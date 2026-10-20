import Foundation

/// Yanlış şifre denemelerinde katlanan bekleme süresi (spec §5.4). İlk 4 deneme
/// beklemesiz; 5. → 30 sn; sonraki her yanlış öncekinin 2 katı; tavan 15 dk.
/// Süre YALNIZCA monoton saatle ölçülür (sistem saati oynatmaya dayanıklı).
/// Codable: sayaç ve bekleme Keychain'e yazılır; uygulama yeniden başlasa da sürer.
public struct LockoutPolicy: Codable, Equatable, Sendable {
    public static let firstPenalty: TimeInterval = 30
    public static let cap: TimeInterval = 900   // 15 dk

    public private(set) var failures = 0
    public private(set) var currentWait: TimeInterval = 0
    public private(set) var lockedUntil: TimeInterval = 0

    public init() {}

    /// Bir yanlış denemeyi kaydeder; bu denemeden sonraki bekleme süresini döndürür.
    public mutating func registerFailure(now: TimeInterval) -> TimeInterval {
        failures += 1
        if failures < 5 {
            currentWait = 0
        } else if failures == 5 {
            currentWait = Self.firstPenalty
        } else {
            currentWait = min(currentWait * 2, Self.cap)
        }
        lockedUntil = now + currentWait
        return currentWait
    }

    public func remaining(now: TimeInterval) -> TimeInterval {
        max(0, lockedUntil - now)
    }

    /// Doğru giriş sonrası: sayaç ve bekleme sıfırlanır.
    public mutating func reset() {
        failures = 0
        currentWait = 0
        lockedUntil = 0
    }

    /// Yeniden başlatma sonrası: monoton saat sıfırlandığı için mevcut beklemeyi
    /// yeni "now"a göre yeniden kur (spec §5.4: o anki bekleme baştan uygulanır).
    public mutating func rearm(now: TimeInterval) {
        lockedUntil = now + currentWait
    }
}
