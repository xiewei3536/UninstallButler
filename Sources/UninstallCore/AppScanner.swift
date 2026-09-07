import Foundation
import AppKit
import Security

/// 掃描應用程式資料夾，讀出每個 App 的身分資訊（bundle ID、輔助程式、簽章、架構…）
public enum AppScanner {

    public static let ownBundleID = "com.bowei.uninstallbutler"

    /// 掃描指定資料夾（含一層子資料夾，如 /Applications/Utilities）
    public static func scan(folders: [URL], includeRestricted: Bool = false) -> [InstalledApp] {
        var seen = Set<String>()
        var candidates: [(URL, URL, Bool)] = []   // (列出的路徑, 解析後路徑, 是否 symlink)
        for folder in folders {
            collectAppURLs(in: folder, depth: 0, seen: &seen, into: &candidates)
        }
        // 每個 App 的檢查互相獨立，平行處理
        let lock = NSLock()
        var results = [Int: InstalledApp]()
        DispatchQueue.concurrentPerform(iterations: candidates.count) { i in
            let (url, resolved, isLink) = candidates[i]
            if var app = inspect(appURL: url, resolved: resolved) {
                app.isSymlink = isLink
                lock.lock(); results[i] = app; lock.unlock()
            }
        }
        let apps = candidates.indices.compactMap { results[$0] }
        return apps.filter { app in
            if app.bundleID == ownBundleID { return false }
            if app.resolvedURL.path.hasPrefix("/System/") { return false }
            if app.isRestricted && !includeRestricted { return false }
            return true
        }
    }

    private static func collectAppURLs(in folder: URL, depth: Int, seen: inout Set<String>, into out: inout [(URL, URL, Bool)]) {
        guard depth <= 2 else { return }
        for child in FS.children(of: folder, includeHidden: false) {
            let isLink = FS.isSymlink(child)
            let resolved = child.resolvingSymlinksInPath()
            if child.pathExtension.lowercased() == "app" || resolved.pathExtension.lowercased() == "app" {
                guard FS.isDirectory(resolved) else { continue }
                if seen.insert(resolved.path).inserted { out.append((child, resolved, isLink)) }
            } else if !isLink, FS.isDirectory(child), child.pathExtension.isEmpty {
                collectAppURLs(in: child, depth: depth + 1, seen: &seen, into: &out)
            }
        }
    }

    /// 讀取單一 App 的資訊（不含大小，大小另外背景計算）
    public static func inspect(appURL: URL, resolved: URL? = nil) -> InstalledApp? {
        let real = resolved ?? appURL.resolvingSymlinksInPath()
        let infoURL = real.appendingPathComponent("Contents/Info.plist")
        guard let info = FS.readPlist(infoURL) else { return nil }

        var app = InstalledApp(url: appURL)
        app.resolvedURL = real
        let finderName = FileManager.default.displayName(atPath: appURL.path)
        app.name = finderName.hasSuffix(".app") ? String(finderName.dropLast(4)) : finderName
        app.bundleID = (info["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespaces)
        app.bundleName = info["CFBundleName"] as? String
        app.executableName = info["CFBundleExecutable"] as? String
        app.version = info["CFBundleShortVersionString"] as? String
        app.build = info["CFBundleVersion"] as? String
        app.isAppStore = FS.exists(real.appendingPathComponent("Contents/_MASReceipt/receipt"))
        app.isRestricted = FS.isRestricted(real) || real.path.hasPrefix("/System/")
        app.lastUsed = Metadata.lastUsed(real)
        app.installedDate = Metadata.dateAdded(real)
        app.archs = architectures(of: real, executable: app.executableName)
        app.helperBundleIDs = helperBundleIDs(in: real, mainID: app.bundleID)

        let signing = SigningInfo.read(real)
        app.teamID = signing.teamID
        app.isSandboxed = signing.sandboxed
        app.appGroups = signing.appGroups
        return app
    }

    // MARK: 架構

    static func architectures(of appURL: URL, executable: String?) -> Set<CPUArch> {
        var archs = Set<CPUArch>()
        if let bundle = Bundle(url: appURL), let list = bundle.executableArchitectures {
            for n in list {
                switch n.intValue {
                case NSBundleExecutableArchitectureX86_64: archs.insert(.x86_64)
                case 0x0100000c: archs.insert(.arm64)   // NSBundleExecutableArchitectureARM64
                default: break
                }
            }
        }
        return archs
    }

    // MARK: 內嵌的輔助程式

    /// 找出 App 內嵌的 LoginItems / XPC / 延伸功能 / 特權工具，收集 bundle ID
    static func helperBundleIDs(in appURL: URL, mainID: String?) -> [String] {
        let contents = appURL.appendingPathComponent("Contents")
        var ids: [String] = []
        let mainLower = mainID?.lowercased()
        let vendor = mainID.flatMap(Names.vendorPrefix)

        // 這些位置底下的東西一定屬於這個 App
        let ownedDirs = ["Library/LoginItems", "Library/LaunchServices", "XPCServices", "Helpers", "PlugIns",
                         "Library/SystemExtensions", "Library/LaunchAgents", "Library/LaunchDaemons"]
        for rel in ownedDirs {
            let dir = contents.appendingPathComponent(rel)
            for child in FS.children(of: dir) {
                if FS.isDirectory(child) {
                    if let id = FS.bundleIdentifier(ofBundleAt: child), id.lowercased() != mainLower { ids.append(id) }
                } else if rel == "Library/LaunchServices" {
                    // 特權工具是以 bundle ID 命名的單一執行檔
                    ids.append(child.lastPathComponent)
                } else if child.pathExtension == "plist", let d = FS.readPlist(child), let label = d["Label"] as? String {
                    ids.append(label)
                }
            }
        }

        // 其他位置（MacOS/、Resources/、Frameworks 內的 Helpers）只收同廠商前綴的 bundle
        let bundleExts: Set<String> = ["app", "xpc", "appex", "systemextension"]
        let skipExts: Set<String> = ["lproj", "bundle", "dsym", "momd", "car", "nib", "storyboardc", "asar", "dylib", "metallib", "scnassets", "xcassets", "swiftmodule"]
        var visited = 0
        if let en = FileManager.default.enumerator(at: contents, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) {
            for case let url as URL in en {
                visited += 1
                if visited > 12_000 { break }
                let ext = url.pathExtension.lowercased()
                if en.level > 7 || skipExts.contains(ext) { en.skipDescendants(); continue }
                if ext == "framework" {
                    // framework 本身不算輔助程式，但 Versions/*/Helpers|XPCServices 內可能有
                    continue
                }
                if !ext.isEmpty && ext.count <= 4 && !bundleExts.contains(ext) && !["app", "xpc"].contains(ext) {
                    // 有副檔名的一般檔案（png/plist/…）不需要深入
                    if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true { continue }
                }
                guard bundleExts.contains(ext) else { continue }
                en.skipDescendants()
                guard let id = FS.bundleIdentifier(ofBundleAt: url) else { continue }
                let lower = id.lowercased()
                if lower == mainLower { continue }
                if let v = vendor, lower.hasPrefix(v + "."), !Names.genericVendorPrefixes.contains(v) { ids.append(id) }
                else if let m = mainLower, lower.hasPrefix(m + ".") { ids.append(id) }
            }
        }

        var seen = Set<String>()
        return ids.filter { seen.insert($0.lowercased()).inserted }
    }
}

// MARK: - 簽章資訊（Team ID、沙盒、App Groups）

public struct SigningInfo {
    public var teamID: String?
    public var sandboxed = false
    public var appGroups: [String] = []

    /// 只讀簽章區塊，不驗證整個 bundle，速度很快
    public static func read(_ url: URL) -> SigningInfo {
        var info = SigningInfo()
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let code = staticCode else { return info }
        var cfInfo: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &cfInfo) == errSecSuccess,
              let dict = cfInfo as? [String: Any] else { return info }
        info.teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String
        if let ent = dict[kSecCodeInfoEntitlementsDict as String] as? [String: Any] {
            info.sandboxed = (ent["com.apple.security.app-sandbox"] as? Bool) ?? false
            if let groups = ent["com.apple.security.application-groups"] as? [String] { info.appGroups = groups }
            else if let g = ent["com.apple.security.application-groups"] as? String { info.appGroups = [g] }
        }
        return info
    }
}
