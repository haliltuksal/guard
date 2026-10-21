import Foundation

/// Çekirdeğin istediği girdi politikası (System'deki InputPolicy'ye uygulama
/// katmanında eşlenir; Core, System'e bağımlı değildir).
public enum CoreInputPolicy: Equatable, Sendable {
    case passThrough, lockOnFirstInput, blockAll
}

/// Kalkanda gösterilecek durum (metin uygulama katmanında yerelleştirilir).
public enum ShieldMessage: Equatable, Sendable {
    case searching
    case blink
    case bystander
    case retry(seconds: Int)
    case gesture(Turn)
}

public enum NotificationKind: Equatable, Sendable {
    case guardStarted
    case guardEndedNoEvents
    case prepareFailed([String])
    case sensorFallback(String)
    case returned
}

/// Çekirdeğin ürettiği yan etkiler (spec §4.2). "Aktif gösterme" (sahte girdi) yok.
public enum GuardEffect: Equatable, Sendable {
    case startSensors
    case stopSensors
    case showShield(ShieldMessage)
    case hideShield
    case setInputPolicy(CoreInputPolicy)
    case wakeKeep(Bool)
    case captureSnapshot(SnapshotReason)   // sen yokken yaklaşanın fotoğrafı (şifreli, yalnızca cihazda)
    case logEvent(GuardLogKind)
    case notify(NotificationKind)
    case showSnapshots(count: Int)         // dönüşte: sen yokken çekilenleri hemen göster
    case showReport(SessionRecord)
    case persist(PersistedState)
}
