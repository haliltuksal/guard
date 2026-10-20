import SwiftUI

@main
struct NobetciApp: App {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some Scene {
        MenuBarExtra("Nöbetçi", systemImage: "shield") {
            Text("Nöbetçi \(version)")
            Divider()
            Button("Çıkış") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        .menuBarExtraStyle(.window)
    }
}
