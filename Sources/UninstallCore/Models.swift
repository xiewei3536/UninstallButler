import Foundation

// MARK: - 已安裝的 App

public enum CPUArch: String, Codable, Hashable, CaseIterable {
    case arm64, x86_64
}

public struct InstalledApp: Identifiable, Hashable {
    public var id: String { url.path }
    /// 在應用程式資料夾中看到的路徑（可能是 symlink）
    public let url: URL
    /// 實際的 bundle 路徑（symlink 解析後）
    public var resolvedURL: URL
    /// Finder 顯示名稱（已本地化、不含 .app）
    public var name: String
    public var bundleID: String?
    public var bundleName: String?
    public var executableName: String?
    public var version: String?
    public var build: String?
    /// 內嵌的輔助程式 / XPC / 延伸功能 / 特權工具的 bundle ID（找殘留時一併比對）
    public var helperBundleIDs: [String] = []
    public var teamID: String?
    public var appGroups: [String] = []
    public var isSandboxed = false
    /// nil 表示尚在計算
    public var sizeBytes: Int64?
    public var lastUsed: Date?
    public var installedDate: Date?
    public var archs: Set<CPUArch> = []
    public var isAppStore = false
    /// SIP 保護（無法移除，例如 Safari）
    public var isRestricted = false
    public var isSymlink = false

    public init(url: URL) {
        self.url = url
        self.resolvedURL = url
        self.name = url.deletingPathExtension().lastPathComponent
    }

    public var isAppleApp: Bool { bundleID?.hasPrefix("com.apple.") ?? false }

    /// 所有可用來比對殘留的 bundle ID（主程式 + 輔助程式），已去重
    public var allBundleIDs: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for id in [bundleID].compactMap({ $0 }) + helperBundleIDs {
            let key = id.lowercased()
            if !key.isEmpty, !seen.contains(key) { seen.insert(key); out.append(id) }
        }
        return out
    }

    public var archDescription: ArchKind {
        if archs.contains(.arm64) && archs.contains(.x86_64) { return .universal }
        if archs.contains(.arm64) { return .appleSilicon }
        if archs.contains(.x86_64) { return .intel }
        return .unknown
    }

}

public enum ArchKind: String, Hashable {
    case universal, appleSilicon, intel, unknown
}

// MARK: - 殘留項目

public enum ResidueCategory: String, CaseIterable, Codable, Hashable {
    case appBundle          // App 本體
    case container          // ~/Library/Containers（沙盒資料）
    case appSupport         // Application Support
    case preferences        // Preferences / ByHost
    case caches             // Caches
    case savedState         // Saved Application State
    case webData            // HTTPStorages / WebKit / Cookies
    case logs               // Logs
    case crashReports       // DiagnosticReports / CrashReporter
    case launchAgents       // LaunchAgents（登入時啟動的背景程式）
    case launchDaemons      // LaunchDaemons（系統層級背景服務）
    case privilegedHelper   // /Library/PrivilegedHelperTools
    case receipts           // 安裝收據（pkgutil）
    case plugins            // QuickLook / Spotlight / PreferencePanes / Internet Plug-Ins / Audio…
    case commandLine        // /usr/local/bin 等指向 App 的指令列捷徑
    case appScripts         // Application Scripts
    case recentDocuments    // 最近使用的文件清單
    case groupContainer     // Group Containers（可能與同開發者其他 App 共用）
    case temporary          // /var/folders 快取與暫存
    case other

    /// 顯示順序
    public static let displayOrder: [ResidueCategory] = [
        .appBundle, .container, .appSupport, .preferences, .caches, .savedState, .webData,
        .logs, .crashReports, .launchAgents, .launchDaemons, .privilegedHelper, .receipts,
        .plugins, .commandLine, .appScripts, .recentDocuments, .groupContainer, .temporary, .other
    ]

    /// 屬於「個人資料與設定」— 使用者選擇保留資料時不勾選
    public var isPersonalData: Bool {
        switch self {
        case .container, .appSupport, .preferences, .groupContainer, .appScripts: return true
        default: return false
        }
    }
}

/// 為何判定這個項目屬於該 App
public enum MatchReason: Hashable {
    case bundleID(String)
    case name(String)
    case vendorFolder(vendor: String, product: String)
    case programPath          // launchd plist 的執行檔位於 App 內
    case symlinkTarget        // symlink 指向 App 內
    case entitlement(String)  // App Group 等來自簽章的宣告
    case receipt(String)
    case containerOwner       // 沙盒容器的中繼資料指向這個 App
    case vendorPrefix(String) // 同開發者前綴（這是該開發者唯一安裝的 App 時才成立）
    case isApp
}

public enum Caution: Hashable {
    /// 同開發者的其他已安裝 App 也在使用（Group Container / 廠商共用資料夾）
    case sharedWith([String])
    /// 只靠名稱比對，把握度較低
    case nameMatchOnly
    /// 需要管理員密碼
    case requiresAdmin
    /// 同開發者的共用元件（更新器等），因為這是該開發者唯一安裝的 App 才一併列出
    case sameDeveloper
}

public struct ResidueItem: Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let category: ResidueCategory
    public var isDirectory: Bool
    public var sizeBytes: Int64?
    public var requiresAdmin: Bool
    public var matchedBy: MatchReason
    public var cautions: [Caution] = []
    public var defaultSelected = true
    /// launchd Label（移除前先卸載）
    public var launchdLabel: String?
    /// pkgutil 收據 ID（以 pkgutil --forget 清除）
    public var receiptID: String?
    /// 移除後若上層廠商資料夾變空，一併移除
    public var pruneParentIfEmpty = false
    /// 這個項目屬於哪個 App（批次解除安裝時用）
    public var ownerAppPath: String?

    public init(url: URL, category: ResidueCategory, isDirectory: Bool, requiresAdmin: Bool, matchedBy: MatchReason) {
        self.url = url
        self.category = category
        self.isDirectory = isDirectory
        self.requiresAdmin = requiresAdmin
        self.matchedBy = matchedBy
        if requiresAdmin { cautions.append(.requiresAdmin) }
    }

    public var isSystemDomain: Bool {
        !url.path.hasPrefix(NSHomeDirectory())
    }

    public static func == (lhs: ResidueItem, rhs: ResidueItem) -> Bool { lhs.url == rhs.url }
    public func hash(into hasher: inout Hasher) { hasher.combine(url) }
}

// MARK: - 殘留清理（找不到主人的檔案）

public enum OrphanConfidence: String, Hashable {
    /// 反向網域名稱、系統中沒有任何 App 認領，且沒有同開發者 App 還安裝著
    case high
    /// 沒有主人，但同開發者的其他 App 仍在，可能是共用元件
    case medium
}

public struct OrphanCandidate: Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let category: ResidueCategory
    public let bundleID: String
    public var isDirectory: Bool
    public var sizeBytes: Int64?
    public var requiresAdmin: Bool
    public var confidence: OrphanConfidence
    /// 同開發者仍安裝的 App 名稱（medium 時）
    public var relatedApps: [String] = []
    public var lastModified: Date?
    public var launchdLabel: String?

    public init(url: URL, category: ResidueCategory, bundleID: String, isDirectory: Bool, requiresAdmin: Bool, confidence: OrphanConfidence) {
        self.url = url
        self.category = category
        self.bundleID = bundleID
        self.isDirectory = isDirectory
        self.requiresAdmin = requiresAdmin
        self.confidence = confidence
    }

    public func asResidueItem() -> ResidueItem {
        var item = ResidueItem(url: url, category: category, isDirectory: isDirectory,
                               requiresAdmin: requiresAdmin, matchedBy: .bundleID(bundleID))
        item.sizeBytes = sizeBytes
        item.launchdLabel = launchdLabel
        item.defaultSelected = confidence == .high
        if !relatedApps.isEmpty { item.cautions.append(.sharedWith(relatedApps)) }
        return item
    }

    public static func == (lhs: OrphanCandidate, rhs: OrphanCandidate) -> Bool { lhs.url == rhs.url }
    public func hash(into hasher: inout Hasher) { hasher.combine(url) }
}

// MARK: - 移除結果

public enum DeletionMode: String, Codable, Hashable {
    case trash       // 移到垃圾桶（可復原）
    case permanent   // 直接永久刪除
}

public enum RemovalStatus: Hashable {
    case removed
    case simulated
    case failed(String)
    case skipped(String)
    case cancelled
}

public struct RemovalOutcome: Identifiable, Hashable {
    public var id: String { item.id }
    public let item: ResidueItem
    public let status: RemovalStatus
}

public struct RemovalReport {
    public var outcomes: [RemovalOutcome] = []
    public var adminCancelled = false
    public var startedAt = Date()
    public var finishedAt = Date()

    public var removed: [RemovalOutcome] { outcomes.filter { $0.status == .removed || $0.status == .simulated } }
    public var failed: [RemovalOutcome] { outcomes.filter { if case .failed = $0.status { return true } else { return false } } }
    public var skipped: [RemovalOutcome] {
        outcomes.filter {
            switch $0.status { case .skipped, .cancelled: return true; default: return false }
        }
    }
    public var freedBytes: Int64 { removed.reduce(0) { $0 + ($1.item.sizeBytes ?? 0) } }
}
