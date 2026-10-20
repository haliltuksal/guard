import SwiftUI

@main
struct NobetciApp: App {
    var body: some Scene {
        MenuBarExtra("Nöbetçi", systemImage: "shield") {
            Text("Nöbetçi")
            Divider()
            Button("Çıkış") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        .menuBarExtraStyle(.window)
    }
}
