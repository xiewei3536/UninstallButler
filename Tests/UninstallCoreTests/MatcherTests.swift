import XCTest
@testable import UninstallCore

final class MatcherTests: XCTestCase {
    private func app(_ path: String, id: String?, name: String, helpers: [String] = [], groups: [String] = [], team: String? = nil) -> InstalledApp {
        var a = InstalledApp(url: URL(fileURLWithPath: path))
        a.bundleID = id
        a.name = name
        a.bundleName = name
        a.executableName = name.replacingOccurrences(of: " ", with: "")
        a.helperBundleIDs = helpers
        a.appGroups = groups
        a.teamID = team
        return a
    }

    func testIDMatchingIncludingHelpersAndSuffixes() {
        let chrome = app("/Applications/Google Chrome.app", id: "com.google.Chrome", name: "Google Chrome", helpers: ["com.google.Chrome.helper"])
        let m = ResidueFinder.Matcher(app: chrome, context: .init(installedApps: [chrome]))
        XCTAssertEqual(m.idMatch("com.google.Chrome"), "com.google.chrome")
        XCTAssertEqual(m.idMatch("com.google.Chrome.plist"), "com.google.chrome")
        XCTAssertEqual(m.idMatch("com.google.Chrome.savedState"), "com.google.chrome")
        XCTAssertEqual(m.idMatch("com.google.Chrome.helper.plist"), "com.google.chrome.helper")
        XCTAssertNil(m.idMatch("com.google.keystone.agent.plist"))
        XCTAssertNil(m.idMatch("com.googlecode.iterm2"))
    }

    func testLongerPrefixBelongsToOtherApp() {
        let chrome = app("/Applications/Google Chrome.app", id: "com.google.Chrome", name: "Google Chrome")
        let canary = app("/Applications/Google Chrome Canary.app", id: "com.google.Chrome.canary", name: "Google Chrome Canary")
        let m = ResidueFinder.Matcher(app: chrome, context: .init(installedApps: [chrome, canary]))
        XCTAssertNil(m.idMatch("com.google.Chrome.canary.plist"), "Canary 的偏好設定屬於 Canary，不該算成 Chrome 的")
        XCTAssertEqual(m.idMatch("com.google.Chrome.plist"), "com.google.chrome")
    }

    func testNameMatchingIsConservative() {
        let a = app("/Applications/Spotify.app", id: "com.spotify.client", name: "Spotify")
        let m = ResidueFinder.Matcher(app: a, context: .init(installedApps: [a]))
        XCTAssertNotNil(m.nameMatch("Spotify", isDirectory: true))
        XCTAssertNotNil(m.nameMatch("spotify.log", isDirectory: false))
        XCTAssertNil(m.nameMatch("Spot", isDirectory: true))
        XCTAssertNil(m.nameMatch("Caches", isDirectory: true))
    }

    func testAmbiguousNameIsSkipped() {
        let a = app("/Applications/Notes Pro.app", id: "com.foo.notes", name: "Notes Pro")
        let b = app("/Applications/Notes Pro Beta.app", id: "com.bar.notespro", name: "Notes Pro")
        let m = ResidueFinder.Matcher(app: a, context: .init(installedApps: [a, b]))
        XCTAssertNil(m.nameMatch("Notes Pro", isDirectory: true), "兩個 App 同名時不能用名稱比對")
    }

    func testVendorAndProductTokens() {
        let word = app("/Applications/Microsoft Word.app", id: "com.microsoft.Word", name: "Microsoft Word")
        let m = ResidueFinder.Matcher(app: word, context: .init(installedApps: [word]))
        XCTAssertEqual(m.vendorToken, "microsoft")
        XCTAssertNotNil(m.productMatch("Word"))
        XCTAssertNil(m.productMatch("Office"))
    }

    func testCrashLogNames() {
        let a = app("/Applications/RustDesk.app", id: "com.carriez.RustDesk", name: "RustDesk")
        let m = ResidueFinder.Matcher(app: a, context: .init(installedApps: [a]))
        XCTAssertNotNil(m.crashMatch("RustDesk_2026-01-02-030405_MacBook.ips"))
        XCTAssertNotNil(m.crashMatch("RustDesk-2026-01-02-030405.crash"))
        XCTAssertNil(m.crashMatch("Safari_2026-01-02-030405_MacBook.ips"))
    }

    func testProgramPath() {
        let a = app("/Applications/Foo.app", id: "com.foo.app", name: "Foo")
        let m = ResidueFinder.Matcher(app: a, context: .init(installedApps: [a]))
        XCTAssertTrue(m.programIsInsideApp(["ProgramArguments": ["/Applications/Foo.app/Contents/MacOS/agent", "--x"]]))
        XCTAssertTrue(m.programIsInsideApp(["Program": "/Applications/Foo.app/Contents/Helpers/h"]))
        XCTAssertFalse(m.programIsInsideApp(["Program": "/Applications/Foo Bar.app/Contents/MacOS/x"]))
    }

    func testPathSafety() {
        let home = NSHomeDirectory()
        XCTAssertTrue(PathSafety.isSafeToRemove(URL(fileURLWithPath: home + "/Library/Caches/com.foo.bar")))
        XCTAssertTrue(PathSafety.isSafeToRemove(URL(fileURLWithPath: "/Applications/Foo.app")))
        XCTAssertTrue(PathSafety.isSafeToRemove(URL(fileURLWithPath: "/Library/LaunchDaemons/com.foo.plist")))
        XCTAssertFalse(PathSafety.isSafeToRemove(URL(fileURLWithPath: home + "/Library/Caches")))
        XCTAssertFalse(PathSafety.isSafeToRemove(URL(fileURLWithPath: home + "/Library")))
        XCTAssertFalse(PathSafety.isSafeToRemove(URL(fileURLWithPath: home)))
        XCTAssertFalse(PathSafety.isSafeToRemove(URL(fileURLWithPath: "/Applications")))
        XCTAssertFalse(PathSafety.isSafeToRemove(URL(fileURLWithPath: "/System/Library/Foo")))
        XCTAssertFalse(PathSafety.isSafeToRemove(URL(fileURLWithPath: home + "/Documents/x")))
        XCTAssertFalse(PathSafety.isSafeToRemove(URL(fileURLWithPath: "/Library/Caches/../../etc")))
    }

    func testAdminScriptQuoting() {
        var item = ResidueItem(url: URL(fileURLWithPath: "/Library/Application Support/It's Here"), category: .appSupport, isDirectory: true, requiresAdmin: true, matchedBy: .name("x"))
        item.launchdLabel = nil
        let script = Remover.buildAdminScript([item], mode: .permanent, uid: 501, gid: 20)
        XCTAssertTrue(script.contains("/bin/rm -rf '/Library/Application Support/It'\\''s Here'"))
        XCTAssertTrue(script.contains("echo OK:0"))
    }
}
