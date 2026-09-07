import Foundation
import Security
import AppKit

/// 以管理員身分執行一段 shell 腳本（系統跳出標準的密碼視窗）
public enum PrivilegedRunner {
    public enum Outcome {
        case output(String)
        case cancelled
        case failed(String)
    }

    public static func run(shellScript: String) -> Outcome {
        // 優先用 Security 框架直接執行（視窗顯示本 App 名稱、可讀取輸出）；沒有就退回 osascript
        if let out = runWithAuthorizationServices(shellScript) { return out }
        return runWithOsascript(shellScript)
    }

    // MARK: AuthorizationExecuteWithPrivileges（透過 dlsym 取得，避免 deprecated 警告）

    private typealias AEWPFn = @convention(c) (
        AuthorizationRef, UnsafePointer<CChar>, AuthorizationFlags,
        UnsafePointer<UnsafeMutablePointer<CChar>?>, UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
    ) -> OSStatus

    private static func runWithAuthorizationServices(_ script: String) -> Outcome? {
        guard let handle = dlopen(nil, RTLD_NOW), let sym = dlsym(handle, "AuthorizationExecuteWithPrivileges") else { return nil }
        let exec = unsafeBitCast(sym, to: AEWPFn.self)

        var authRef: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &authRef) == errAuthorizationSuccess, let auth = authRef else { return nil }
        defer { AuthorizationFree(auth, [.destroyRights]) }

        let status: OSStatus = "system.privilege.admin".withCString { cName in
            var item = AuthorizationItem(name: cName, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { itemPtr in
                var rights = AuthorizationRights(count: 1, items: itemPtr)
                return AuthorizationCopyRights(auth, &rights, nil, [.interactionAllowed, .preAuthorize, .extendRights], nil)
            }
        }
        if status == errAuthorizationCanceled { return .cancelled }
        guard status == errAuthorizationSuccess else { return .failed("Authorization failed (\(status))") }

        var argv: [UnsafeMutablePointer<CChar>?] = [strdup("-c"), strdup(script), nil]
        defer { for p in argv { free(p) } }
        var pipe: UnsafeMutablePointer<FILE>?
        let st: OSStatus = argv.withUnsafeMutableBufferPointer { buf in
            exec(auth, "/bin/sh", [], UnsafePointer(buf.baseAddress!), &pipe)
        }
        guard st == errAuthorizationSuccess, let fp = pipe else { return .failed("Privileged execution failed (\(st))") }
        var output = ""
        var line = [CChar](repeating: 0, count: 8192)
        while fgets(&line, Int32(line.count), fp) != nil {
            output += String(cString: line)
        }
        fclose(fp)
        return .output(output)
    }

    // MARK: osascript 後備方案

    private static func runWithOsascript(_ script: String) -> Outcome {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let src = "do shell script \"\(escaped)\" with administrator privileges"
        let r = Shell.run("/usr/bin/osascript", ["-e", src], timeout: 600)
        if r.status != 0 {
            if r.output.contains("-128") { return .cancelled }
            return .failed(r.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return .output(r.output)
    }
}

// MARK: - 正在執行的程式

public enum RunningApps {
    public static func instances(of app: InstalledApp) -> [NSRunningApplication] {
        let roots = Set([app.url.path, app.resolvedURL.path, app.resolvedURL.resolvingSymlinksInPath().path])
        func inside(_ url: URL?) -> Bool {
            guard let url else { return false }
            for p in [url.path, url.resolvingSymlinksInPath().path] {
                for root in roots where p == root || p.hasPrefix(root + "/") { return true }
            }
            return false
        }
        return NSWorkspace.shared.runningApplications.filter { r in
            if inside(r.bundleURL) || inside(r.executableURL) { return true }
            if let id = app.bundleID, r.bundleIdentifier == id { return true }
            return false
        }
    }

    public static func isRunning(_ app: InstalledApp) -> Bool { !instances(of: app).isEmpty }

    /// 先禮貌結束，等不到就強制；最後清掉 bundle 內殘餘的背景程序
    @discardableResult
    public static func quit(_ app: InstalledApp, timeout: TimeInterval = 5) -> Bool {
        let procs = instances(of: app)
        guard !procs.isEmpty else { return true }
        for p in procs { p.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, procs.contains(where: { !$0.isTerminated }) { usleep(100_000) }
        for p in procs where !p.isTerminated { p.forceTerminate() }
        usleep(300_000)
        // 非 GUI 的背景程序（agent、helper）
        for root in Set([app.resolvedURL.path, app.resolvedURL.resolvingSymlinksInPath().path]) {
            Shell.run("/usr/bin/pkill", ["-9", "-f", NSRegularExpression.escapedPattern(for: root + "/")], timeout: 5)
        }
        return instances(of: app).allSatisfy { $0.isTerminated }
    }
}
