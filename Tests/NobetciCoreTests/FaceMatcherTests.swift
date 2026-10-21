import Testing
@testable import NobetciCore

private let th = Thresholds(accept: 0.5, sustain: 0.4, reject: 0.3)

@Test func scoreIsOneForIdenticalZeroForOrthogonal() {
    let m = FaceMatcher(profile: [[1, 0]], thresholds: th)
    #expect(abs(m.score([1, 0]) - 1) < 1e-6)
    #expect(abs(m.score([0, 1])) < 1e-6)
}

@Test func scoreAveragesTopThree() {
    // En yüksek 3 benzerliğin ortalaması; dördüncü (düşük) göz ardı edilir.
    let m = FaceMatcher(profile: [[1, 0], [1, 0], [1, 0], [0, 1]], thresholds: th)
    #expect(abs(m.score([1, 0]) - 1) < 1e-6)
}

@Test func classifyOwnerStrangerUncertain() {
    let m = FaceMatcher(profile: [[1, 0]], thresholds: th)
    #expect(m.classify([1, 0], hasVerifiedTrack: false) == .owner)        // 1.0 ≥ accept
    #expect(m.classify([0, 1], hasVerifiedTrack: false) == .stranger)     // 0.0 < reject
    #expect(m.classify([0.35, 0.9367], hasVerifiedTrack: false) == .uncertain) // reject ≤ 0.35 < accept
}

@Test func classifyFromPrecomputedScoreMatchesClassify() {
    // Pipeline skoru bir kez hesaplayıp hem sınıflandırma hem "kabul seviyesinde mi" için kullanır.
    let m = FaceMatcher(profile: [[1, 0]], thresholds: th)
    for v: [Float] in [[1, 0], [0, 1], [0.35, 0.9367], [0.45, 0.893]] {
        #expect(m.classify(score: m.score(v), hasVerifiedTrack: false) == m.classify(v, hasVerifiedTrack: false))
        #expect(m.classify(score: m.score(v), hasVerifiedTrack: true) == m.classify(v, hasVerifiedTrack: true))
    }
    #expect(m.thresholds.accept == 0.5)
}

@Test func sustainThresholdHoldsVerifiedTrack() {
    let m = FaceMatcher(profile: [[1, 0]], thresholds: th)
    let v: [Float] = [0.45, 0.893]   // cos ≈ 0.45: accept(0.5) altında, sustain(0.4) üstünde
    #expect(m.classify(v, hasVerifiedTrack: false) == .uncertain)  // ilk tanıma: accept gerekir
    #expect(m.classify(v, hasVerifiedTrack: true) == .owner)       // sürdürme: sustain yeter
}

@Test func sustainThresholdOnlyAppliesToTheOwnTrack() {
    // Sürdürme eşiği kimlik sürekliliğine aittir: yabancı bir yüze uygulanırsa
    // 0,55–0,70 arası skorlayan biri "sahip" sayılır.
    let m = FaceMatcher(profile: [[1, 0, 0]], thresholds: Thresholds(accept: 0.70, sustain: 0.55, reject: 0.40))
    #expect(m.classify(score: 0.60, hasVerifiedTrack: true) == .owner)       // sahip izi
    #expect(m.classify(score: 0.60, hasVerifiedTrack: false) == .uncertain)  // başka iz
}

@Test func addingGrowsTheProfileWithoutTouchingThresholds() {
    // Şifreyle açılışta öğrenilen vektör profile katılır; eşikler değişmez.
    let m = FaceMatcher(profile: [[1, 0, 0]], thresholds: Thresholds(accept: 0.70, sustain: 0.55, reject: 0.40))
    let grown = m.adding([[0, 1, 0]])
    #expect(m.profileSize == 1 && grown.profileSize == 2)
    #expect(grown.thresholds == m.thresholds)
    #expect(grown.score([0, 1, 0]) > m.score([0, 1, 0]))   // yeni görünüm artık tanınıyor
}
