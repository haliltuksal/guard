import Foundation
import ServiceManagement

/// Uygulamayı launchd ajanı olarak kaydeder; çökme/öldürme sonrası ~1 sn içinde
/// yeniden başlar (KeepAlive). İki plist vardır: girişte başlat açık/kapalı.
/// Kaynak: Resources/LaunchAgents/*.plist, uygulama paketine kopyalanır.
public enum LaunchAgent {
    public static let loginLabel = "com.halil.nobetci.login"
    public static let manualLabel = "com.halil.nobetci"

    public static func register(runAtLogin: Bool) throws {
        let service = SMAppService.agent(plistName: (runAtLogin ? loginLabel : manualLabel) + ".plist")
        // Diğer varyantı kaydını kaldır (tek ajan kuralı).
        let other = SMAppService.agent(plistName: (runAtLogin ? manualLabel : loginLabel) + ".plist")
        if other.status == .enabled { try? other.unregister() }
        if service.status != .enabled { try service.register() }
    }

    public static func unregister() throws {
        for label in [loginLabel, manualLabel] {
            let service = SMAppService.agent(plistName: label + ".plist")
            if service.status == .enabled { try service.unregister() }
        }
    }

    /// Elle açılan kopya launchd yönetiminde değilse, ajanı canlandırıp bu kopyayı bırakır (tek kopya).
    public static func kickstartIfNeeded() {
        let uid = getuid()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["kickstart", "-k", "gui/\(uid)/\(manualLabel)"]
        try? task.run()
    }
}
