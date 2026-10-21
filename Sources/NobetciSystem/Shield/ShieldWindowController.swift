import AppKit

/// Ekran kümesini sağlayan kaynak — testte sahte, üretimde `SystemScreens`.
@MainActor public protocol ScreenProvider: AnyObject {
    var frames: [CGRect] { get }
    var onChange: (() -> Void)? { get set }
}

@MainActor public final class SystemScreens: ScreenProvider {
    public var frames: [CGRect] { NSScreen.screens.map(\.frame) }
    public var onChange: (() -> Void)?
    // Uygulama ömrü boyunca yaşar; gözlemci [weak self] tuttuğu için sızıntı olmaz.
    public init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
    }
}

final class ShieldWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Her ekranı kaplayan kalkan pencerelerini yönetir. Pencere kümesi her zaman
/// ekran kümesine eşitlenir (ekran takılıp çıkınca kalkansız ekran kalmaz).
@MainActor public final class ShieldWindowController {
    private let screens: ScreenProvider
    private let makeContent: () -> NSView
    private var windows: [ShieldWindow] = []
    public private(set) var isShowing = false
    public var tintAlpha: CGFloat = 0.55

    public init(screens: ScreenProvider = SystemScreens(), content: @escaping () -> NSView) {
        self.screens = screens
        self.makeContent = content
        screens.onChange = { [weak self] in self?.rebuildIfShowing() }
    }

    public var windowFrames: [CGRect] { windows.map(\.frame) }
    public var debugWindowLevel: Int { windows.first.map { $0.level.rawValue } ?? -1 }

    public func show() {
        // İdempotent: kilitliyken her kare `.showShield` etkisi gelir; pencereleri her
        // seferinde yıkıp kurmak titremeye ve gereksiz maliyete yol açar. Mesaj metni
        // pencerelerden bağımsız olarak (gözlemlenen model) güncellenir.
        guard !isShowing else { return }
        isShowing = true
        rebuild()
        NSApp?.activate(ignoringOtherApps: true)
    }

    public func hide(animated: Bool) {
        isShowing = false
        let old = windows
        windows = []
        guard animated else { old.forEach { $0.orderOut(nil) }; return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            old.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { MainActor.assumeIsolated { old.forEach { $0.orderOut(nil) } } })
    }

    private func rebuildIfShowing() { if isShowing { rebuild() } }

    private func rebuild() {
        windows.forEach { $0.orderOut(nil) }
        windows = screens.frames.map { frame in
            let window = ShieldWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false

            let effect = NSVisualEffectView(frame: CGRect(origin: .zero, size: frame.size))
            effect.material = .fullScreenUI
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.autoresizingMask = [.width, .height]

            let tint = NSView(frame: effect.bounds)
            tint.wantsLayer = true
            tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(tintAlpha).cgColor
            tint.autoresizingMask = [.width, .height]

            let content = makeContent()
            content.frame = effect.bounds
            content.autoresizingMask = [.width, .height]

            effect.addSubview(tint)
            effect.addSubview(content)
            window.contentView = effect
            window.alphaValue = 1
            window.orderFrontRegardless()
            return window
        }
        windows.first?.makeKeyAndOrderFront(nil)
    }
}
