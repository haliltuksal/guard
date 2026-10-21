import Testing
@testable import NobetciCore

// Sen yokken yaklaşan kişilerin fotoğrafı — ama her karede değil: hız sınırı ve
// oturum üst sınırı (depolama ve gizlilik için).
// Not: `allow` mutating olduğu için sonucu önce değişkene al (#expect içinde çağrılamaz).

@Test func firstCaptureAllowedThenRateLimited() {
    var p = SnapshotPolicy()
    let a = p.allow(now: 0.0); #expect(a)
    let b = p.allow(now: 1.0); #expect(!b)   // 3 sn dolmadı
    let c = p.allow(now: 2.9); #expect(!c)
    let d = p.allow(now: 3.0); #expect(d)    // doldu
}

@Test func sessionCapStopsCapturing() {
    var p = SnapshotPolicy()
    var t = 0.0
    for _ in 0..<SnapshotPolicy.maxPerSession {
        let ok = p.allow(now: t); #expect(ok)
        t += SnapshotPolicy.minInterval
    }
    let over = p.allow(now: t); #expect(!over)   // üst sınır aşıldı
}

@Test func urgentCaptureSkipsIntervalButRespectsCap() {
    var p = SnapshotPolicy()
    let a = p.allow(now: 0.0); #expect(a)
    let blocked = p.allow(now: 0.1); #expect(!blocked)              // normal: aralık dolmadı
    let urgent = p.allow(now: 0.1, urgent: true); #expect(urgent)   // yanlış şifre: atlar
    var q = SnapshotPolicy()
    for _ in 0..<SnapshotPolicy.maxPerSession { _ = q.allow(now: 0, urgent: true) }
    let over = q.allow(now: 0, urgent: true); #expect(!over)        // üst sınır yine geçerli
}

@Test func resetClearsLimitAndCount() {
    var p = SnapshotPolicy()
    let a = p.allow(now: 0.0); #expect(a)
    p.reset()
    let b = p.allow(now: 0.1); #expect(b)        // yeni nöbet: baştan
}
