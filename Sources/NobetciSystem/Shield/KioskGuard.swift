import AppKit

/// Kilitliyken sistem kaçış yollarını kapatır: Cmd+Tab, Force Quit, oturum kapatma,
/// Dock ve menü çubuğu. Menü çubuğu (accessory) uygulamasında presentationOptions
/// yetersiz kalırsa kilitliyken etkinleştirme politikası geçici olarak .regular yapılır.
@MainActor
public enum KioskGuard {
    private static let kioskOptions: NSApplication.PresentationOptions = [
        .hideDock, .hideMenuBar, .disableProcessSwitching, .disableForceQuit,
        .disableSessionTermination, .disableHideApplication, .disableAppleMenu,
    ]
    private static var previousPolicy: NSApplication.ActivationPolicy?

    public static func engage() {
        previousPolicy = NSApp.activationPolicy()
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)   // accessory'de presentationOptions için gerekir
        }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = kioskOptions
    }

    public static func disengage() {
        NSApp.presentationOptions = []
        if let previousPolicy { NSApp.setActivationPolicy(previousPolicy) }
        previousPolicy = nil
    }
}
