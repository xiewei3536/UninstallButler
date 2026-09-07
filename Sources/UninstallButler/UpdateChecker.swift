import AppKit
import Foundation
import UninstallCore

/// 對照 GitHub Releases 最新 tag 檢查是否有新版（每天最多自動檢查一次；選單可手動）
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()
    static let repo = "xiewei3536/UninstallButler"
    private let lastCheckKey = "updateLastCheck"
    private let skippedKey = "updateSkippedVersion"

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 啟動時：距上次檢查超過一天才查，而且只有真的有新版才打擾
    func startAutoCheck() {
        guard Bundle.main.bundleIdentifier != nil else { return } // 開發執行檔不檢查
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 86_400 else { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { throw URLError(.badServerResponse) }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? URL(string: "https://github.com/\(Self.repo)/releases/latest")!
            let notes = (json["body"] as? String) ?? ""
            if isNewer(latest, than: currentVersion) {
                if !userInitiated, UserDefaults.standard.string(forKey: skippedKey) == latest { return }
                presentUpdate(version: latest, page: page, notes: notes)
            } else if userInitiated {
                let a = NSAlert()
                a.messageText = L.updateUpToDate.s
                a.informativeText = L.updateUpToDateBody.f(currentVersion)
                a.runModal()
            }
        } catch {
            if userInitiated {
                let a = NSAlert()
                a.alertStyle = .warning
                a.messageText = L.updateFailed.s
                a.informativeText = error.localizedDescription
                a.runModal()
            }
        }
    }

    private func presentUpdate(version: String, page: URL, notes: String) {
        let a = NSAlert()
        a.messageText = L.updateAvailable.f(version)
        var body = L.updateAvailableBody.f(currentVersion, version)
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { body += "\n\n" + String(trimmed.prefix(600)) }
        a.informativeText = body
        a.addButton(withTitle: L.updateDownload.s)
        a.addButton(withTitle: L.updateLater.s)
        a.addButton(withTitle: L.updateSkip.s)
        switch a.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(page)
        case .alertThirdButtonReturn: UserDefaults.standard.set(version, forKey: skippedKey)
        default: break
        }
    }

    /// 1.2.10 > 1.2.9
    func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
