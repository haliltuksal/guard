import Foundation

public enum MatchResult: Equatable, Sendable {
    case owner, stranger, uncertain
}

/// Yüz eşleştirme eşikleri. Değerleri model değerlendirmesinden (spec §6.8-5) gelir;
/// burada yalnızca mantık tanımlıdır.
public struct Thresholds: Sendable, Equatable {
    public var accept: Float   // ilk tanıma ve kilit açma (tek kare FAR ≤ 1e-4)
    public var sustain: Float  // doğrulanmış izi sürdürme (daha düşük)
    public var reject: Float   // kesin yabancı
    public init(accept: Float, sustain: Float, reject: Float) {
        self.accept = accept; self.sustain = sustain; self.reject = reject
    }
}

/// Bir yüz vektörünü sahip profiliyle karşılaştırır.
public struct FaceMatcher: Sendable {
    private let profile: [[Float]]
    public let thresholds: Thresholds

    public init(profile: [[Float]], thresholds: Thresholds) {
        self.profile = profile
        self.thresholds = thresholds
    }

    /// Profildeki vektörlere kosinüs benzerliğinin en yüksek 3'ünün ortalaması.
    public func score(_ v: [Float]) -> Float {
        guard !profile.isEmpty else { return 0 }
        let sims = profile.map { Self.cosine($0, v) }.sorted(by: >)
        let top = sims.prefix(3)
        return top.reduce(0, +) / Float(top.count)
    }

    /// Histerezis: doğrulanmış bir sahip izi varsa `sustain`, yoksa `accept` eşiği uygulanır.
    public func classify(_ v: [Float], hasVerifiedTrack: Bool) -> MatchResult {
        classify(score: score(v), hasVerifiedTrack: hasVerifiedTrack)
    }

    /// Önceden hesaplanmış skorla sınıflandırma (pipeline skoru bir kez hesaplar).
    public func classify(score s: Float, hasVerifiedTrack: Bool) -> MatchResult {
        let acceptThreshold = hasVerifiedTrack ? thresholds.sustain : thresholds.accept
        if s >= acceptThreshold { return .owner }
        if s < thresholds.reject { return .stranger }
        return .uncertain
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom > 0 ? dot / denom : 0
    }
}
