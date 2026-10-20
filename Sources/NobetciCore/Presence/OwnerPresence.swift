import Foundation

/// Sahip varlığını ardışık kare oylarıyla doğrular ve histerezisle sürdürür:
/// 3 ardışık "owner" karesi izi doğrular; iz kopmadıkça ve son sahip gözleminden
/// 1,5 sn geçmedikçe "present" kalır.
public struct OwnerPresence: Sendable {
    public static let absenceTimeout: TimeInterval = 1.5
    private static let framesToVerify = 3

    private var consecutiveOwnerFrames = 0
    private var verified = false
    private var lastOwnerSeen: TimeInterval = -.greatestFiniteMagnitude
    private var awaitingFirstObservation = false

    public init() {}

    public var hasVerifiedTrack: Bool { verified }

    /// Sahip olduğu bilinen bir anda (nöbet başlangıcı, kilit açılışı) izi doğrulanmış sayar.
    public mutating func seedPresent(now: TimeInterval) {
        verified = true
        consecutiveOwnerFrames = Self.framesToVerify
        lastOwnerSeen = now
        awaitingFirstObservation = true
    }

    public mutating func update(match: MatchResult, trackAlive: Bool, now: TimeInterval) -> Presence {
        if awaitingFirstObservation {
            // Tohum ile ilk gözlem arasındaki süre (asenkron kamera açılışı, ~1–2 sn) varlığı
            // eskitmez; zaman aşımı saati ilk gözlemde başlar.
            awaitingFirstObservation = false
            lastOwnerSeen = now
        }
        // Yalnızca sahip karesi "görülme"yi ileri taşır. Kaçırılan/kopan iz ya da
        // yabancı/belirsiz kare doğrulamaya doğru sayımı sıfırlar AMA doğrulamayı
        // anında düşürmez — tek de-doğrulama yolu 1,5 sn'lik zaman aşımıdır (histerezis).
        if match == .owner, trackAlive {
            consecutiveOwnerFrames += 1
            lastOwnerSeen = now
            if consecutiveOwnerFrames >= Self.framesToVerify { verified = true }
        } else {
            consecutiveOwnerFrames = 0
        }
        if verified, now - lastOwnerSeen <= Self.absenceTimeout {
            return .present
        }
        if now - lastOwnerSeen > Self.absenceTimeout { verified = false }
        return .absent
    }
}
