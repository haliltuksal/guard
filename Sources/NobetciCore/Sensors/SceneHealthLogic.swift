import Foundation

/// Kamera sağlığı/sahne tetikleyicileri (T6 örtülü/karanlık, T7 donma, T8 kayma).
/// Eşikler on-device kliplerle (D6/D1) kesinleşir; buradakiler başlangıç.
public struct SceneHealthLogic: Sendable {
    public static let minBrightness: Double = 0.08  // ortalama parlaklık (0–1)
    public static let minTexture: Double = 0.01     // doku (varyans) tabanı — ölçüm: sahip varken 0,04; kapalı lens ≈ 0
    public static let dimForTextureCollapse: Double = 0.2  // doku çöküşü ancak loşken "örtülü" — ölçüm: gece odası 0,29 (örtülü DEĞİL)
    public static let freezeGap: TimeInterval = 1.0 // kare gelmeme süresi
    public static let shiftFraction: Double = 0.03  // kare genişliğinin oranı

    private let cameraShiftEnabled: Bool
    public init(cameraShiftEnabled: Bool) { self.cameraShiftEnabled = cameraShiftEnabled }

    /// Kamera örtüldü/karartıldı: karanlık, ya da loş + dokusuz (parmak/bez). Parlak ve
    /// dokusuz bir sahne (düz duvar) örtülü sayılmaz — yoksa sahip yokken sürekli yanlış alarm.
    public func isCovered(brightness: Double, texture: Double) -> Bool {
        brightness < Self.minBrightness
            || (texture < Self.minTexture && brightness < Self.dimForTextureCollapse)
    }

    /// Kare akışı kesildi/dondu.
    public func isFrozen(frameGap: TimeInterval) -> Bool {
        frameGap >= Self.freezeGap
    }

    /// Kişi yokken tüm görüntü ötelendi (kamera açısı değişti). Ayar kapalıysa her zaman false.
    public func isShifted(translationFraction: Double) -> Bool {
        cameraShiftEnabled && translationFraction >= Self.shiftFraction
    }
}

/// T6 süreklilik kapısı (spec §5.3: ≥ 0,5 sn). Kamera ısınmasındaki birkaç siyah kare
/// (ölçüldü: ~9 kare ≈ 0,3 sn) ya da anlık gölge "örtülü" sayılmaz.
public struct CoveredDebouncer: Sendable {
    public static let required: TimeInterval = 0.5
    private var coveredSince: TimeInterval?
    public init() {}

    /// `covered` anlık ölçümdür; kesintisiz ≥ 0,5 sn sürdüyse true döner.
    public mutating func feed(covered: Bool, now: TimeInterval) -> Bool {
        guard covered else { coveredSince = nil; return false }
        let since = coveredSince ?? now
        coveredSince = since
        return now - since >= Self.required
    }
}
