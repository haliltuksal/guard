import Foundation

/// Sahip varlığını ardışık kare oylarıyla doğrular ve histerezisle sürdürür:
/// 3 ardışık "owner" karesi izi doğrular; iz kopmadıkça ve son sahip gözleminden
/// 1,5 sn geçmedikçe "present" kalır.
public struct OwnerPresence {
    public static let absenceTimeout: TimeInterval = 1.5
    private static let framesToVerify = 3

    private var consecutiveOwnerFrames = 0
    private var verified = false
    private var lastOwnerSeen: TimeInterval = -.greatestFiniteMagnitude

    public init() {}

    public var hasVerifiedTrack: Bool { verified }

    /// Sahip olduğu bilinen bir anda (nöbet başlangıcı, kilit açılışı) izi doğrulanmış sayar.
    public mutating func seedPresent(now: TimeInterval) {
        verified = true
        consecutiveOwnerFrames = Self.framesToVerify
        lastOwnerSeen = now
    }

    public mutating func update(match: MatchResult, trackAlive: Bool, now: TimeInterval) -> Presence {
        guard trackAlive else {
            // İz koptu: doğrulama düşer, yeni iz baştan doğrulanmalı.
            consecutiveOwnerFrames = 0
            verified = false
            return .absent
        }
        switch match {
        case .owner:
            consecutiveOwnerFrames += 1
            lastOwnerSeen = now
            if consecutiveOwnerFrames >= Self.framesToVerify { verified = true }
        case .stranger, .uncertain:
            consecutiveOwnerFrames = 0   // doğrulamaya doğru sayımı sıfırla (verified timeout'la düşer)
        }
        if verified, now - lastOwnerSeen <= Self.absenceTimeout {
            return .present
        }
        if now - lastOwnerSeen > Self.absenceTimeout { verified = false }
        return .absent
    }
}
