import Foundation
import AppKit

/// 找出「主人已經不在」的殘留檔案：反向網域名稱命名、系統中沒有任何 App 認領
public enum OrphanScanner {

    struct Location {
        let url: URL
        let category: ResidueCategory
        var launchd = false
        var groupContainers = false
    }

    static func locations() -> [Location] {
        let u = Paths.userLibrary, s = Paths.systemLibrary
        var locs: [Location] = [
            Location(url: u.appendingPathComponent("Application Support"), category: .appSupport),
            Location(url: u.appendingPathComponent("Caches"), category: .caches),
            Location(url: u.appendingPathComponent("Preferences"), category: .preferences),
            Location(url: u.appendingPathComponent("Preferences/ByHost"), category: .preferences),
            Location(url: u.appendingPathComponent("Saved Application State"), category: .savedState),
            Location(url: u.appendingPathComponent("Containers"), category: .container),
            Location(url: u.appendingPathComponent("Group Containers"), category: .groupContainer, groupContainers: true),
            Location(url: u.appendingPathComponent("HTTPStorages"), category: .webData),
            Location(url: u.appendingPathComponent("WebKit"), category: .webData),
            Location(url: u.appendingPathComponent("Cookies"), category: .webData),
            Location(url: u.appendingPathComponent("Logs"), category: .logs),
            Location(url: u.appendingPathComponent("Application Scripts"), category: .appScripts),
            Location(url: u.appendingPathComponent("Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments"), category: .recentDocuments),
            Location(url: u.appendingPathComponent("LaunchAgents"), category: .launchAgents, launchd: true),
            Location(url: s.appendingPathComponent("Application Support"), category: .appSupport),
            Location(url: s.appendingPathComponent("Caches"), category: .caches),
            Location(url: s.appendingPathComponent("Preferences"), category: .preferences),
            Location(url: s.appendingPathComponent("Logs"), category: .logs),
            Location(url: s.appendingPathComponent("LaunchAgents"), category: .launchAgents, launchd: true),
            Location(url: s.appendingPathComponent("LaunchDaemons"), category: .launchDaemons, launchd: true),
        ]
        if let c = Paths.userCacheDir { locs.append(Location(url: c, category: .temporary)) }
        if let t = Paths.userTempDir { locs.append(Location(url: t, category: .temporary)) }
        return locs
    }

    /// 已安裝 App 的知識庫
    final class Knowledge {
        let ownerIDs: [String]                 // 所有已安裝 App（含輔助程式）的 ID，小寫
        let vendorApps: [String: [String]]     // com.google → ["Google Chrome"]
        let groupNames: Set<String>            // 已安裝 App 宣告的 group（小寫）
        let teamIDs: Set<String>
        let nameTokens: [(token: String, app: String)]  // 正規化名稱 → App（找不到 ID 主人時的降級判斷）
        var lsCache: [String: Bool] = [:]
        let lock = NSLock()

        init(apps: [InstalledApp]) {
            var ids: [String] = []
            var vendors: [String: [String]] = [:]
            var groups = Set<String>()
            var teams = Set<String>()
            var tokens: [(String, String)] = []
            for a in apps {
                ids += a.allBundleIDs.map { $0.lowercased() }
                if let id = a.bundleID, let vp = Names.vendorPrefix(id), !Names.genericVendorPrefixes.contains(vp) {
                    vendors[vp, default: []].append(a.name)
                }
                for g in a.appGroups { groups.insert(g.lowercased()) }
                if let t = a.teamID { teams.insert(t.uppercased()) }
                let full = Names.normalized(a.name)
                if full.count >= 5 { tokens.append((full, a.name)) }
                if let first = a.name.split(separator: " ").first {
                    let n = Names.normalized(String(first))
                    if n.count >= 5, n != full, Names.isSafeMatchName(n) { tokens.append((n, a.name)) }
                }
            }
            nameTokens = tokens
            // 各種外掛 / 輸入法 / 偏好設定面板等非 App 的 bundle 也是主人
            let pluginDirs = ["Input Methods", "PreferencePanes", "QuickLook", "Spotlight", "Internet Plug-Ins", "Screen Savers",
                              "Audio/Plug-Ins/Components", "Audio/Plug-Ins/VST", "Audio/Plug-Ins/VST3", "Audio/Plug-Ins/HAL", "Services",
                              "Contextual Menu Items", "Extensions", "Frameworks", "PrivilegedHelperTools"]
            for lib in [Paths.userLibrary, Paths.systemLibrary] {
                for d in pluginDirs {
                    for child in FS.children(of: lib.appendingPathComponent(d)) {
                        if d == "PrivilegedHelperTools" { ids.append(child.lastPathComponent.lowercased()); continue }
                        if let id = FS.bundleIdentifier(ofBundleAt: child) { ids.append(id.lowercased()) }
                    }
                }
            }
            // 正在執行的程式也算有主人
            for r in NSWorkspace.shared.runningApplications {
                if let id = r.bundleIdentifier { ids.append(id.lowercased()) }
            }
            // 全部安裝資料夾（含 /System）都認識
            for sys in ["/System/Applications", "/System/Applications/Utilities", "/System/Library/CoreServices"] {
                for child in FS.children(of: URL(fileURLWithPath: sys)) where child.pathExtension == "app" {
                    if let id = FS.bundleIdentifier(ofBundleAt: child) { ids.append(id.lowercased()) }
                }
            }
            ownerIDs = Array(Set(ids))
            vendorApps = vendors
            groupNames = groups
            teamIDs = teams
        }

        /// Launch Services 是否知道有這個 ID 的 App（不限資料夾）
        func launchServicesKnows(_ id: String) -> Bool {
            lock.lock(); if let c = lsCache[id] { lock.unlock(); return c }; lock.unlock()
            var known = false
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                known = FS.exists(url)
            }
            lock.lock(); lsCache[id] = known; lock.unlock()
            return known
        }

        /// 這個 ID（或它的上層前綴）有沒有主人
        func hasOwner(_ rawID: String) -> Bool {
            let id = rawID.lowercased()
            for o in ownerIDs where id == o || id.hasPrefix(o + ".") { return true }
            // 逐層縮短：com.foo.app.helper → com.foo.app
            var parts = id.split(separator: ".").map(String.init)
            while parts.count >= 3 {
                let candidate = parts.joined(separator: ".")
                if launchServicesKnows(candidate) { return true }
                if launchdServiceExists(candidate) { return true }
                parts.removeLast()
            }
            return false
        }

        /// 仍有效的背景服務（plist 存在且執行檔存在）
        func launchdServiceExists(_ label: String) -> Bool {
            let dirs = [Paths.userLibrary.appendingPathComponent("LaunchAgents"),
                        Paths.systemLibrary.appendingPathComponent("LaunchAgents"),
                        Paths.systemLibrary.appendingPathComponent("LaunchDaemons")]
            for d in dirs {
                let plist = d.appendingPathComponent(label + ".plist")
                if let p = FS.readPlist(plist), programExists(p) { return true }
            }
            if FS.exists(Paths.systemLibrary.appendingPathComponent("PrivilegedHelperTools/" + label)) { return true }
            return false
        }
    }

    static func programExists(_ plist: [String: Any]) -> Bool {
        var paths: [String] = []
        if let p = plist["Program"] as? String { paths.append(p) }
        if let args = plist["ProgramArguments"] as? [String], let f = args.first { paths.append(f) }
        if paths.isEmpty { return true } // 沒有可判斷的路徑（BundleProgram 等），視為有效
        for p in paths {
            let std = (p as NSString).standardizingPath
            if FS.exists(URL(fileURLWithPath: std)) { return true }
            // 只有指令名（如 python3）交給 PATH，視為有效
            if !std.hasPrefix("/") { return true }
        }
        return false
    }

    // MARK: - 主流程

    public static func scan(installedApps: [InstalledApp]) -> [OrphanCandidate] {
        let k = Knowledge(apps: installedApps)
        var out: [OrphanCandidate] = []
        var seen = Set<String>()

        for loc in locations() where FS.isDirectory(loc.url) {
            for child in FS.children(of: loc.url) {
                let name = child.lastPathComponent
                if name.hasPrefix(".") { continue }
                let isDir = FS.isDirectory(child)
                var candidate: OrphanCandidate?

                if loc.launchd {
                    guard child.pathExtension == "plist", let plist = FS.readPlist(child) else { continue }
                    let label = (plist["Label"] as? String) ?? child.deletingPathExtension().lastPathComponent
                    if SharedInfrastructure.isShared(label) { continue }
                    if programExists(plist) { continue }
                    var c = OrphanCandidate(url: child, category: loc.category, bundleID: label, isDirectory: false,
                                            requiresAdmin: !FS.currentUserCanDelete(child), confidence: .high)
                    c.launchdLabel = label
                    candidate = c
                } else {
                    var id = Names.stripByHostUUID(Names.stripKnownSuffixes(name))
                    // 已安裝 App 宣告的 group 名稱（Group Containers / Application Scripts 都會出現）
                    if k.groupNames.contains(name.lowercased()) { continue }
                    // TEAMID.com.foo.bar / group.com.foo.bar → com.foo.bar
                    let parts = id.split(separator: ".").map(String.init)
                    let first = parts.first ?? ""
                    let looksLikeTeamID = first.count == 10 && first.uppercased() == first && first.allSatisfy { $0.isLetter || $0.isNumber }
                    if looksLikeTeamID {
                        if k.teamIDs.contains(first) { continue } // 同 Team 的 App 還在，保守略過
                        id = parts.dropFirst().joined(separator: ".")
                    } else if first == "group" {
                        id = parts.dropFirst().joined(separator: ".")
                    }
                    var ownerPathMissing = false
                    var relatedByPath: [String] = []
                    if loc.category == .container, let meta = ContainerMetadata.read(child) {
                        // 容器中繼資料最準：App 路徑還在 → 有主人；不在 → 孤兒
                        if let owner = meta.appBundlePath {
                            if FS.exists(URL(fileURLWithPath: owner)) { continue }
                            ownerPathMissing = true
                            // 路徑不在了，但落在某個仍安裝的 App 裡（舊版的延伸功能）→ 只當「請先確認」
                            let std = (owner as NSString).standardizingPath
                            relatedByPath = installedApps.filter { std.hasPrefix($0.resolvedURL.path + "/") }.map(\.name)
                        }
                        if let mid = meta.bundleID, Names.looksLikeBundleID(mid) { id = mid }
                    }
                    guard Names.looksLikeBundleID(id) else { continue }
                    if SharedInfrastructure.isShared(id) { continue }
                    if !ownerPathMissing && k.hasOwner(id) { continue }
                    var c = OrphanCandidate(url: child, category: loc.category, bundleID: id, isDirectory: isDir,
                                            requiresAdmin: !FS.currentUserCanDelete(child), confidence: .high)
                    // 第一段就是某個已安裝 App 的名字（LINE.AudioService…）→ 可能是舊版元件，請先確認
                    let head = Names.normalized(String(id.split(separator: ".").first ?? ""))
                    let headApps = head.count >= 3 ? installedApps.filter { Names.normalized($0.name) == head || Names.normalized($0.bundleName ?? "") == head }.map(\.name) : []
                    if !relatedByPath.isEmpty {
                        c.confidence = .medium
                        c.relatedApps = Array(Set(relatedByPath)).sorted()
                    } else if !headApps.isEmpty {
                        c.confidence = .medium
                        c.relatedApps = Array(Set(headApps)).sorted()
                    } else if let vp = Names.vendorPrefix(id), let related = k.vendorApps[vp], !related.isEmpty {
                        c.confidence = .medium
                        c.relatedApps = Array(Set(related)).sorted()
                    } else {
                        // ID 裡含有某個已安裝 App 的名字（Electron App 常用不同的偏好設定網域）→ 降級
                        let norm = Names.normalized(id)
                        let hits = k.nameTokens.filter { norm.contains($0.token) }.map(\.app)
                        if !hits.isEmpty { c.confidence = .medium; c.relatedApps = Array(Set(hits)).sorted() }
                    }
                    candidate = c
                }

                guard var c = candidate, seen.insert(c.url.path).inserted else { continue }
                c.lastModified = FS.modificationDate(child)
                out.append(c)
            }
        }

        // 大小（平行計算）
        let lock = NSLock()
        var sizes = [Int: Int64]()
        DispatchQueue.concurrentPerform(iterations: out.count) { i in
            let s = SizeCalculator.size(of: out[i].url)
            lock.lock(); sizes[i] = s; lock.unlock()
        }
        for (i, s) in sizes { out[i].sizeBytes = s }

        out.sort { a, b in
            if a.confidence != b.confidence { return a.confidence == .high }
            return (a.sizeBytes ?? 0) > (b.sizeBytes ?? 0)
        }
        return out
    }
}
