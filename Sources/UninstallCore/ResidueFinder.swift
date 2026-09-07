import Foundation
import AppKit

/// 針對一個 App，找出它散落在系統各處的所有相關檔案
public enum ResidueFinder {

    public struct Context {
        public var installedApps: [InstalledApp]
        public var extraAppFolders: [URL] = []
        public init(installedApps: [InstalledApp], extraAppFolders: [URL] = []) {
            self.installedApps = installedApps
            self.extraAppFolders = extraAppFolders
        }
    }

    // MARK: - 位置表

    struct Location {
        let url: URL
        let category: ResidueCategory
        var allowName = false
        var allowVendor = false
        var bundlesOnly = false      // 條目本身是 bundle（讀它的 Info.plist 來比對）
        var crashLogs = false        // 崩潰紀錄命名規則
        var launchd = false          // launchd plist
        var defaultSelected = true
        var ids = true               // 允許用 bundle ID 比對
    }

    static func userLocations() -> [Location] {
        let lib = Paths.userLibrary
        func L(_ rel: String, _ cat: ResidueCategory, name: Bool = false, vendor: Bool = false, bundles: Bool = false, crash: Bool = false, launchd: Bool = false, selected: Bool = true) -> Location {
            Location(url: lib.appendingPathComponent(rel, isDirectory: true), category: cat, allowName: name, allowVendor: vendor, bundlesOnly: bundles, crashLogs: crash, launchd: launchd, defaultSelected: selected)
        }
        return [
            L("Application Support", .appSupport, name: true, vendor: true),
            L("Caches", .caches, name: true, vendor: true),
            L("Preferences", .preferences),
            L("Preferences/ByHost", .preferences),
            L("Saved Application State", .savedState),
            L("Containers", .container),
            L("HTTPStorages", .webData),
            L("WebKit", .webData),
            L("Cookies", .webData),
            L("Logs", .logs, name: true, vendor: true),
            L("Logs/DiagnosticReports", .crashReports, crash: true),
            L("Logs/DiagnosticReports/Retired", .crashReports, crash: true),
            L("Application Support/CrashReporter", .crashReports, crash: true),
            L("LaunchAgents", .launchAgents, launchd: true),
            L("Application Scripts", .appScripts),
            L("Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments", .recentDocuments),
            L("Internet Plug-Ins", .plugins, name: true, bundles: true),
            L("QuickLook", .plugins, name: true, bundles: true),
            L("PreferencePanes", .plugins, name: true, bundles: true),
            L("Services", .plugins, name: true, bundles: true),
            L("Spotlight", .plugins, name: true, bundles: true),
            L("Input Methods", .plugins, name: true, bundles: true),
            L("Screen Savers", .plugins, name: true, bundles: true),
            L("Audio/Plug-Ins/Components", .plugins, name: true, bundles: true),
            L("Audio/Plug-Ins/VST", .plugins, name: true, bundles: true),
            L("Audio/Plug-Ins/VST3", .plugins, name: true, bundles: true),
            L("Audio/Plug-Ins/HAL", .plugins, name: true, bundles: true),
            L("Contextual Menu Items", .plugins, name: true, bundles: true),
        ]
    }

    static func systemLocations() -> [Location] {
        let lib = Paths.systemLibrary
        func L(_ rel: String, _ cat: ResidueCategory, name: Bool = false, vendor: Bool = false, bundles: Bool = false, crash: Bool = false, launchd: Bool = false, selected: Bool = true) -> Location {
            Location(url: lib.appendingPathComponent(rel, isDirectory: true), category: cat, allowName: name, allowVendor: vendor, bundlesOnly: bundles, crashLogs: crash, launchd: launchd, defaultSelected: selected)
        }
        var locs = [
            L("Application Support", .appSupport, name: true, vendor: true),
            L("Caches", .caches, name: true, vendor: true),
            L("Preferences", .preferences),
            L("Logs", .logs, name: true, vendor: true),
            L("Logs/DiagnosticReports", .crashReports, crash: true),
            L("Logs/DiagnosticReports/Retired", .crashReports, crash: true),
            L("LaunchAgents", .launchAgents, launchd: true),
            L("LaunchDaemons", .launchDaemons, launchd: true),
            L("PrivilegedHelperTools", .privilegedHelper),
            L("Internet Plug-Ins", .plugins, name: true, bundles: true),
            L("QuickLook", .plugins, name: true, bundles: true),
            L("PreferencePanes", .plugins, name: true, bundles: true),
            L("Spotlight", .plugins, name: true, bundles: true),
            L("Input Methods", .plugins, name: true, bundles: true),
            L("Screen Savers", .plugins, name: true, bundles: true),
            L("Audio/Plug-Ins/Components", .plugins, name: true, bundles: true),
            L("Audio/Plug-Ins/VST", .plugins, name: true, bundles: true),
            L("Audio/Plug-Ins/VST3", .plugins, name: true, bundles: true),
            L("Audio/Plug-Ins/HAL", .plugins, name: true, bundles: true),
            L("Extensions", .plugins, bundles: true),
            L("Frameworks", .other, bundles: true, selected: false),
            L("StartupItems", .launchDaemons, name: true),
        ]
        locs.append(Location(url: URL(fileURLWithPath: "/Users/Shared", isDirectory: true), category: .other, allowName: true, allowVendor: true, defaultSelected: false))
        return locs
    }

    // MARK: - 比對器

    public struct Matcher {
        let app: InstalledApp
        let appPath: String
        let ids: [String]              // 自己的 bundle ID（小寫）
        let otherIDs: [String]         // 其他 App 的 bundle ID（小寫）— 用來排除「更長的前綴屬於別人」
        let names: Set<String>         // 正規化後的名稱
        let productTokens: Set<String> // 廠商資料夾底下用的產品名
        public let vendorToken: String?// 正規化後的廠商名（com.google.Chrome → google）
        let vendorPrefix: String?      // com.google
        let crashPrefixes: Set<String> // 崩潰紀錄檔名前綴（正規化）
        let groups: Set<String>        // App Groups（小寫）
        let teamID: String?
        let groupOwners: [String: [String]] // group → 其他也宣告此 group 的 App 名稱
        /// 自己的輔助程式 ID 中，也被其他已安裝 App 內嵌的（共用更新器等）→ 其他 App 名稱
        let sharedHelperOwners: [String: [String]]
        /// 這是該開發者（廠商前綴）唯一安裝的 App：可以把開發者層級的共用元件一併帶走
        public let isSoleVendorApp: Bool
        public let vendorName: String?  // 顯示用（com.google → google）

        public init(app: InstalledApp, context: Context) {
            self.app = app
            appPath = app.resolvedURL.path
            ids = app.allBundleIDs.map { $0.lowercased() }
            var others: [String] = []
            var otherNames = Set<String>()
            var owners: [String: [String]] = [:]
            var helperOwners: [String: [String]] = [:]
            let myHelpers = Set(app.helperBundleIDs.map { $0.lowercased() })
            var sameVendorOthers = 0
            let myVendor = app.bundleID.flatMap(Names.vendorPrefix)
            for o in context.installedApps where o.url != app.url {
                let oIDs = o.allBundleIDs.map { $0.lowercased() }
                others += oIDs
                for id in oIDs where myHelpers.contains(id) { helperOwners[id, default: []].append(o.name) }
                for n in [o.name, o.bundleName, o.executableName].compactMap({ $0 }) { otherNames.insert(Names.normalized(n)) }
                for g in o.appGroups { owners[g.lowercased(), default: []].append(o.name) }
                if let v = myVendor, let ov = o.bundleID.flatMap(Names.vendorPrefix), ov == v { sameVendorOthers += 1 }
            }
            // 其他 App 也內嵌的共用 ID 不能算「別人的更長前綴」，否則會互相排除
            otherIDs = others.filter { !myHelpers.contains($0) }
            groupOwners = owners
            sharedHelperOwners = helperOwners
            isSoleVendorApp = myVendor != nil && sameVendorOthers == 0 && !Names.genericVendorPrefixes.contains(myVendor!) && !app.isAppleApp
            vendorName = myVendor.map { String($0.split(separator: ".")[1]) }

            var nameSet = Set<String>()
            var candidates = [app.name, app.bundleName, app.executableName, app.url.deletingPathExtension().lastPathComponent].compactMap { $0 }
            if let id = app.bundleID, let last = id.split(separator: ".").last { candidates.append(String(last)) }
            for c in candidates where Names.isSafeMatchName(c) {
                let n = Names.normalized(c)
                if !otherNames.contains(n) { nameSet.insert(n) }
            }
            productTokens = nameSet
            // 頂層名稱比對：排除只有一個字、太短或跟廠商同名的
            names = nameSet.filter { $0.count >= 4 }

            var crash = Set<String>()
            for c in [app.executableName, app.bundleName, app.name].compactMap({ $0 }) where Names.isSafeMatchName(c) { crash.insert(Names.normalized(c)) }
            crashPrefixes = crash

            if let id = app.bundleID, let vp = Names.vendorPrefix(id), !Names.genericVendorPrefixes.contains(vp), !(app.isAppleApp) {
                vendorPrefix = vp
                vendorToken = Names.normalized(String(vp.split(separator: ".")[1]))
            } else {
                vendorPrefix = nil
                vendorToken = nil
            }
            groups = Set(app.appGroups.map { $0.lowercased() })
            teamID = app.teamID
        }

        /// 條目名稱是否屬於這個 App 的某個 bundle ID；回傳命中的 ID。
        /// 若有「其他 App」的 ID 是更長的前綴，則判定屬於別人。
        public func idMatch(_ entryName: String) -> String? {
            let lower = entryName.lowercased()
            let base = Names.stripByHostUUID(Names.stripKnownSuffixes(lower))
            func matchLen(_ id: String) -> Int? {
                if base == id { return id.count + 1 }
                if base.hasPrefix(id + ".") || base.hasPrefix(id + "-") || base.hasPrefix(id + "_") { return id.count }
                return nil
            }
            var best: (id: String, len: Int, mine: Bool)?
            for id in ids { if let l = matchLen(id), l > (best?.len ?? -1) { best = (id, l, true) } }
            for id in otherIDs { if let l = matchLen(id), l > (best?.len ?? -1) { best = (id, l, false) } }
            guard let b = best, b.mine else { return nil }
            return b.id
        }

        /// 開發者層級的共用元件（com.google.keystone…）：只有在這是該開發者唯一安裝的 App 時才成立
        public func vendorPrefixMatch(_ entryName: String) -> String? {
            guard isSoleVendorApp, let vp = vendorPrefix else { return nil }
            let lower = entryName.lowercased()
            let base = Names.stripByHostUUID(Names.stripKnownSuffixes(lower))
            guard base == vp || base.hasPrefix(vp + ".") else { return nil }
            // 其他 App 的 ID 若是更長前綴（理論上不會，因為同廠商就不是 sole），保守排除
            for id in otherIDs where base == id || base.hasPrefix(id + ".") { return nil }
            return vp
        }

        public func nameMatch(_ entryName: String, isDirectory: Bool) -> String? {
            var base = entryName
            if !isDirectory || entryName.contains(".") {
                // 檔案：去掉一層副檔名（Foo.log / Foo.plist）
                let ext = (entryName as NSString).pathExtension
                if !ext.isEmpty, ext.count <= 12 { base = (entryName as NSString).deletingPathExtension }
            }
            let n = Names.normalized(base)
            guard n.count >= 4 else { return nil }
            return names.contains(n) ? n : nil
        }

        public func productMatch(_ entryName: String) -> String? {
            let n = Names.normalized((entryName as NSString).deletingPathExtension)
            if productTokens.contains(n) { return n }
            return idMatch(entryName)
        }

        /// 崩潰紀錄：Name_2024-01-01-120000_host.ips / Name-2024…crash / Name_UUID.plist
        public func crashMatch(_ fileName: String) -> String? {
            let base = (fileName as NSString).deletingPathExtension
            var heads: [String] = []
            if let i = base.firstIndex(of: "_") { heads.append(String(base[..<i])) }
            if let i = base.firstIndex(of: "-") { heads.append(String(base[..<i])) }
            heads.append(base)
            for h in heads {
                let n = Names.normalized(h)
                if n.count >= 3, crashPrefixes.contains(n) { return n }
            }
            return nil
        }

        public func programIsInsideApp(_ plist: [String: Any]) -> Bool {
            var paths: [String] = []
            if let p = plist["Program"] as? String { paths.append(p) }
            if let args = plist["ProgramArguments"] as? [String], let first = args.first { paths.append(first) }
            for p in paths {
                let std = (p as NSString).standardizingPath
                if std == appPath || std.hasPrefix(appPath + "/") { return true }
            }
            return false
        }
    }

    // MARK: - 主流程

    public static func find(for app: InstalledApp, context: Context) -> [ResidueItem] {
        let m = Matcher(app: app, context: context)
        var items: [ResidueItem] = []

        // 1. App 本體
        var main = ResidueItem(url: app.url, category: .appBundle, isDirectory: true,
                               requiresAdmin: !FS.currentUserCanDelete(app.url), matchedBy: .isApp)
        main.sizeBytes = app.sizeBytes
        items.append(main)
        if app.resolvedURL.path != app.url.path {
            var target = ResidueItem(url: app.resolvedURL, category: .appBundle, isDirectory: true,
                                     requiresAdmin: !FS.currentUserCanDelete(app.resolvedURL), matchedBy: .symlinkTarget)
            target.sizeBytes = app.sizeBytes
            items.append(target)
        }

        // 2. Library 各處
        for loc in userLocations() + systemLocations() {
            items += scan(location: loc, matcher: m)
        }

        // 3. Group Containers
        items += groupContainers(m)
        // 3b. ~/Library/<廠商> 與 /Library/<廠商>（例如 ~/Library/Google）
        items += vendorTopLevelFolders(m)

        // 4. 安裝收據
        items += receipts(m)

        // 5. 指令列捷徑（symlink 指向 App 內）
        items += commandLineLinks(m)

        // 6. /var/folders 快取與暫存
        items += temporaryFiles(m)

        // 去重 + 排序
        var seen = Set<String>()
        items = items.filter { seen.insert($0.url.path).inserted }
        items = items.filter { $0.url.path != app.url.path || $0.category == .appBundle }
        items.sort { a, b in
            let ia = ResidueCategory.displayOrder.firstIndex(of: a.category) ?? 99
            let ib = ResidueCategory.displayOrder.firstIndex(of: b.category) ?? 99
            if ia != ib { return ia < ib }
            return a.url.path.localizedStandardCompare(b.url.path) == .orderedAscending
        }
        for i in items.indices { items[i].ownerAppPath = app.url.path }

        computeSizes(&items)
        return items
    }

    // MARK: 掃描單一位置

    static func scan(location loc: Location, matcher m: Matcher) -> [ResidueItem] {
        guard FS.isDirectory(loc.url) else { return [] }
        var out: [ResidueItem] = []

        for child in FS.children(of: loc.url) {
            let name = child.lastPathComponent
            if name == ".DS_Store" || name == ".localized" { continue }
            let isDir = FS.isDirectory(child)
            var reason: MatchReason?
            var cautions: [Caution] = []
            var label: String?

            if loc.launchd {
                guard child.pathExtension == "plist", let plist = FS.readPlist(child) else { continue }
                label = plist["Label"] as? String
                if let id = m.idMatch(name) { reason = .bundleID(id) }
                else if let lbl = label, let id = m.idMatch(lbl) { reason = .bundleID(id) }
                else if m.programIsInsideApp(plist) { reason = .programPath }
                else if let vp = m.vendorPrefixMatch(name) ?? label.flatMap({ m.vendorPrefixMatch($0) }) { reason = .vendorPrefix(vp); cautions.append(.sameDeveloper) }
            } else if loc.category == .container {
                // 沙盒容器：先看中繼資料指向哪個 App（最精確），再退回名稱比對
                if let meta = ContainerMetadata.read(child), let owner = meta.appBundlePath {
                    let std = (owner as NSString).standardizingPath
                    if std == m.appPath || std.hasPrefix(m.appPath + "/") { reason = .containerOwner }
                    else if FS.exists(URL(fileURLWithPath: std)) { continue } // 屬於別的 App
                }
                if reason == nil, let id = m.idMatch(name) { reason = .bundleID(id) }
                if reason == nil, let vp = m.vendorPrefixMatch(name) { reason = .vendorPrefix(vp); cautions.append(.sameDeveloper) }
            } else if loc.crashLogs {
                if let id = m.idMatch(name) { reason = .bundleID(id) }
                else if let n = m.crashMatch(name) { reason = .name(n) }
            } else if loc.bundlesOnly {
                guard isDir else { continue }
                if let bid = FS.bundleIdentifier(ofBundleAt: child), let id = m.idMatch(bid) { reason = .bundleID(id) }
                else if let id = m.idMatch(name) { reason = .bundleID(id) }
                else if loc.allowName, let n = m.nameMatch(name, isDirectory: true) { reason = .name(n); cautions.append(.nameMatchOnly) }
            } else {
                if loc.ids, let id = m.idMatch(name) { reason = .bundleID(id) }
                else if loc.allowName, let n = m.nameMatch(name, isDirectory: isDir) { reason = .name(n); cautions.append(.nameMatchOnly) }
                else if loc.ids, let vp = m.vendorPrefixMatch(name) { reason = .vendorPrefix(vp); cautions.append(.sameDeveloper) }
                else if loc.allowVendor, isDir, let vendor = m.vendorToken, Names.normalized(name) == vendor {
                    // 廠商資料夾：只拿底下屬於這個產品的子項目
                    for sub in FS.children(of: child) where sub.lastPathComponent != ".DS_Store" {
                        if let p = m.productMatch(sub.lastPathComponent) {
                            var item = ResidueItem(url: sub, category: loc.category, isDirectory: FS.isDirectory(sub),
                                                   requiresAdmin: !FS.currentUserCanDelete(sub),
                                                   matchedBy: .vendorFolder(vendor: name, product: p))
                            item.pruneParentIfEmpty = true
                            item.defaultSelected = loc.defaultSelected
                            out.append(item)
                        }
                    }
                    continue
                }
            }

            guard let r = reason else { continue }
            var item = ResidueItem(url: child, category: loc.category, isDirectory: isDir,
                                   requiresAdmin: !FS.currentUserCanDelete(child), matchedBy: r)
            item.cautions += cautions
            item.launchdLabel = label
            item.defaultSelected = loc.defaultSelected
            // 透過「與其他 App 共用的輔助程式 ID」比對到的：標示並預設不勾
            if case .bundleID(let id) = r, let owners = m.sharedHelperOwners[id], !owners.isEmpty {
                item.cautions.append(.sharedWith(owners))
                item.defaultSelected = false
            }
            out.append(item)
        }
        return out
    }

    // MARK: ~/Library/<廠商>

    static func vendorTopLevelFolders(_ m: Matcher) -> [ResidueItem] {
        guard let vendor = m.vendorToken else { return [] }
        var out: [ResidueItem] = []
        for lib in [Paths.userLibrary, Paths.systemLibrary] {
            for child in FS.children(of: lib, includeHidden: false) where FS.isDirectory(child) && Names.normalized(child.lastPathComponent) == vendor {
                if m.isSoleVendorApp {
                    var item = ResidueItem(url: child, category: .appSupport, isDirectory: true,
                                           requiresAdmin: !FS.currentUserCanDelete(child), matchedBy: .vendorPrefix(m.vendorPrefix ?? vendor))
                    item.cautions.append(.sameDeveloper)
                    out.append(item)
                } else {
                    for sub in FS.children(of: child) where sub.lastPathComponent != ".DS_Store" {
                        if let p = m.productMatch(sub.lastPathComponent) {
                            var item = ResidueItem(url: sub, category: .appSupport, isDirectory: FS.isDirectory(sub),
                                                   requiresAdmin: !FS.currentUserCanDelete(sub),
                                                   matchedBy: .vendorFolder(vendor: child.lastPathComponent, product: p))
                            item.pruneParentIfEmpty = true
                            out.append(item)
                        }
                    }
                }
            }
        }
        return out
    }

    // MARK: Group Containers / Application Scripts（依簽章宣告）

    static func groupContainers(_ m: Matcher) -> [ResidueItem] {
        var out: [ResidueItem] = []
        let roots: [(URL, ResidueCategory)] = [
            (Paths.userLibrary.appendingPathComponent("Group Containers"), .groupContainer),
            (Paths.userLibrary.appendingPathComponent("Application Scripts"), .appScripts),
        ]
        for (root, cat) in roots {
            guard FS.isDirectory(root) else { continue }
            for child in FS.children(of: root) {
                let name = child.lastPathComponent
                let lower = name.lowercased()
                var reason: MatchReason?
                if m.groups.contains(lower) { reason = .entitlement(name) }
                else if let team = m.teamID, lower.hasPrefix(team.lowercased() + ".") {
                    let rest = String(name.dropFirst(team.count + 1))
                    if let id = m.idMatch(rest) { reason = .bundleID(id) }
                    else if m.groups.contains(rest.lowercased()) { reason = .entitlement(name) }
                }
                if reason == nil, lower.hasPrefix("group."), let id = m.idMatch(String(name.dropFirst(6))) { reason = .bundleID(id) }
                if reason == nil, lower.hasPrefix("group."), let vp = m.vendorPrefixMatch(String(name.dropFirst(6))) { reason = .vendorPrefix(vp) }
                if reason == nil, let team = m.teamID, m.isSoleVendorApp, lower.hasPrefix(team.lowercased() + ".") { reason = .vendorPrefix(team) }
                guard let r = reason else { continue }
                var item = ResidueItem(url: child, category: cat, isDirectory: FS.isDirectory(child),
                                       requiresAdmin: !FS.currentUserCanDelete(child), matchedBy: r)
                if let owners = m.groupOwners[lower], !owners.isEmpty {
                    item.cautions.append(.sharedWith(owners))
                    item.defaultSelected = false
                }
                if case .vendorPrefix = r { item.cautions.append(.sameDeveloper) }
                out.append(item)
            }
        }
        return out
    }

    // MARK: 安裝收據

    static func receipts(_ m: Matcher) -> [ResidueItem] {
        guard FS.isDirectory(Paths.receipts) else { return [] }
        var byID: [String: (plist: URL?, bom: URL?)] = [:]
        for child in FS.children(of: Paths.receipts) {
            let ext = child.pathExtension
            guard ext == "plist" || ext == "bom" else { continue }
            let rid = child.deletingPathExtension().lastPathComponent
            var hit = m.idMatch(rid) != nil
            if !hit, let vendor = m.vendorToken {
                // com.microsoft.package.Microsoft_Word.app：同廠商 + 含產品名
                let norm = Names.normalized(rid)
                let comps = rid.lowercased().split(separator: ".").map { Names.normalized(String($0)) }
                if comps.contains(vendor) {
                    hit = m.productTokens.contains { $0.count >= 5 && norm.contains($0) }
                }
            }
            guard hit else { continue }
            var entry = byID[rid] ?? (nil, nil)
            if ext == "plist" { entry.plist = child } else { entry.bom = child }
            byID[rid] = entry
        }
        return byID.compactMap { rid, files in
            guard let anchor = files.plist ?? files.bom else { return nil }
            var item = ResidueItem(url: anchor, category: .receipts, isDirectory: false, requiresAdmin: true, matchedBy: .receipt(rid))
            item.receiptID = rid
            item.sizeBytes = [files.plist, files.bom].compactMap { $0 }.reduce(0) { $0 + SizeCalculator.size(of: $1) }
            return item
        }
    }

    // MARK: 指令列捷徑

    static func commandLineLinks(_ m: Matcher) -> [ResidueItem] {
        let dirs = [URL(fileURLWithPath: "/usr/local/bin"), URL(fileURLWithPath: "/opt/homebrew/bin"),
                    Paths.home.appendingPathComponent(".local/bin"), Paths.home.appendingPathComponent("bin")]
        var out: [ResidueItem] = []
        for dir in dirs where FS.isDirectory(dir) {
            for child in FS.children(of: dir) {
                guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: child.path) else { continue }
                let abs = dest.hasPrefix("/") ? dest : dir.appendingPathComponent(dest).path
                let std = (abs as NSString).standardizingPath
                if std.hasPrefix(m.appPath + "/") {
                    var item = ResidueItem(url: child, category: .commandLine, isDirectory: false,
                                           requiresAdmin: !FS.currentUserCanDelete(child), matchedBy: .symlinkTarget)
                    item.sizeBytes = 0
                    out.append(item)
                }
            }
        }
        return out
    }

    // MARK: /var/folders

    static func temporaryFiles(_ m: Matcher) -> [ResidueItem] {
        var out: [ResidueItem] = []
        for dir in [Paths.userCacheDir, Paths.userTempDir].compactMap({ $0 }) where FS.isDirectory(dir) {
            for child in FS.children(of: dir) {
                let name = child.lastPathComponent
                if let id = m.idMatch(name) {
                    out.append(ResidueItem(url: child, category: .temporary, isDirectory: FS.isDirectory(child),
                                           requiresAdmin: !FS.currentUserCanDelete(child), matchedBy: .bundleID(id)))
                } else if let vp = m.vendorPrefixMatch(name) {
                    var item = ResidueItem(url: child, category: .temporary, isDirectory: FS.isDirectory(child),
                                           requiresAdmin: !FS.currentUserCanDelete(child), matchedBy: .vendorPrefix(vp))
                    item.cautions.append(.sameDeveloper)
                    out.append(item)
                }
            }
        }
        return out
    }

    // MARK: 大小

    static func computeSizes(_ items: inout [ResidueItem]) {
        let lock = NSLock()
        var sizes = [Int: Int64]()
        let indices = items.indices.filter { items[$0].sizeBytes == nil }
        DispatchQueue.concurrentPerform(iterations: indices.count) { k in
            let i = indices[k]
            let s = SizeCalculator.size(of: items[i].url)
            lock.lock(); sizes[i] = s; lock.unlock()
        }
        for (i, s) in sizes { items[i].sizeBytes = s }
    }
}
