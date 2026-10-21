import Foundation

/// Karanlıkta yüz kalitesi tabanı.
///
/// Vision'ın yakalama kalitesi karanlıkta **herkes** için düşer; sabit 0,25 tabanı
/// sahibi kilit dışında bırakıyordu (arkadaş geri bildirimi, 2026-10-21: "buradan beni
/// nasıl tanıyacak"). Taban ışığa göre uyarlanır; eşiğin asıl işi bulanık fotoğrafla
/// kandırmayı zorlaştırmaktır ve karanlıkta saldırganın kesiti de aynı ölçüde kötüdür.
public enum QualityFloor {
    public static let normal: Float = 0.25
    public static let dark: Float = 0.12
    /// Bu parlaklığın altı "karanlık oda" sayılır (0…1 luma ortalaması).
    public static let darkBrightness: Float = 0.18

    public static func value(brightness: Float) -> Float {
        brightness < darkBrightness ? dark : normal
    }
}

/// Karanlığı sürekliliğe bakarak belirler: tek koyu kare (göz kırpma, gölge, kamera
/// ısınması) kamerayı uzun pozlamaya geçirmesin. Aydınlığa dönüş anındadır.
public struct LowLightDetector: Sendable {
    public static let sustain: TimeInterval = 1.5

    private var darkSince: TimeInterval?
    private var isDark = false

    public init() {}

    @discardableResult
    public mutating func update(brightness: Float, now: TimeInterval) -> Bool {
        if brightness < QualityFloor.darkBrightness {
            let start = darkSince ?? now
            darkSince = start
            if now - start >= Self.sustain { isDark = true }
        } else {
            darkSince = nil
            isDark = false
        }
        return isDark
    }

    public var dark: Bool { isDark }
}
