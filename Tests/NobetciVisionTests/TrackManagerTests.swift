import Testing
import CoreGraphics
@testable import NobetciVision

@Test func sameBoxKeepsIdentityAndCountsFrames() {
    var tm = TrackManager()
    let box = CGRect(x: 10, y: 10, width: 50, height: 50)
    let t1 = tm.update(boxes: [box], now: 0)
    let t2 = tm.update(boxes: [box.offsetBy(dx: 2, dy: 2)], now: 0.1) // örtüşür
    #expect(t1.count == 1 && t2.count == 1)
    #expect(t1[0].id == t2[0].id)
    #expect(t2[0].frameCount == 2)
}

@Test func disjointBoxGetsNewIdentity() {
    var tm = TrackManager()
    let first = tm.update(boxes: [CGRect(x: 0, y: 0, width: 20, height: 20)], now: 0)
    let t = tm.update(boxes: [CGRect(x: 200, y: 200, width: 20, height: 20)], now: 0.1)
    // Eski iz süresi dolmadığı için kalır; ayrık kutu yeni kimlik alır (eskinin id'sini miras almaz).
    #expect(t.count == 2)
    let newTrack = t.first { $0.id != first[0].id }
    #expect(newTrack?.frameCount == 1)
}

@Test func trackExpiresAfterTimeout() {
    var tm = TrackManager()
    _ = tm.update(boxes: [CGRect(x: 0, y: 0, width: 20, height: 20)], now: 0)
    let gone = tm.update(boxes: [], now: TrackManager.expiry + 0.1)
    #expect(gone.isEmpty)
}

@Test func twoBoxesTrackedIndependently() {
    var tm = TrackManager()
    let a = CGRect(x: 0, y: 0, width: 30, height: 30)
    let b = CGRect(x: 100, y: 100, width: 30, height: 30)
    _ = tm.update(boxes: [a, b], now: 0)
    let t = tm.update(boxes: [a, b], now: 0.1)
    #expect(t.count == 2)
    #expect(Set(t.map(\.id)).count == 2)
    #expect(t.allSatisfy { $0.frameCount == 2 })
}
