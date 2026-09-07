import XCTest
@testable import UninstallCore

final class NamesTests: XCTestCase {
    func testStripSuffixes() {
        XCTAssertEqual(Names.stripKnownSuffixes("com.foo.bar.plist"), "com.foo.bar")
        XCTAssertEqual(Names.stripKnownSuffixes("com.foo.bar.savedState"), "com.foo.bar")
        XCTAssertEqual(Names.stripKnownSuffixes("com.foo.bar.binarycookies"), "com.foo.bar")
        XCTAssertEqual(Names.stripKnownSuffixes("com.foo.bar.sfl2"), "com.foo.bar")
        XCTAssertEqual(Names.stripKnownSuffixes("com.foo.bar"), "com.foo.bar")
    }

    func testByHost() {
        XCTAssertEqual(Names.stripByHostUUID("com.foo.bar.0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0"), "com.foo.bar")
        XCTAssertEqual(Names.stripByHostUUID("com.foo.bar"), "com.foo.bar")
    }

    func testBundleIDShape() {
        XCTAssertTrue(Names.looksLikeBundleID("com.google.Chrome"))
        XCTAssertTrue(Names.looksLikeBundleID("org.videolan.vlc"))
        XCTAssertFalse(Names.looksLikeBundleID("Google"))
        XCTAssertFalse(Names.looksLikeBundleID("com.foo"))
        XCTAssertFalse(Names.looksLikeBundleID("12.34.56"))
    }

    func testSafeNames() {
        XCTAssertTrue(Names.isSafeMatchName("Spotify"))
        XCTAssertFalse(Names.isSafeMatchName("App"))
        XCTAssertFalse(Names.isSafeMatchName("Cache"))
        XCTAssertFalse(Names.isSafeMatchName("ab"))
    }

    func testVendorPrefix() {
        XCTAssertEqual(Names.vendorPrefix("com.google.Chrome"), "com.google")
        XCTAssertNil(Names.vendorPrefix("com.foo"))
    }
}
