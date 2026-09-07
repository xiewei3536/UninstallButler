import Foundation
import AppKit

// MARK: - 路徑安全網

/// 不論比對邏輯出什麼錯，這裡是最後一道防線：只允許刪除已知根目錄底下的「內容」，絕不刪根目錄本身
public enum PathSafety {
    static var allowedRoots: [String] {
        var roots = [
            "/Applications", Paths.home.appendingPathComponent("Applications").path,
            Paths.userLibrary.path, Paths.systemLibrary.path,
            "/usr/local/bin", "/opt/homebrew/bin",
            Paths.home.appendingPathComponent(".local/bin").path, Paths.home.appendingPathComponent("bin").path,
            Paths.receipts.path, "/private/var/folders", "/var/folders", "/Users/Shared",
        ]
        if let c = Paths.userCacheDir { roots.append(c.path) }
        if let t = Paths.userTempDir { roots.append(t.path) }
        return roots.map { ($0 as NSString).standardizingPath }
    }

    /// 絕對不能整個刪掉的目錄（就算它在允許的根目錄底下）
    static var forbidden: Set<String> {
        let u = Paths.userLibrary.path, s = Paths.systemLibrary.path
        var set: Set<String> = [
            "/", "/Applications", "/Applications/Utilities", "/Library", "/System", "/Users", "/usr", "/usr/local", "/usr/local/bin",
            "/opt", "/opt/homebrew", "/opt/homebrew/bin", "/private", "/private/var", "/private/var/db", "/private/var/folders",
            "/var", "/var/folders", "/var/db", Paths.receipts.path, "/Users/Shared", Paths.home.path,
            Paths.home.appendingPathComponent("Applications").path, Paths.home.appendingPathComponent(".local").path,
            Paths.home.appendingPathComponent(".local/bin").path, Paths.home.appendingPathComponent("bin").path, u, s,
        ]
        for sub in ["Application Support", "Preferences", "Preferences/ByHost", "Caches", "Containers", "Group Containers", "LaunchAgents",
                    "LaunchDaemons", "PrivilegedHelperTools", "Logs", "Logs/DiagnosticReports", "Saved Application State", "HTTPStorages",
                    "WebKit", "Cookies", "Application Scripts", "Internet Plug-Ins", "QuickLook", "PreferencePanes", "Services", "Spotlight",
                    "Input Methods", "Screen Savers", "Audio", "Audio/Plug-Ins", "Audio/Plug-Ins/Components", "Audio/Plug-Ins/VST",
                    "Audio/Plug-Ins/VST3", "Audio/Plug-Ins/HAL", "Extensions", "Frameworks", "StartupItems", "Contextual Menu Items",
                    "Application Support/CrashReporter", "Application Support/com.apple.sharedfilelist",
                    "Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments",
                    "Safari", "Mail", "Messages", "Keychains", "Accounts", "Calendars", "Reminders", "Suggestions", "Metadata",
                    "Mobile Documents", "CloudStorage", "Fonts", "Colors", "Sounds", "Keyboard Layouts", "Developer"] {
            set.insert(u + "/" + sub); set.insert(s + "/" + sub)
        }
        if let c = Paths.userCacheDir { set.insert(c.path) }
        if let t = Paths.userTempDir { set.insert(t.path) }
        return Set(set.map { ($0 as NSString).standardizingPath })
    }

    public static func isSafeToRemove(_ url: URL) -> Bool {
        let path = (url.path as NSString).standardizingPath
        guard path.hasPrefix("/"), !path.contains("/../"), !path.hasSuffix("/.."), path.count > 1 else { return false }
        if forbidden.contains(path) { return false }
        // 系統磁碟區（已封存）內的東西一律不碰
        if path.hasPrefix("/System/") || path.hasPrefix("/usr/bin") || path.hasPrefix("/bin/") || path.hasPrefix("/sbin/") { return false }
        for root in allowedRoots where path.hasPrefix(root + "/") {
            // 至少要是根目錄底下的第一層以內的東西（不是根目錄本身）
            return path.count > root.count + 1
        }
        return false
    }
}

// MARK: - 移除

public struct RemovalOptions {
    public var mode: DeletionMode = .trash
    public var dryRun = false
    public init(mode: DeletionMode = .trash, dryRun: Bool = false) {
        self.mode = mode
        self.dryRun = dryRun
    }
}

public struct RemovalProgress {
    public enum Phase { case quitting, removing, waitingForAdmin, finishing }
    public var phase: Phase
    public var done: Int
    public var total: Int
    public var current: ResidueItem?
    public init(phase: Phase, done: Int, total: Int, current: ResidueItem?) {
        self.phase = phase; self.done = done; self.total = total; self.current = current
    }
}

public enum Remover {

    /// 解除安裝：結束程式 → 卸載背景服務 → 移除使用者層檔案 → 一次性以管理員身分移除系統層檔案
    public static func uninstall(apps: [InstalledApp], items: [ResidueItem], options: RemovalOptions,
                                progress: @escaping (RemovalProgress) -> Void) -> RemovalReport {
        var report = RemovalReport()
        let total = items.count
        var done = 0
        func tick(_ phase: RemovalProgress.Phase, _ current: ResidueItem?) {
            let p = RemovalProgress(phase: phase, done: done, total: total, current: current)
            DispatchQueue.main.async { progress(p) }
        }

        // 1. 結束正在執行的 App
        tick(.quitting, nil)
        if !options.dryRun {
            for app in apps { RunningApps.quit(app) }
        }

        // 2. 卸載使用者層的登入啟動項
        let uid = getuid()
        for item in items where item.category == .launchAgents && !item.isSystemDomain {
            guard let label = item.launchdLabel, !options.dryRun else { continue }
            Shell.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"], timeout: 10)
        }

        // 3. 排序：背景服務先、App 本體最後
        let ordered = items.sorted { a, b in
            func rank(_ i: ResidueItem) -> Int {
                switch i.category {
                case .launchAgents, .launchDaemons: return 0
                case .appBundle: return 2
                default: return 1
                }
            }
            return rank(a) < rank(b)
        }

        var adminItems: [ResidueItem] = []
        for item in ordered {
            tick(.removing, item)
            guard PathSafety.isSafeToRemove(item.url) else {
                report.outcomes.append(RemovalOutcome(item: item, status: .failed("Refused: path outside the allowed locations")))
                done += 1; continue
            }
            if item.category == .appBundle, FS.isRestricted(item.url) {
                report.outcomes.append(RemovalOutcome(item: item, status: .skipped("Protected by macOS (SIP)")))
                done += 1; continue
            }
            if item.receiptID != nil || item.category == .launchDaemons || item.category == .privilegedHelper || item.requiresAdmin {
                adminItems.append(item); continue
            }
            if options.dryRun {
                report.outcomes.append(RemovalOutcome(item: item, status: .simulated))
                done += 1; continue
            }
            guard FS.exists(item.url) || FS.isSymlink(item.url) else {
                report.outcomes.append(RemovalOutcome(item: item, status: .removed)) // 已經不在了
                done += 1; continue
            }
            do {
                try removeAsUser(item.url, mode: options.mode)
                if item.pruneParentIfEmpty { pruneParentAsUser(of: item.url, mode: options.mode) }
                report.outcomes.append(RemovalOutcome(item: item, status: .removed))
                UBLog.remove.info("removed \(item.url.path, privacy: .public)")
            } catch {
                if isPermissionError(error) {
                    adminItems.append(item)
                } else {
                    report.outcomes.append(RemovalOutcome(item: item, status: .failed(error.localizedDescription)))
                    UBLog.remove.error("failed \(item.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            done += 1
        }

        // 4. 需要管理員權限的項目：一次授權、一個腳本處理完
        if !adminItems.isEmpty {
            if options.dryRun {
                for item in adminItems { report.outcomes.append(RemovalOutcome(item: item, status: .simulated)) }
            } else {
                tick(.waitingForAdmin, adminItems.first)
                try? FileManager.default.createDirectory(at: Paths.trash, withIntermediateDirectories: true)
                let script = buildAdminScript(adminItems, mode: options.mode, uid: uid, gid: getgid())
                switch PrivilegedRunner.run(shellScript: script) {
                case .cancelled:
                    report.adminCancelled = true
                    for item in adminItems { report.outcomes.append(RemovalOutcome(item: item, status: .cancelled)) }
                case .failed(let msg):
                    for item in adminItems { report.outcomes.append(RemovalOutcome(item: item, status: .failed(msg))) }
                case .output(let out):
                    var results: [Int: RemovalStatus] = [:]
                    for line in out.split(separator: "\n") {
                        let s = String(line)
                        if s.hasPrefix("OK:"), let i = Int(s.dropFirst(3)) { results[i] = .removed }
                        else if s.hasPrefix("FAIL:") {
                            let rest = s.dropFirst(5)
                            let parts = rest.split(separator: ":", maxSplits: 1)
                            if let first = parts.first, let i = Int(first) {
                                results[i] = .failed(parts.count > 1 ? String(parts[1]) : "Failed")
                            }
                        }
                    }
                    for (i, item) in adminItems.enumerated() {
                        let status = results[i] ?? .failed("No result reported")
                        report.outcomes.append(RemovalOutcome(item: item, status: status))
                    }
                }
            }
            done += adminItems.count
        }

        tick(.finishing, nil)
        report.finishedAt = Date()
        return report
    }

    // MARK: 使用者層

    static func removeAsUser(_ url: URL, mode: DeletionMode) throws {
        switch mode {
        case .trash:
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                // 跨磁碟區等無法進垃圾桶的情況：只有在非權限錯誤時才改為直接刪除
                if isPermissionError(error) { throw error }
                try FileManager.default.removeItem(at: url)
            }
        case .permanent:
            try FileManager.default.removeItem(at: url)
        }
    }

    static func pruneParentAsUser(of url: URL, mode: DeletionMode) {
        let parent = url.deletingLastPathComponent()
        guard PathSafety.isSafeToRemove(parent) else { return }
        let rest = FS.children(of: parent).filter { ![".DS_Store", ".localized"].contains($0.lastPathComponent) }
        guard rest.isEmpty else { return }
        try? removeAsUser(parent, mode: mode)
    }

    static func isPermissionError(_ error: Error) -> Bool {
        var e: NSError? = error as NSError
        while let ns = e {
            if ns.domain == NSPOSIXErrorDomain, [Int(EPERM), Int(EACCES), Int(EROFS)].contains(ns.code) { return true }
            if ns.domain == NSCocoaErrorDomain, [NSFileWriteNoPermissionError, NSFileReadNoPermissionError, NSFileWriteVolumeReadOnlyError].contains(ns.code) { return true }
            e = ns.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    // MARK: 管理員腳本

    /// 管理員腳本用的垃圾桶目標路徑。沒有「完整磁碟取用」時看不到 ~/.Trash 裡有什麼，
    /// 為了絕不覆蓋垃圾桶裡的既有項目，一律加上時間戳（Finder 的重名做法）。
    static func uniqueTrashName(for url: URL, taken: inout Set<String>) -> URL {
        let base = url.lastPathComponent
        let f = DateFormatter(); f.dateFormat = "HH.mm.ss"
        let stamp = f.string(from: Date())
        let ext = url.pathExtension
        let stem = ext.isEmpty ? base : url.deletingPathExtension().lastPathComponent
        var candidate = Paths.trash.appendingPathComponent(ext.isEmpty ? "\(stem) \(stamp)" : "\(stem) \(stamp).\(ext)")
        var n = 2
        while FS.exists(candidate) || taken.contains(candidate.path) {
            candidate = Paths.trash.appendingPathComponent(ext.isEmpty ? "\(stem) \(stamp) \(n)" : "\(stem) \(stamp) \(n).\(ext)")
            n += 1
        }
        taken.insert(candidate.path)
        return candidate
    }

    public static func buildAdminScript(_ items: [ResidueItem], mode: DeletionMode, uid: uid_t, gid: gid_t) -> String {
        var lines = ["exec 2>&1", "set -f"]
        var taken = Set<String>()
        let q = Shell.quote
        for (i, item) in items.enumerated() {
            let path = q(item.url.path)
            if let label = item.launchdLabel {
                if item.category == .launchDaemons { lines.append("/bin/launchctl bootout system/\(q(label)) >/dev/null 2>&1 || true") }
                else { lines.append("/bin/launchctl bootout gui/\(uid)/\(q(label)) >/dev/null 2>&1 || true") }
            }
            if let rid = item.receiptID {
                lines.append("if /usr/sbin/pkgutil --forget \(q(rid)) >/dev/null 2>&1; then echo OK:\(i); else echo FAIL:\(i):pkgutil; fi")
                continue
            }
            let remove: String
            switch mode {
            case .trash:
                let dest = q(uniqueTrashName(for: item.url, taken: &taken).path)
                remove = "/bin/mv -f \(path) \(dest) && /usr/sbin/chown -R \(uid):\(gid) \(dest)"
            case .permanent:
                remove = "/bin/rm -rf \(path)"
            }
            lines.append("if [ -e \(path) ] || [ -L \(path) ]; then if \(remove); then echo OK:\(i); else echo FAIL:\(i):\"$?\"; fi; else echo OK:\(i); fi")
            if item.pruneParentIfEmpty {
                let parent = item.url.deletingLastPathComponent()
                if PathSafety.isSafeToRemove(parent) {
                    lines.append("/bin/rm -f \(q(parent.appendingPathComponent(".DS_Store").path)); /bin/rmdir \(q(parent.path)) >/dev/null 2>&1 || true")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
