import AppKit
import SwiftUI

/// Bir SwiftUI görünümünü bağımsız bir pencerede gösterir (kurulum, rapor).
@MainActor
final class WindowPresenter {
    private var window: NSWindow?

    func show<Content: View>(title: String, size: NSSize, @ViewBuilder content: () -> Content) {
        let hosting = NSHostingController(rootView: content())
        let w = NSWindow(contentViewController: hosting)
        w.title = title
        w.styleMask = [.titled, .closable]
        w.setContentSize(size)
        w.center()
        w.isReleasedWhenClosed = false
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        window = w
    }

    func close() {
        window?.close()
        window = nil
    }
}
