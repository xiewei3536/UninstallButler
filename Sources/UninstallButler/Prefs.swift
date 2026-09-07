import Foundation
import Combine
import UninstallCore

/// 使用者偏好（UserDefaults），變更即時通知 UI
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    @Published var language: String { didSet { d.set(language, forKey: "language") } }
    @Published var deletionMode: DeletionMode { didSet { d.set(deletionMode.rawValue, forKey: "deletionMode") } }
    @Published var extraFolders: [String] { didSet { d.set(extraFolders, forKey: "extraFolders") } }
    @Published var showAppleApps: Bool { didSet { d.set(showAppleApps, forKey: "showAppleApps") } }
    @Published var unusedDays: Int { didSet { d.set(unusedDays, forKey: "unusedDays") } }
    @Published var hasSeenWelcome: Bool { didSet { d.set(hasSeenWelcome, forKey: "hasSeenWelcome") } }

    private init() {
        language = d.string(forKey: "language") ?? "auto"
        deletionMode = DeletionMode(rawValue: d.string(forKey: "deletionMode") ?? "") ?? .trash
        extraFolders = d.stringArray(forKey: "extraFolders") ?? []
        showAppleApps = d.object(forKey: "showAppleApps") as? Bool ?? true
        unusedDays = d.object(forKey: "unusedDays") as? Int ?? 90
        hasSeenWelcome = d.bool(forKey: "hasSeenWelcome")
    }

    var appFolders: [URL] {
        var urls = Paths.defaultAppFolders
        for p in extraFolders {
            let u = URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true)
            if !urls.contains(u) { urls.append(u) }
        }
        return urls
    }

    /// 是否為模擬模式（開發/測試用，不真的刪除）
    static var dryRun: Bool { ProcessInfo.processInfo.environment["UNINSTALLBUTLER_DRYRUN"] == "1" }
}
