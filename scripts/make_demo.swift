// 產生 README 截圖用的「虛構示範環境」：假 App（含圖示、假大小）＋ 一個示範 App 的假殘留。
//   swift scripts/make_demo.swift create   → /tmp/ub-demo/Applications/*.app 與 ~/Library 內的示範殘留
//   swift scripts/make_demo.swift cleanup  → 全部移除
// 所有名稱都是虛構的，不會碰到任何真實 App 的檔案。
import AppKit
import Foundation

let fm = FileManager.default
let home = URL(fileURLWithPath: NSHomeDirectory())
let demoRoot = URL(fileURLWithPath: "/tmp/ub-demo/Applications", isDirectory: true)
let lib = home.appendingPathComponent("Library")

struct DemoApp { let name: String; let id: String; let version: String; let mb: Int; let hue: CGFloat; let intelOnly: Bool }
let apps: [DemoApp] = [
    .init(name: "Aurora Notes", id: "com.northlight.AuroraNotes", version: "3.2.1", mb: 48, hue: 0.62, intelOnly: false),
    .init(name: "Blueprint Studio", id: "com.draftworks.BlueprintStudio", version: "2024.4", mb: 380, hue: 0.55, intelOnly: false),
    .init(name: "Cascade Player", id: "org.cascade.Player", version: "1.9.0", mb: 96, hue: 0.02, intelOnly: false),
    .init(name: "Driftwood", id: "com.tidepool.Driftwood", version: "5.0.2", mb: 22, hue: 0.09, intelOnly: true),
    .init(name: "Ember Mail", id: "com.emberworks.Mail", version: "7.1", mb: 140, hue: 0.98, intelOnly: false),
    .init(name: "Fjord Browser", id: "com.fjordlabs.FjordBrowser", version: "118.0.5", mb: 420, hue: 0.58, intelOnly: false),
    .init(name: "Glacier Backup", id: "com.glacier.Backup", version: "4.3.0", mb: 64, hue: 0.50, intelOnly: false),
    .init(name: "Harbor Sync", id: "io.harbor.Sync", version: "2.8.3", mb: 110, hue: 0.44, intelOnly: false),
    .init(name: "Iris Photos", id: "com.irislabs.Photos", version: "6.0", mb: 260, hue: 0.80, intelOnly: false),
    .init(name: "Juniper Terminal", id: "dev.juniper.Terminal", version: "1.4.7", mb: 18, hue: 0.33, intelOnly: false),
    .init(name: "Kestrel VPN", id: "com.kestrel.VPN", version: "3.0.9", mb: 36, hue: 0.70, intelOnly: true),
    .init(name: "Lumen Weather", id: "com.lumen.Weather", version: "2.2", mb: 30, hue: 0.12, intelOnly: false),
]
let demoResidue: [(String, Int)] = [   // 相對 ~/Library 的路徑 → KB（0 = 單一小檔）
    ("Application Support/Fjord Browser/Profiles", 96_000),
    ("Application Support/fjordlabs/FjordBrowser", 3_200),
    ("Caches/com.fjordlabs.FjordBrowser", 210_000),
    ("Caches/com.fjordlabs.FjordBrowser.helper", 8_400),
    ("Preferences/com.fjordlabs.FjordBrowser.plist", 0),
    ("Saved Application State/com.fjordlabs.FjordBrowser.savedState", 40),
    ("LaunchAgents/com.fjordlabs.FjordBrowser.updater.plist", 0),
    ("HTTPStorages/com.fjordlabs.FjordBrowser", 1_100),
    ("WebKit/com.fjordlabs.FjordBrowser", 2_900),
    ("Logs/Fjord Browser", 1_800),
]

func writeBlob(_ url: URL, kb: Int) throws {
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if kb == 0 { try Data("demo".utf8).write(to: url); return }
    let handle = try { () throws -> FileHandle in
        fm.createFile(atPath: url.path, contents: nil)
        return try FileHandle(forWritingTo: url)
    }()
    defer { try? handle.close() }
    var remaining = kb * 1024
    let chunk = Data((0..<(1024 * 1024)).map { _ in UInt8.random(in: 0...255) })
    while remaining > 0 {
        let n = min(remaining, chunk.count)
        try handle.write(contentsOf: chunk.prefix(n))
        remaining -= n
    }
}

func makeIcon(letter: String, hue: CGFloat, to icns: URL) throws {
    let size: CGFloat = 512
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let inset: CGFloat = 36
    let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let plate = NSBezierPath(roundedRect: rect, xRadius: 98, yRadius: 98)
    let c1 = NSColor(calibratedHue: hue, saturation: 0.65, brightness: 0.95, alpha: 1)
    let c2 = NSColor(calibratedHue: hue, saturation: 0.85, brightness: 0.55, alpha: 1)
    NSGradient(colors: [c1, c2])!.draw(in: plate, angle: -70)
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 250, weight: .bold), .foregroundColor: NSColor.white.withAlphaComponent(0.95)]
    let str = NSAttributedString(string: letter, attributes: attrs)
    let sz = str.size()
    str.draw(at: NSPoint(x: (size - sz.width) / 2, y: (size - sz.height) / 2 - 10))
    img.unlockFocus()
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return }
    let iconset = icns.deletingLastPathComponent().appendingPathComponent("tmp.iconset")
    try? fm.removeItem(at: iconset)
    try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
    try png.write(to: iconset.appendingPathComponent("icon_256x256@2x.png"))
    try png.write(to: iconset.appendingPathComponent("icon_512x512.png"))
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    p.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
    try p.run(); p.waitUntilExit()
    try? fm.removeItem(at: iconset)
}

func thinBinary(to url: URL, intelOnly: Bool) throws {
    if intelOnly {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
        p.arguments = ["/bin/ls", "-thin", "x86_64", "-output", url.path]
        try p.run(); p.waitUntilExit()
    } else {
        try fm.copyItem(at: URL(fileURLWithPath: "/bin/ls"), to: url)
    }
}

func create() throws {
    try? fm.removeItem(at: demoRoot)
    try fm.createDirectory(at: demoRoot, withIntermediateDirectories: true)
    for a in apps {
        let bundle = demoRoot.appendingPathComponent("\(a.name).app")
        let contents = bundle.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try fm.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        let exe = a.name.replacingOccurrences(of: " ", with: "")
        let info: [String: Any] = ["CFBundleIdentifier": a.id, "CFBundleName": a.name, "CFBundleDisplayName": a.name,
                                   "CFBundleExecutable": exe, "CFBundleShortVersionString": a.version, "CFBundleVersion": "1",
                                   "CFBundlePackageType": "APPL", "CFBundleIconFile": "AppIcon", "LSMinimumSystemVersion": "12.0"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        try thinBinary(to: contents.appendingPathComponent("MacOS/\(exe)"), intelOnly: a.intelOnly)
        try makeIcon(letter: String(a.name.prefix(1)), hue: a.hue, to: contents.appendingPathComponent("Resources/AppIcon.icns"))
        try writeBlob(contents.appendingPathComponent("Resources/payload.bin"), kb: a.mb * 1024)
        print("  • \(a.name) (\(a.mb) MB)")
    }
    for (rel, kb) in demoResidue {
        let url = lib.appendingPathComponent(rel)
        if url.pathExtension == "plist" {
            let plist: [String: Any] = rel.contains("LaunchAgents")
                ? ["Label": "com.fjordlabs.FjordBrowser.updater", "ProgramArguments": [demoRoot.appendingPathComponent("Fjord Browser.app/Contents/MacOS/FjordBrowser").path, "--check"], "RunAtLoad": false]
                : ["HomePage": "https://example.com", "ShowBookmarksBar": true]
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
        } else {
            try writeBlob(url.appendingPathComponent(kb > 50_000 ? "Cache.db" : "data.bin"), kb: kb)
            if kb > 50_000 { try writeBlob(url.appendingPathComponent("Media Cache/index.db"), kb: 12_000) }
        }
    }
    // /var/folders 快取
    var buf = [Int8](repeating: 0, count: Int(PATH_MAX))
    if confstr(_CS_DARWIN_USER_CACHE_DIR, &buf, buf.count) > 0 {
        let c = URL(fileURLWithPath: String(cString: buf)).appendingPathComponent("com.fjordlabs.FjordBrowser")
        try writeBlob(c.appendingPathComponent("tmp.bin"), kb: 12_000)
    }
    print("示範環境已建立：\(demoRoot.path)")
}

func cleanup() {
    try? fm.removeItem(at: URL(fileURLWithPath: "/tmp/ub-demo"))
    for (rel, _) in demoResidue { try? fm.removeItem(at: lib.appendingPathComponent(rel)) }
    try? fm.removeItem(at: lib.appendingPathComponent("Application Support/fjordlabs"))
    var buf = [Int8](repeating: 0, count: Int(PATH_MAX))
    if confstr(_CS_DARWIN_USER_CACHE_DIR, &buf, buf.count) > 0 {
        try? fm.removeItem(at: URL(fileURLWithPath: String(cString: buf)).appendingPathComponent("com.fjordlabs.FjordBrowser"))
    }
    print("示範環境已清除")
}

if CommandLine.arguments.contains("cleanup") { cleanup() } else { try create() }
