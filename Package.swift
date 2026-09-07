// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UninstallButler",
    platforms: [.macOS(.v13)],
    targets: [
        // 核心邏輯（掃描 App、找殘留、移除）— 與 UI 分離，方便單元測試
        .target(
            name: "UninstallCore",
            path: "Sources/UninstallCore"
        ),
        // App 本體（SwiftUI + AppKit 視窗、選單、三語 UI）
        .executableTarget(
            name: "UninstallButler",
            dependencies: ["UninstallCore"],
            path: "Sources/UninstallButler"
        ),
        .testTarget(
            name: "UninstallCoreTests",
            dependencies: ["UninstallCore"],
            path: "Tests/UninstallCoreTests"
        )
    ]
)
