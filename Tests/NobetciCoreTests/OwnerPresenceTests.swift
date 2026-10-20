import Testing
@testable import NobetciCore

@Test func ownerBecomesPresentAfterThreeOwnerFrames() {
    var p = OwnerPresence()
    #expect(p.update(match: .owner, trackAlive: true, now: 0) == .absent)   // 1
    #expect(p.update(match: .owner, trackAlive: true, now: 0.1) == .absent) // 2
    #expect(p.update(match: .owner, trackAlive: true, now: 0.2) == .present) // 3 → doğrulandı
    #expect(p.hasVerifiedTrack)
}

@Test func verifiedOwnerSurvivesSingleUncertainFrameWithinTimeout() {
    var p = OwnerPresence()
    for t in [0.0, 0.1, 0.2] { _ = p.update(match: .owner, trackAlive: true, now: t) }
    #expect(p.update(match: .uncertain, trackAlive: true, now: 0.5) == .present) // 1,5 sn içinde
}

@Test func ownerGoesAbsentAfterTimeout() {
    var p = OwnerPresence()
    for t in [0.0, 0.1, 0.2] { _ = p.update(match: .owner, trackAlive: true, now: t) }
    #expect(p.update(match: .uncertain, trackAlive: true, now: 1.9) == .absent) // son görülme 0.2 + 1,5 < 1.9
    #expect(!p.hasVerifiedTrack)
}

@Test func brokenTrackDropsVerification() {
    var p = OwnerPresence()
    for t in [0.0, 0.1, 0.2] { _ = p.update(match: .owner, trackAlive: true, now: t) }
    #expect(p.update(match: .owner, trackAlive: false, now: 0.3) == .absent) // iz koptu
    #expect(!p.hasVerifiedTrack)
}
