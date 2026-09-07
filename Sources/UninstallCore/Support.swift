import Foundation
import AppKit
import os.log

// MARK: - 日誌

public enum UBLog {
    public static let subsystem = "com.bowei.uninstallbutler"
    public static let scan = Logger(subsystem: subsystem, category: "scan")
    public static let remove = Logger(subsystem: subsystem, category: "remove")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}

// MARK: - 路徑

public enum Paths {
    public static let home = URL(fileURLWithPath: NSHomeDirectory())
    public static let userLibrary = home.appendingPathComponent("Library", isDirectory: true)
    public static let systemLibrary = URL(fileURLWithPath: "/Library", isDirectory: true)
    public static let receipts = URL(fileURLWithPath: "/private/var/db/receipts", isDirectory: true)

    /// 預設會掃描的 App 資料夾
    public static var defaultAppFolders: [URL] {
        [URL(fileURLWithPath: "/Applications", isDirectory: true),
         home.appendingPathComponent("Applications", isDirectory: true)]
    }

    /// 這位使用者的 /var/folders/…/C（快取）與 /T（暫存）
    public static func darwinUserDir(_ name: Int32) -> URL? {
        var buf = [Int8](repeating: 0, count: Int(PATH_MAX))
        let n = confstr(name, &buf, buf.count)
        guard n > 0 else { return nil }
        let path = String(cString: buf)
        return path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
    }
    public static var userCacheDir: URL? { darwinUserDir(_CS_DARWIN_USER_CACHE_DIR) }
    public static var userTempDir: URL? { darwinUserDir(_CS_DARWIN_USER_TEMP_DIR) }

    /// 目前使用者的 Trash
    public static var trash: URL { home.appendingPathComponent(".Trash", isDirectory: true) }

    /// 顯示用：把家目錄縮成 ~
    public static func abbreviated(_ path: String) -> String {
        let h = NSHomeDirectory()
        if path == h { return "~" }
        if path.hasPrefix(h + "/") { return "~" + path.dropFirst(h.count) }
        return path
    }
}

// MARK: - 檔案系統小工具

public enum FS {
    public static let fm = FileManager.default

    public static func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    public static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    public static func isSymlink(_ url: URL) -> Bool {
        (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    /// 列出目錄內容（含隱藏檔），失敗回空陣列
    public static func children(of url: URL, includeHidden: Bool = true) -> [URL] {
        let opts: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        return (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: opts)) ?? []
    }

    /// 讀取目錄時是否被拒（用來判斷需要「完整磁碟取用」）
    public static func isReadable(_ url: URL) -> Bool {
        do {
            _ = try fm.contentsOfDirectory(atPath: url.path)
            return true
        } catch {
            let ns = error as NSError
            if ns.domain == NSCocoaErrorDomain, ns.code == NSFileReadNoPermissionError { return false }
            if ns.domain == NSPOSIXErrorDomain, ns.code == Int(EPERM) || ns.code == Int(EACCES) { return false }
            return true // 不存在等其他原因，不算權限問題
        }
    }

    public static func modificationDate(_ url: URL) -> Date? {
        (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// 這個項目能不能用目前使用者的身分刪除（近似判斷：上層可寫 + 自己是擁有者或可寫）
    public static func currentUserCanDelete(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent().path
        guard access(parent, W_OK) == 0 else { return false }
        var sb = stat()
        guard lstat(url.path, &sb) == 0 else { return false }
        if sb.st_uid == getuid() { return true }
        // 不是自己的檔案：目錄要能寫才能清空內容
        if (sb.st_mode & S_IFMT) == S_IFDIR { return access(url.path, W_OK) == 0 }
        return true // 只要上層可寫，一般檔案就能 unlink
    }

    /// SIP / 系統保護旗標
    public static func isRestricted(_ url: URL) -> Bool {
        var sb = stat()
        guard lstat(url.path, &sb) == 0 else { return false }
        return (sb.st_flags & UInt32(SF_RESTRICTED)) != 0
    }

    public static func readPlist(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }

    public static func bundleIdentifier(ofBundleAt url: URL) -> String? {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        if let d = readPlist(plist), let id = d["CFBundleIdentifier"] as? String { return id }
        // 舊式 / 扁平 bundle
        let flat = url.appendingPathComponent("Info.plist")
        if let d = readPlist(flat), let id = d["CFBundleIdentifier"] as? String { return id }
        return nil
    }
}

// MARK: - 大小計算

public enum SizeCalculator {
    /// 用 Spotlight 索引快速取得套件大小（沒有索引時回 nil）
    public static func spotlightSize(of url: URL) -> Int64? {
        guard let item = MDItemCreate(nil, url.path as CFString) else { return nil }
        if let n = MDItemCopyAttribute(item, "kMDItemPhysicalSize" as CFString) as? NSNumber { return n.int64Value }
        if let n = MDItemCopyAttribute(item, kMDItemFSSize) as? NSNumber { return n.int64Value }
        return nil
    }

    /// 逐檔加總實際占用空間（不追 symlink）
    public static func size(of url: URL) -> Int64 {
        var sb = stat()
        guard lstat(url.path, &sb) == 0 else { return 0 }
        if (sb.st_mode & S_IFMT) != S_IFDIR {
            return Int64(sb.st_blocks) * 512
        }
        var total: Int64 = Int64(sb.st_blocks) * 512
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return total }
        for case let child as URL in en {
            guard let rv = try? child.resourceValues(forKeys: Set(keys)) else { continue }
            if rv.isSymbolicLink == true { continue }
            if let alloc = rv.totalFileAllocatedSize ?? rv.fileAllocatedSize { total += Int64(alloc) }
        }
        return total
    }

    /// App 大小：先試 Spotlight，沒有就逐檔算
    public static func bundleSize(of url: URL) -> Int64 {
        if let s = spotlightSize(of: url), s > 0 { return s }
        return size(of: url)
    }
}

// MARK: - Spotlight 中繼資料

public enum Metadata {
    public static func lastUsed(_ url: URL) -> Date? {
        guard let item = MDItemCreate(nil, url.path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
    public static func dateAdded(_ url: URL) -> Date? {
        if let rv = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]), let d = rv.addedToDirectoryDate { return d }
        guard let item = MDItemCreate(nil, url.path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemDateAdded) as? Date
    }
}

// MARK: - 權限

public enum Privileges {
    /// 「完整磁碟取用」是否已授權：以能否讀取受保護的使用者資料夾判斷
    public static func hasFullDiskAccess() -> Bool {
        let probes = [
            Paths.userLibrary.appendingPathComponent("Safari"),
            Paths.userLibrary.appendingPathComponent("Cookies"),
        ]
        for p in probes where FS.exists(p) {
            return FS.isReadable(p)
        }
        return true
    }

    public static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - 外部指令

public enum Shell {
    @discardableResult
    public static func run(_ launchPath: String, _ args: [String], timeout: TimeInterval = 20) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(50_000) }
        if p.isRunning { p.terminate() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// 單引號包起來給 /bin/sh
    public static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// MARK: - 名稱處理

public enum Names {
    /// 太籠統、不能單靠名稱比對的字
    public static let stopWords: Set<String> = [
        "app", "apps", "helper", "helpers", "update", "updater", "updates", "system", "apple", "library", "cache",
        "caches", "logs", "log", "preferences", "support", "application", "applications", "data", "tmp", "temp",
        "user", "users", "shared", "common", "default", "settings", "config", "plugins", "plugin", "utilities",
        "utility", "tools", "tool", "mac", "macos", "osx", "install", "installer", "setup", "service", "services",
        "agent", "daemon", "com", "net", "org", "io", "www", "home", "local", "google", "microsoft", "adobe",
        "finder", "safari", "mail", "music", "photos", "notes", "maps", "news", "tv", "books", "home", "keychain",
        "containers", "group", "documents", "desktop", "downloads", "movies", "pictures", "public", "sites", "test"
    ]

    /// 把「Microsoft Word」「Microsoft_Word」「microsoft-word」正規化成 microsoftword
    public static func normalized(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    public static func isSafeMatchName(_ s: String) -> Bool {
        let n = normalized(s)
        return n.count >= 3 && !stopWords.contains(n)
    }

    /// 像不像反向網域 ID（至少三段）
    public static func looksLikeBundleID(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        guard parts.count >= 3 else { return false }
        for p in parts {
            if p.isEmpty { return false }
            if !p.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) { return false }
        }
        // 第一段通常是 com/net/org/io/…（純字母、2~6 字）
        let first = parts[0]
        return first.count >= 2 && first.count <= 8 && first.allSatisfy { $0.isLetter }
    }

    /// 去掉尾端已知副檔名：.plist .savedState .binarycookies .sfl2 .sfl3 .lockfile
    public static func stripKnownSuffixes(_ name: String) -> String {
        var s = name
        let suffixes = [".plist.lockfile", ".plist", ".savedState", ".binarycookies", ".sfl3", ".sfl2", ".sfl", ".lockfile", ".bom"]
        var changed = true
        while changed {
            changed = false
            for suf in suffixes where s.lowercased().hasSuffix(suf.lowercased()) {
                s = String(s.dropLast(suf.count)); changed = true
            }
        }
        return s
    }

    /// ByHost 檔名：com.foo.bar.<UUID>.plist → com.foo.bar
    public static func stripByHostUUID(_ name: String) -> String {
        let parts = name.split(separator: ".")
        if let last = parts.last, last.count == 36, last.filter({ $0 == "-" }).count == 4 {
            return parts.dropLast().joined(separator: ".")
        }
        return name
    }

    /// 反向網域 ID 的「廠商前綴」com.foo（前兩段）
    public static func vendorPrefix(_ id: String) -> String? {
        let parts = id.lowercased().split(separator: ".")
        guard parts.count >= 3 else { return nil }
        return parts[0] + "." + parts[1]
    }

    /// 一般 hosting 前綴（不代表同一開發者）
    public static let genericVendorPrefixes: Set<String> = [
        "com.github", "io.github", "com.gitlab", "com.electron", "org.electron", "com.example", "com.yourcompany",
        "com.mycompany", "com.company", "com.todesktop", "com.tauri", "org.tauri", "io.tauri", "com.nativefier"
    ]
}

// MARK: - 沙盒容器中繼資料

public enum ContainerMetadata {
    public struct Info {
        public var bundleID: String?
        public var appBundlePath: String?
    }

    /// 讀 ~/Library/Containers/<x>/.com.apple.containermanagerd.metadata.plist（或舊的 Container.plist），
    /// 取得這個容器屬於哪個 bundle ID、哪個 App 路徑
    public static func read(_ container: URL) -> Info? {
        var info = Info()
        let modern = container.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
        let legacy = container.appendingPathComponent("Container.plist")
        guard let plist = FS.readPlist(modern) ?? FS.readPlist(legacy) else { return nil }
        if let id = plist["MCMMetadataIdentifier"] as? String { info.bundleID = id }
        if let metaInfo = plist["MCMMetadataInfo"] as? [String: Any],
           let validation = metaInfo["SandboxProfileDataValidationInfo"] as? [String: Any],
           let params = validation["SandboxProfileDataValidationParametersKey"] as? [String: Any] {
            info.appBundlePath = params["application_bundle"] as? String
            if info.bundleID == nil { info.bundleID = params["application_bundle_id"] as? String }
        } else if let validation = plist["SandboxProfileDataValidationInfo"] as? [String: Any],
                  let params = validation["SandboxProfileDataValidationParametersKey"] as? [String: Any] {
            info.appBundlePath = params["application_bundle"] as? String
            if info.bundleID == nil { info.bundleID = params["application_bundle_id"] as? String }
        }
        if info.bundleID == nil && info.appBundlePath == nil { return nil }
        return info
    }
}

// MARK: - 已知的共用元件 / 系統元件（不能當成某個 App 的殘留）

public enum SharedInfrastructure {
    public static let prefixes: [String] = [
        "com.apple.", "group.com.apple.", "is.workflow.", "org.cups.", "org.swift.", "org.sparkle-project.",
        "com.plausiblelabs.", "io.branch.", "com.crashlytics.", "com.google.firebase.", "com.microsoft.appcenter.",
        "io.sentry.", "com.mixpanel.", "com.amplitude.", "com.bowei.uninstallbutler",
    ]
    public static func isShared(_ id: String) -> Bool {
        let lower = id.lowercased()
        if lower.contains("com.apple.") { return true }
        return prefixes.contains { lower.hasPrefix($0) }
    }
}
