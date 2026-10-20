// swift-tools-version: 6.0
import PackageDescription

// Probe: SwiftPM app + Swift Testing with Command Line Tools only (no Xcode).
let package = Package(
    name: "Probe",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ProbeKit"),
        .executableTarget(name: "ProbeApp", dependencies: ["ProbeKit"]),
        .testTarget(name: "ProbeKitTests", dependencies: ["ProbeKit"]),
    ]
)
