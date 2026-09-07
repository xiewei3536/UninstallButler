import AppKit
import SwiftUI
import Combine
import UninstallCore

// MARK: - 自我測試 / 快照（開發用，不會刪除任何檔案）
//   UNINSTALLBUTLER_SELFTEST=1                     掃描 App、對第一個（或指定）App 找殘留、掃殘留檔案，印出結果後結束
//   UNINSTALLBUTLER_SELFTEST_APP="Google Chrome"   指定要分析的 App 名稱
//   UNINSTALLBUTLER_SNAPSHOT=/tmp/ub.png           開視窗、掃完後把主視窗畫成 PNG 後結束
//   UNINSTALLBUTLER_SNAPSHOT_APP="Spotify"         快照時選取的 App
//   UNINSTALLBUTLER_SNAPSHOT_VIEW=leftovers|settings|welcome|confirm
//   UNINSTALLBUTLER_LANG=zh-Hant|zh-Hans|en        覆寫語言
//   UNINSTALLBUTLER_DRYRUN=1                       解除安裝只模擬，不真的刪

let env = ProcessInfo.processInfo.environment
if let lang = env["UNINSTALLBUTLER_LANG"] { Prefs.shared.language = lang }

if env["UNINSTALLBUTLER_SELFTEST"] == "1" {
    SelfTest.run(appName: env["UNINSTALLBUTLER_SELFTEST_APP"])
    exit(0)
}
if env["UNINSTALLBUTLER_SELFTEST_REMOVE"] == "1" {
    // 端對端測試移除引擎：只對自己建立的假 App（com.ubtest.fakeapp）與假殘留動手
    exit(RemovalSelfTest.run() ? 0 : 1)
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let store = AppStore()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if NSApp.applicationIconImage == nil || Bundle.main.bundleIdentifier == nil {
            NSApp.applicationIconImage = NSImage(systemSymbolName: "trash.circle.fill", accessibilityDescription: nil)
        }
        buildMenu()
        Prefs.shared.$language.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.buildMenu()
            self?.window.title = L.appName.s
        }.store(in: &cancellables)

        let root = RootView().environmentObject(store)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1140, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = L.appName.s
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.contentViewController = NSHostingController(rootView: root)
        window.minSize = NSSize(width: 980, height: 620)
        window.setFrameAutosaveName("UninstallButler.Main")
        if !window.setFrameUsingName("UninstallButler.Main") { window.center() }
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        store.refreshApps()
        if env["UNINSTALLBUTLER_SNAPSHOT"] == nil { UpdateChecker.shared.startAutoCheck() }
        if !Prefs.shared.hasSeenWelcome && env["UNINSTALLBUTLER_SNAPSHOT"] == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.store.showWelcome = true }
        }
        setupSnapshotIfRequested()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: 選單列

    private func buildMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L.menuAbout.s, action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: L.menuCheckUpdates.s, action: #selector(checkUpdates), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L.menuSettings.s, action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L.menuHide.s, action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: L.menuHideOthers.s, action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: L.menuShowAll.s, action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L.menuQuit.s, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; main.addItem(appItem)

        let file = NSMenu(title: L.menuFile.s)
        file.addItem(withTitle: L.refresh.s, action: #selector(refresh), keyEquivalent: "r").target = self
        file.addItem(.separator())
        file.addItem(withTitle: L.menuClose.s, action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileItem = NSMenuItem(); fileItem.submenu = file; main.addItem(fileItem)

        let edit = NSMenu(title: L.menuEdit.s)
        edit.addItem(withTitle: L.menuUndo.s, action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: L.menuRedo.s, action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: L.menuCut.s, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L.menuCopy.s, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L.menuPaste.s, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L.menuSelectAll.s, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(); editItem.submenu = edit; main.addItem(editItem)

        let view = NSMenu(title: L.menuView.s)
        let langMenu = NSMenu(title: L.menuLanguage.s)
        for (title, code) in [(L.langAuto.s, "auto"), ("English", "en"), ("繁體中文", "zh-Hant"), ("简体中文", "zh-Hans")] {
            let item = langMenu.addItem(withTitle: title, action: #selector(setLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = Prefs.shared.language == code ? .on : .off
        }
        let langItem = view.addItem(withTitle: L.menuLanguage.s, action: nil, keyEquivalent: "")
        langItem.submenu = langMenu
        let viewItem = NSMenuItem(); viewItem.submenu = view; main.addItem(viewItem)

        let windowMenu = NSMenu(title: L.menuWindow.s)
        windowMenu.addItem(withTitle: L.menuMinimize.s, action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: L.menuZoom.s, action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        let windowItem = NSMenuItem(); windowItem.submenu = windowMenu; main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        let help = NSMenu(title: L.menuHelp.s)
        help.addItem(withTitle: L.menuWelcome.s, action: #selector(showWelcome), keyEquivalent: "").target = self
        help.addItem(withTitle: L.menuFDA.s, action: #selector(openFDA), keyEquivalent: "").target = self
        let helpItem = NSMenuItem(); helpItem.submenu = help; main.addItem(helpItem)
        NSApp.helpMenu = help

        NSApp.mainMenu = main
    }

    @objc private func showAbout() { store.showSettings = true }
    @objc private func checkUpdates() { Task { await UpdateChecker.shared.check(userInitiated: true) } }
    @objc private func showSettings() { store.showSettings = true }
    @objc private func showWelcome() { store.showWelcome = true }
    @objc private func refresh() { store.refreshApps() }
    @objc private func openFDA() { Privileges.openFullDiskAccessSettings() }
    @objc private func setLanguage(_ sender: NSMenuItem) {
        if let code = sender.representedObject as? String { Prefs.shared.language = code }
    }

    // MARK: 快照

    private func setupSnapshotIfRequested() {
        guard let path = env["UNINSTALLBUTLER_SNAPSHOT"] else { return }
        let wantApp = env["UNINSTALLBUTLER_SNAPSHOT_APP"]
        let view = env["UNINSTALLBUTLER_SNAPSHOT_VIEW"] ?? "apps"
        Task { @MainActor [weak self] in
            guard let self else { return }
            let s = self.store
            var ticks = 0
            // 等 App 掃描完成
            while s.isScanningApps && ticks < 60 { try? await Task.sleep(nanoseconds: 500_000_000); ticks += 1 }
            switch view {
            case "leftovers": s.section = .leftovers; s.scanOrphans()
            case "settings": s.showSettings = true
            case "welcome": s.showWelcome = true
            default:
                let target = wantApp.flatMap { name in s.apps.first { $0.name == name } } ?? s.visibleApps.first
                if let t = target { s.selection = [t.id]; s.ensureResidue(for: t) }
            }
            var waited = 0
            while waited < 90 {
                try? await Task.sleep(nanoseconds: 500_000_000); waited += 1
                let ready: Bool
                switch view {
                case "leftovers": ready = s.orphansScanned
                case "settings", "welcome": ready = waited > 3
                case "confirm":
                    if let id = s.selection.first, let app = s.app(for: id), s.residue[id] != nil {
                        if s.flow == nil { s.requestUninstall([app]); ready = false } else { ready = waited > 5 }
                    } else { ready = false }
                default: ready = s.selection.first.map { s.residue[$0] != nil } ?? false
                }
                if ready { break }
            }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            self.snapshot(to: path)
            fflush(stdout)
            exit(0)   // 開發用鉤子：直接結束，不走 terminate（sheet 開著時 terminate 可能不會結束）
        }
    }

    private func snapshot(to path: String) {
        // 若有 sheet 開著就連同 sheet 一起截（擷取整個視窗畫面）
        let target: NSWindow = window.attachedSheet ?? window
        // contentView 的上層是視窗框（含標題列與工具列），一起截才看得到工具列按鈕
        guard let view = target.contentView?.superview ?? target.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("snapshot written: \(path) lang=\(Prefs.shared.language)")
        }
    }
}

// MARK: - 自我測試

enum SelfTest {
    static func run(appName: String?) {
        var failures = 0
        func check(_ cond: Bool, _ what: String) {
            print((cond ? "  ✓ " : "  ✗ ") + what)
            if !cond { failures += 1 }
        }
        print("== 邏輯檢查")
        check(Names.stripKnownSuffixes("com.foo.bar.plist") == "com.foo.bar", "stripKnownSuffixes plist")
        check(Names.stripKnownSuffixes("com.foo.bar.savedState") == "com.foo.bar", "stripKnownSuffixes savedState")
        check(Names.stripByHostUUID("com.foo.bar.0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0") == "com.foo.bar", "stripByHostUUID")
        check(Names.looksLikeBundleID("com.google.Chrome") && !Names.looksLikeBundleID("Google") && !Names.looksLikeBundleID("com.foo"), "looksLikeBundleID")
        check(!Names.isSafeMatchName("App") && Names.isSafeMatchName("Spotify"), "isSafeMatchName")
        let home = NSHomeDirectory()
        check(PathSafety.isSafeToRemove(URL(fileURLWithPath: home + "/Library/Caches/com.foo.bar")), "PathSafety allows ~/Library/Caches/x")
        check(!PathSafety.isSafeToRemove(URL(fileURLWithPath: home + "/Library/Caches")), "PathSafety refuses ~/Library/Caches")
        check(!PathSafety.isSafeToRemove(URL(fileURLWithPath: home)), "PathSafety refuses home")
        check(!PathSafety.isSafeToRemove(URL(fileURLWithPath: "/Applications")), "PathSafety refuses /Applications")
        check(!PathSafety.isSafeToRemove(URL(fileURLWithPath: home + "/Documents/x")), "PathSafety refuses ~/Documents")
        check(!PathSafety.isSafeToRemove(URL(fileURLWithPath: "/System/Library/x")), "PathSafety refuses /System")

        var chrome = InstalledApp(url: URL(fileURLWithPath: "/Applications/Google Chrome.app"))
        chrome.bundleID = "com.google.Chrome"; chrome.name = "Google Chrome"; chrome.helperBundleIDs = ["com.google.Chrome.helper"]
        var canary = InstalledApp(url: URL(fileURLWithPath: "/Applications/Google Chrome Canary.app"))
        canary.bundleID = "com.google.Chrome.canary"; canary.name = "Google Chrome Canary"
        let m = ResidueFinder.Matcher(app: chrome, context: .init(installedApps: [chrome, canary]))
        check(m.idMatch("com.google.Chrome.plist") == "com.google.chrome", "idMatch own prefs")
        check(m.idMatch("com.google.Chrome.helper.plist") == "com.google.chrome.helper", "idMatch helper")
        check(m.idMatch("com.google.Chrome.canary.plist") == nil, "idMatch does not steal Canary's prefs")
        check(m.idMatch("com.google.keystone.agent.plist") == nil, "idMatch ignores vendor siblings")
        check(m.vendorToken == "google" && m.productMatch("Chrome") != nil, "vendor folder + product token")
        check(m.programIsInsideApp(["ProgramArguments": ["/Applications/Google Chrome.app/Contents/MacOS/x"]]), "programIsInsideApp")
        var itm = ResidueItem(url: URL(fileURLWithPath: "/Library/Application Support/It's Here"), category: .appSupport, isDirectory: true, requiresAdmin: true, matchedBy: .name("x"))
        itm.pruneParentIfEmpty = false
        let script = Remover.buildAdminScript([itm], mode: .permanent, uid: 501, gid: 20)
        check(script.contains("/bin/rm -rf '/Library/Application Support/It'\\''s Here'"), "admin script quoting")
        print(failures == 0 ? "  全部通過" : "  ✗ \(failures) 項失敗")

        print("\n== 掃描 App（\(Prefs.shared.appFolders.map(\.path).joined(separator: ", "))）")
        let t0 = Date()
        let apps = AppScanner.scan(folders: Prefs.shared.appFolders)
        print("  找到 \(apps.count) 個 App，耗時 \(String(format: "%.2f", Date().timeIntervalSince(t0))) 秒")
        for a in apps.sorted(by: { $0.name < $1.name }) {
            let arch = a.archDescription.rawValue
            print("  • \(a.name) [\(a.bundleID ?? "-")] v\(a.version ?? "-") \(arch) helpers=\(a.helperBundleIDs.count) groups=\(a.appGroups.count) team=\(a.teamID ?? "-")\(a.isSandboxed ? " sandbox" : "")\(a.isAppStore ? " MAS" : "")")
        }

        let target = appName.flatMap { n in apps.first { $0.name == n } } ?? apps.first
        if var t = target {
            print("\n== 殘留分析：\(t.name)")
            let t1 = Date()
            t.sizeBytes = SizeCalculator.bundleSize(of: t.resolvedURL)
            let items = ResidueFinder.find(for: t, context: .init(installedApps: apps))
            print("  \(items.count) 個項目，耗時 \(String(format: "%.2f", Date().timeIntervalSince(t1))) 秒")
            for i in items {
                let flags = (i.requiresAdmin ? " [admin]" : "") + (i.defaultSelected ? "" : " [unchecked]") + (i.cautions.isEmpty ? "" : " \(i.cautions)")
                print("  • [\(i.category.rawValue)] \(Paths.abbreviated(i.url.path))  \(Fmt.bytes(i.sizeBytes))\(flags)")
            }
        }

        print("\n== 殘留檔案（孤兒）掃描")
        let t2 = Date()
        let orphans = OrphanScanner.scan(installedApps: apps)
        print("  \(orphans.count) 個候選，耗時 \(String(format: "%.2f", Date().timeIntervalSince(t2))) 秒")
        for o in orphans.prefix(60) {
            print("  • [\(o.confidence.rawValue)] [\(o.category.rawValue)] \(Paths.abbreviated(o.url.path))  \(Fmt.bytes(o.sizeBytes))\(o.relatedApps.isEmpty ? "" : "  related: \(o.relatedApps.joined(separator: ", "))")")
        }
        print("\n完整磁碟取用：\(Privileges.hasFullDiskAccess() ? "已授權" : "未授權")")
        if failures > 0 { exit(1) }
    }
}

// MARK: - 移除引擎端對端測試（合成資料）

enum RemovalSelfTest {
    static let fakeID = "com.ubtest.fakeapp"
    static let fakeName = "UBTest Fake App"

    static func run() -> Bool {
        var failures = 0
        func check(_ cond: Bool, _ what: String) {
            print((cond ? "  ✓ " : "  ✗ ") + what)
            if !cond { failures += 1 }
        }
        let fm = FileManager.default
        let lib = Paths.userLibrary
        let appsDir = Paths.home.appendingPathComponent("Applications", isDirectory: true)
        let appURL = appsDir.appendingPathComponent("\(fakeName).app", isDirectory: true)

        // 假殘留（全部用獨一無二的名字，測試後會全部清掉）
        let fixtures: [URL] = [
            lib.appendingPathComponent("Caches/\(fakeID)"),
            lib.appendingPathComponent("Preferences/\(fakeID).plist"),
            lib.appendingPathComponent("Application Support/\(fakeName)"),
            lib.appendingPathComponent("Application Support/UBTest/FakeApp"),
            lib.appendingPathComponent("Saved Application State/\(fakeID).savedState"),
            lib.appendingPathComponent("LaunchAgents/\(fakeID).agent.plist"),
            lib.appendingPathComponent("Logs/\(fakeName)"),
            lib.appendingPathComponent("HTTPStorages/\(fakeID)"),
        ]
        let vendorParent = lib.appendingPathComponent("Application Support/UBTest")

        func cleanupEverything() {
            for u in fixtures + [appURL, vendorParent] { try? fm.removeItem(at: u) }
            for t in FS.children(of: Paths.trash) where t.lastPathComponent.lowercased().contains("ubtest") || t.lastPathComponent.contains(fakeName) || t.lastPathComponent == "FakeApp" {
                try? fm.removeItem(at: t)
            }
        }

        print("== 建立假 App 與假殘留")
        cleanupEverything()
        do {
            try fm.createDirectory(at: appURL.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            let info: [String: Any] = ["CFBundleIdentifier": fakeID, "CFBundleName": fakeName, "CFBundleExecutable": "UBTestFakeApp",
                                       "CFBundleShortVersionString": "1.0", "CFBundlePackageType": "APPL"]
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try data.write(to: appURL.appendingPathComponent("Contents/Info.plist"))
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: appURL.appendingPathComponent("Contents/MacOS/UBTestFakeApp"))
            for u in fixtures {
                if u.pathExtension == "plist" {
                    let plist: [String: Any] = u.lastPathComponent.contains(".agent")
                        ? ["Label": "\(fakeID).agent", "ProgramArguments": [appURL.appendingPathComponent("Contents/MacOS/UBTestFakeApp").path], "RunAtLoad": false]
                        : ["hello": "world"]
                    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: u)
                } else {
                    try fm.createDirectory(at: u, withIntermediateDirectories: true)
                    try Data(repeating: 0x41, count: 64 * 1024).write(to: u.appendingPathComponent("blob.bin"))
                }
            }
        } catch {
            print("  ✗ 無法建立測試資料：\(error)")
            cleanupEverything()
            return false
        }
        check(fixtures.allSatisfy { FS.exists($0) }, "\(fixtures.count) 個假殘留已建立")

        print("== 掃描與比對")
        let apps = AppScanner.scan(folders: Prefs.shared.appFolders)
        guard let app = apps.first(where: { $0.bundleID == fakeID }) else {
            print("  ✗ 掃描沒有找到假 App"); cleanupEverything(); return false
        }
        check(app.name == fakeName, "顯示名稱 = \(app.name)")
        let items = ResidueFinder.find(for: app, context: .init(installedApps: apps))
        let found = Set(items.map { $0.url.path })
        for f in fixtures { check(found.contains(f.path), "找到 \(Paths.abbreviated(f.path))") }
        check(found.contains(appURL.path), "找到 App 本體")
        let unexpected = found.subtracting(fixtures.map(\.path) + [appURL.path])
        check(unexpected.isEmpty, "沒有誤判其他檔案\(unexpected.isEmpty ? "" : "：\(unexpected)")")
        let vendorItem = items.first { $0.url.path == vendorParent.appendingPathComponent("FakeApp").path }
        check(vendorItem?.pruneParentIfEmpty == true, "廠商資料夾子項目會順手清掉空的上層")
        check(items.first { $0.category == .launchAgents }?.launchdLabel == "\(fakeID).agent", "LaunchAgent 讀到 Label")
        check(items.allSatisfy { !$0.requiresAdmin }, "全部不需管理員密碼")

        print("== 移除（移到垃圾桶）")
        let report = Remover.uninstall(apps: [app], items: items, options: RemovalOptions(mode: .trash)) { _ in }
        check(report.failed.isEmpty, "沒有失敗項目\(report.failed.isEmpty ? "" : "：\(report.failed.map { "\($0.item.url.lastPathComponent) \($0.status)" })")")
        check(report.removed.count == items.count, "移除 \(report.removed.count)/\(items.count)")
        for f in fixtures + [appURL] { check(!FS.exists(f), "已不在原位：\(Paths.abbreviated(f.path))") }
        check(!FS.exists(vendorParent), "空的廠商資料夾 UBTest 已順手移除")
        if FS.isReadable(Paths.trash) {
            let trashed = FS.children(of: Paths.trash).filter { $0.lastPathComponent.lowercased().contains("ubtest") || $0.lastPathComponent.contains(fakeName) || $0.lastPathComponent == "FakeApp" }
            check(trashed.count >= fixtures.count, "垃圾桶裡有 \(trashed.count) 個對應項目（可復原）")
        } else {
            print("  – 無法檢視垃圾桶內容（~/.Trash 需要完整磁碟取用），略過此檢查")
        }
        check(report.freedBytes > 0, "統計釋放空間 \(Fmt.bytes(report.freedBytes))")

        print("== 清理測試資料")
        cleanupEverything()
        print(failures == 0 ? "全部通過" : "✗ \(failures) 項失敗")
        return failures == 0
    }
}

// MARK: - 進入點

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
