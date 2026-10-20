import Testing
import Foundation
@testable import NobetciCore

@Test func manualClockAdvancesMonotonicOnly() {
    let c = ManualClock(now: 100, wall: Date(timeIntervalSince1970: 1000))
    c.advance(by: 2.5)
    #expect(c.now() == 102.5)
    #expect(c.wallNow() == Date(timeIntervalSince1970: 1002.5))
}

@Test func manualClockWallCanMoveIndependently() {
    let c = ManualClock(now: 0, wall: Date(timeIntervalSince1970: 1000))
    c.setWall(Date(timeIntervalSince1970: 500))   // duvar saati geri alındı
    c.advance(by: 10)                              // monoton ileri
    #expect(c.now() == 10)
    #expect(c.wallNow() == Date(timeIntervalSince1970: 510))
}

@Test func systemClockIsMonotonic() {
    let c = SystemClock()
    #expect(c.now() <= c.now())
}
