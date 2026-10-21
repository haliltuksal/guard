import AppKit
import SwiftUI

/// Bir SwiftUI görünümünü bağımsız bir pencerede gösterir (kurulum, rapor).
@MainActor
final class WindowPresenter {
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    var isShowing: Bool { window != nil }

    func show<Content: View>(title: String, size: NSSize, @ViewBuilder content: () -> Content) {
        close()                                  // ikinci çağrı ikinci pencere açmasın
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
        // Kullanıcı kırmızı düğmeyle kapatırsa referansı bırak ki isShowing doğru kalsın.
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.window = nil }
        }
    }

    func close() {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }   // her gösterimde gözlemci birikmesin
        closeObserver = nil
        window?.close()
        window = nil
    }
}
