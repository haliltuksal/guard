// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nobetci",
    defaultLocalization: "tr",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "NobetciCore"),
        .target(name: "NobetciVision", dependencies: ["NobetciCore"]),
        .target(name: "NobetciSystem", dependencies: ["NobetciCore"]),
        .executableTarget(
            name: "Nobetci",
            dependencies: ["NobetciCore", "NobetciVision", "NobetciSystem"],
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "nobetci-eval", dependencies: ["NobetciCore", "NobetciVision"]),
        // Test targets are declared as each gains its first test file (SwiftPM
        // rejects a target with no sources). NobetciVisionTests / NobetciSystemTests
        // are added in the first task that writes a test into them.
        .testTarget(name: "NobetciCoreTests", dependencies: ["NobetciCore"]),
    ],
    swiftLanguageModes: [.v6]
)
