// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ScreenPilot", platforms: [.macOS(.v14)], products: [
    .executable(name: "ScreenPilot", targets: ["ScreenPilot"]),
    .executable(name: "ConnectionGuard", targets: ["ConnectionGuard"])
], targets: [
    .target(name: "DisplayCore"),
    .executableTarget(name: "ConnectionGuard", dependencies: ["DisplayCore"]),
    .executableTarget(name: "ScreenPilot", dependencies: ["DisplayCore"]),
    .testTarget(name: "DisplayCoreTests", dependencies: ["DisplayCore"])
], swiftLanguageModes: [.v5])
