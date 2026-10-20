import Testing
@testable import NobetciCore

// Not: `feed` mutating olduğu için #expect içinde çağrılamaz; sonucu önce değişkene al.

@Test func detectsBlinkOnReopenWithinWindow() {
    var b = BlinkDetector()
    let r0 = b.feed(ear: 0.30, now: 0.0); #expect(!r0)   // taban
    let r1 = b.feed(ear: 0.30, now: 0.1); #expect(!r1)
    let r2 = b.feed(ear: 0.10, now: 0.2); #expect(!r2)   // kapandı
    let r3 = b.feed(ear: 0.10, now: 0.3); #expect(!r3)   // kapalı
    let r4 = b.feed(ear: 0.30, now: 0.4); #expect(r4)    // açıldı → kırpma (0,2 sn)
    #expect(b.blinkedWithin(3.0, now: 0.5))
}

@Test func longClosureIsNotBlink() {
    var b = BlinkDetector()
    _ = b.feed(ear: 0.30, now: 0.0)
    _ = b.feed(ear: 0.10, now: 0.2)                      // kapandı
    let reopen = b.feed(ear: 0.30, now: 1.0); #expect(!reopen) // 0,8 sn kapalı → kırpma değil
    #expect(!b.blinkedWithin(3.0, now: 1.1))
}

@Test func blinkExpiresOutsideWindow() {
    var b = BlinkDetector()
    _ = b.feed(ear: 0.30, now: 0.0)
    _ = b.feed(ear: 0.10, now: 0.2)
    let blink = b.feed(ear: 0.30, now: 0.4); #expect(blink)  // kırpma anı 0.4
    #expect(!b.blinkedWithin(3.0, now: 5.0))                 // 4,6 sn sonra pencere dışı
}
