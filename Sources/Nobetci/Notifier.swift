import Foundation
import UserNotifications
import NobetciCore

/// Yerel bildirimler (nöbet başladı/bitti, sorun). Ağ yok; yalnızca yerel.
@MainActor
final class Notifier {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ kind: NotificationKind) {
        let content = UNMutableNotificationContent()
        switch kind {
        case .guardStarted:
            content.title = L10n.t("notify.guardStarted")
        case .guardEndedNoEvents:
            content.title = L10n.t("notify.guardEndedNoEvents")
        case .prepareFailed(let missing):
            content.title = L10n.t("notify.prepareFailed")
            content.body = missing.joined(separator: ", ")
        case .sensorFallback(let name):
            content.title = L10n.t("notify.sensorFallback", name)
        case .returned:
            content.title = L10n.t("notify.returned")
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
