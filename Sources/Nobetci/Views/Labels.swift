import SwiftUI
import NobetciCore

/// Rapor ve fotoğraf galerisinin ortak Türkçe etiketleri — iki yerde ayrı ayrı
/// yazılmasın diye tek kaynak.
enum Labels {
    static func snapshot(_ reason: SnapshotReason) -> String {
        switch reason {
        case .personSeen: "kadrajda"
        case .locked(let r): "kilit: \(lock(r))"
        case .wrongPasscode: "yanlış şifre"
        }
    }

    static func lock(_ r: LockReason) -> String {
        switch r {
        case .strangerFace: "yabancı yüz"
        case .facelessPerson: "yüzsüz kişi"
        case .input: "girdi"
        case .lidAngle: "kapak açısı"
        case .motion: "hareket"
        case .cameraCovered: "kamera örtüldü"
        case .cameraLost: "kamera kesildi"
        case .cameraShift: "kamera kaydı"
        case .display: "ekran"
        case .usb: "USB"
        case .power: "güç"
        case .sleep: "uyku"
        case .relaunch: "yeniden başlatma"
        case .filterLost: "girdi filtresi"
        }
    }

    static func event(_ kind: GuardLogKind) -> String {
        switch kind {
        case .guardStarted: "Nöbet başladı"
        case .guardEnded: "Nöbet bitti"
        case .ownerLeft: "Sahip ayrıldı"
        case .ownerReturned: "Sahip döndü"
        case .triggered(let r): "Kilit: \(lock(r))"
        case .unlockedByFace: "Yüzle açıldı"
        case .unlockedByPasscode: "Şifreyle açıldı"
        case .wrongPasscode: "Yanlış şifre"
        case .sensorIssue(let s): "Sensör sorunu: \(s)"
        case .cameraIssue(let s): "Kamera sorunu: \(s)"
        case .relaunched: "Yeniden başlatıldı"
        case .slept: "Uyudu"
        case .woke: "Uyandı"
        case .endedByRestart: "Yeniden başlatmayla bitti"
        }
    }

    static func icon(for kind: GuardLogKind) -> String {
        switch kind {
        case .triggered: "lock.fill"
        case .wrongPasscode: "xmark.shield"
        case .unlockedByFace, .unlockedByPasscode: "lock.open.fill"
        default: "circle.fill"
        }
    }

    static func color(for kind: GuardLogKind) -> Color {
        switch kind {
        case .triggered, .wrongPasscode: .orange
        case .unlockedByFace, .unlockedByPasscode: .green
        default: .secondary
        }
    }

    /// Fotoğrafın ne kadar sonra silineceği (galeri altbilgisi).
    static func retention(days: Int) -> String {
        days <= 0 ? "Fotoğraflar otomatik silinmiyor." : "Fotoğraflar \(days) gün sonra kendiliğinden silinir."
    }
}
