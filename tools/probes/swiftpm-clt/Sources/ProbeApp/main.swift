import SwiftUI
import AppKit
import AVFoundation
import Vision
import CoreML
import ProbeKit

// Compile-only probe: a MenuBarExtra SwiftUI app builds with SwiftPM + Command Line Tools.
struct ProbeApp: App {
    var body: some Scene {
        MenuBarExtra("Probe", systemImage: "eye") {
            Text("cos = \(cosineSimilarity([1, 0], [1, 0]))")
        }
        .menuBarExtraStyle(.window)
    }
}

if CommandLine.arguments.contains("--run") {
    ProbeApp.main()
} else {
    print("ProbeApp built OK; Vision request type:", VNDetectFaceLandmarksRequest.self)
}
