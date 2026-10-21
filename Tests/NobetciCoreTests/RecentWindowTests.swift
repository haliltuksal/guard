import Testing
@testable import NobetciCore

// Spec §5.4.1: "≤ 1 sn içinde ≥ 5 analiz karesinde eşleşme" — ardışık değil, kayan pencere.
@Test func countsEventsWithinSlidingWindow() {
    var w = RecentWindow()
    for t in [0.0, 0.1, 0.2, 0.3, 0.4] { w.add(t) }
    #expect(w.count(within: 1.0, now: 0.4) == 5)
    #expect(w.count(within: 1.0, now: 1.2) == 3)   // 0.2, 0.3, 0.4 kaldı
    #expect(w.count(within: 1.0, now: 1.5) == 0)
}

@Test func missedFrameDoesNotResetCount() {
    var w = RecentWindow()
    for t in [0.0, 0.1, 0.2] { w.add(t) }
    // 0.3'te eşleşme yok (kaçan kare) — sayaç sıfırlanmaz
    w.add(0.4); w.add(0.5)
    #expect(w.count(within: 1.0, now: 0.5) == 5)
}
