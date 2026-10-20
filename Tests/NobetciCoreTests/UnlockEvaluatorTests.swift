import Testing
@testable import NobetciCore

private func readyFrame() -> FrameSummary {
    var f = FrameSummary.empty
    f.ownerTrack = OwnerTrackState(recognizedFrameCount: 6, present: true)
    f.ownerQualityOK = true
    f.blinkObservedWithin = 1.0   // 1 sn önce kırptı
    return f
}

@Test func unlocksWhenAllConditionsMet() {
    let e = UnlockEvaluator()
    #expect(e.evaluate(frame: readyFrame(), settings: GuardSettings(), requestedTurn: .left, now: 10) == .unlock)
}

@Test func keepsWaitingUntilEnoughOwnerFrames() {
    let e = UnlockEvaluator()
    var f = readyFrame()
    f.ownerTrack = OwnerTrackState(recognizedFrameCount: 4, present: true)
    #expect(e.evaluate(frame: f, settings: GuardSettings(), requestedTurn: .left, now: 10) == .keepWaiting)
}

@Test func bystanderBlocksFaceUnlock() {
    let e = UnlockEvaluator()
    var f = readyFrame(); f.strangerFacePresent = true
    #expect(e.evaluate(frame: f, settings: GuardSettings(), requestedTurn: .left, now: 10) == .bystander)
    var g = readyFrame(); g.bodyPresentBeyondThreshold = true
    #expect(e.evaluate(frame: g, settings: GuardSettings(), requestedTurn: .left, now: 10) == .bystander)
}

@Test func lowQualityAndMissingBlinkReported() {
    let e = UnlockEvaluator()
    var lowQ = readyFrame(); lowQ.ownerQualityOK = false
    #expect(e.evaluate(frame: lowQ, settings: GuardSettings(), requestedTurn: .left, now: 10) == .lowQuality)
    var noBlink = readyFrame(); noBlink.blinkObservedWithin = nil
    #expect(e.evaluate(frame: noBlink, settings: GuardSettings(), requestedTurn: .left, now: 10) == .needBlink)
    var oldBlink = readyFrame(); oldBlink.blinkObservedWithin = 4.0
    #expect(e.evaluate(frame: oldBlink, settings: GuardSettings(), requestedTurn: .left, now: 10) == .needBlink)
}

@Test func strictModeRequiresGesture() {
    let e = UnlockEvaluator()
    var s = GuardSettings(); s.strictMode = true
    var notYet = readyFrame(); notYet.strictGestureSatisfied = false
    #expect(e.evaluate(frame: notYet, settings: s, requestedTurn: .right, now: 10) == .needGesture(.right))
    var done = readyFrame(); done.strictGestureSatisfied = true
    #expect(e.evaluate(frame: done, settings: s, requestedTurn: .right, now: 10) == .unlock)
}
