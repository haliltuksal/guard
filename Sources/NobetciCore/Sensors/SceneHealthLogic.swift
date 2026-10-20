import Foundation

/// Kamera sağlığı/sahne tetikleyicileri (T6 örtülü/karanlık, T7 donma, T8 kayma).
/// Eşikler on-device kliplerle (D6/D1) kesinleşir; buradakiler başlangıç.
public struct SceneHealthLogic {
    public static let minBrightness: Double = 0.08  // ortalama parlaklık (0–1)
    public static let minTexture: Double = 0.02     // Laplacian varyansı tabanı
    public static let freezeGap: TimeInterval = 1.0 // kare gelmeme süresi
    public static let shiftFraction: Double = 0.03  // kare genişliğinin oranı

    private let cameraShiftEnabled: Bool
    public init(cameraShiftEnabled: Bool) { self.cameraShiftEnabled = cameraShiftEnabled }

    /// Kamera örtüldü/karartıldı: ortalama parlaklık ya da doku çöktü.
    public func isCovered(brightness: Double, texture: Double) -> Bool {
        brightness < Self.minBrightness || texture < Self.minTexture
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
