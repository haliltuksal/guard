import Testing
import Foundation
@testable import NobetciCore

// Yardımcılar ------------------------------------------------------------

private func started(settings: GuardSettings = GuardSettings(),
                     verify: @escaping @Sendable (String) -> Bool = { _ in false }) -> GuardEngine {
    var e = GuardEngine(clock: ManualClock(), settings: settings, verifyPasscode: verify)
    _ = e.handle(.command(.startGuard))
    _ = e.handle(.prepareResult(ok: true, missing: []))   // → guarding(.present)
    return e
}

private func ownerFrame(at t: TimeInterval) -> FrameSummary {
    var f = FrameSummary.empty
    f.ownerTrack = OwnerTrackState(recognizedFrameCount: 6, present: true)
    f.ownerQualityOK = true
    f.blinkObservedWithin = 0.5
    f.timestamp = t
    f.sceneEmptyFor = 0
    return f
}

private func contains(_ effects: [GuardEffect], lock reason: LockReason) -> Bool {
    effects.contains(.logEvent(.triggered(reason)))
}

// Başlatma ---------------------------------------------------------------

@Test func startPreparesThenGuardsPresent() {
    var e = GuardEngine(clock: ManualClock())
    _ = e.handle(.command(.startGuard))
    #expect(e.state == .preparing)
    let fx = e.handle(.prepareResult(ok: true, missing: []))
    #expect(e.state == .guarding(.present))
    #expect(fx.contains(.startSensors) && fx.contains(.wakeKeep(true)) && fx.contains(.setInputPolicy(.passThrough)))
}

@Test func failedPrepareReturnsOffWithReason() {
    var e = GuardEngine(clock: ManualClock())
    _ = e.handle(.command(.startGuard))
    let fx = e.handle(.prepareResult(ok: false, missing: ["kamera"]))
    #expect(e.state == .off)
    #expect(fx.contains(.notify(.prepareFailed(["kamera"]))))
}

// Varlık geçişleri -------------------------------------------------------

@Test func ownerLeavesAfterTimeout() {
    var e = started()
    _ = e.handle(.frame(ownerFrame(at: 0)))
    let fx = e.handle(.frame({ var f = FrameSummary.empty; f.timestamp = 2.0; return f }()))
    #expect(e.state == .guarding(.absent))
    #expect(fx.contains(.setInputPolicy(.lockOnFirstInput)))
}

// Tetikleyiciler ---------------------------------------------------------

@Test func strangerLocksAfterThreeConsecutiveFramesNotOne() {
    var e = started()
    func stranger(_ t: TimeInterval) -> FrameSummary { var f = FrameSummary.empty; f.strangerFacePresent = true; f.timestamp = t; return f }
    _ = e.handle(.frame(stranger(0.1)))   // 1 — tek kare kilitlemez (sahip kafasını çevirmiş olabilir)
    _ = e.handle(.frame(stranger(0.2)))   // 2
    if case .guarding = e.state {} else { Issue.record("iki karede kilitlenmemeli") }
    let fx = e.handle(.frame(stranger(0.3)))   // 3 → kilit
    if case .locked(let c) = e.state { #expect(c.reason == .strangerFace) } else { Issue.record("üçüncü karede kilit beklenirdi") }
    #expect(fx.contains(.setInputPolicy(.blockAll)))
}

@Test func ownerFrameResetsStrangerStreak() {
    var e = started()
    func stranger(_ t: TimeInterval) -> FrameSummary { var f = FrameSummary.empty; f.strangerFacePresent = true; f.timestamp = t; return f }
    _ = e.handle(.frame(stranger(0.1)))
    _ = e.handle(.frame(stranger(0.2)))
    _ = e.handle(.frame(ownerFrame(at: 0.25)))   // sahip göründü → sayaç sıfırlanır
    _ = e.handle(.frame(stranger(0.3)))
    if case .guarding = e.state {} else { Issue.record("sayaç sıfırlandığı için kilitlenmemeli") }
}

@Test func inputLocksOnlyWhenOwnerAbsent() {
    var e = started()
    #expect(e.handle(.input).isEmpty)           // sahip varken girdi serbest
    _ = e.handle(.frame({ var f = FrameSummary.empty; f.timestamp = 2.0; return f }()))  // absent
    let fx = e.handle(.input)
    #expect(contains(fx, lock: .input))
}

@Test func facelessPersonRequiresPriorEmptyScene() {
    var e = started()
    _ = e.handle(.frame({ var f = FrameSummary.empty; f.timestamp = 2.0; return f }()))  // absent
    // Sahne yeni boşaldı: gövde T2'yi tetiklemez.
    var soon = FrameSummary.empty; soon.bodyPresentBeyondThreshold = true; soon.sceneEmptyFor = 0.5; soon.timestamp = 2.5
    #expect(e.handle(.frame(soon)).isEmpty)
    #expect(e.state == .guarding(.absent))
    // Sahne ≥ 3 sn boş kaldıktan sonra gövde: tetikler.
    var later = FrameSummary.empty; later.bodyPresentBeyondThreshold = true; later.sceneEmptyFor = 3.2; later.timestamp = 6.0
    let fx = e.handle(.frame(later))
    #expect(contains(fx, lock: .facelessPerson))
}

@Test func cameraLossLocksButSensorLossOnlyWarns() {
    var e = started()
    _ = e.handle(.frame({ var f = FrameSummary.empty; f.timestamp = 2.0; return f }()))  // absent
    let warn = e.handle(.hardware(.lidSensorLost))
    #expect(e.state == .guarding(.absent))
    #expect(warn.contains(.notify(.sensorFallback("kapak"))))
    let fx = e.handle(.cameraHealth(.lost))
    if case .locked(let c) = e.state { #expect(c.reason == .cameraLost) } else { Issue.record("kilit beklenirdi") }
    #expect(contains(fx, lock: .cameraLost))
}

@Test func lidTriggersOnlyWhenAbsentAndBaselineRefreshedWhenPresent() {
    var e = started()
    _ = e.handle(.lidAngle(100))                // present: taban 100
    _ = e.handle(.frame({ var f = FrameSummary.empty; f.timestamp = 2.0; return f }()))  // absent
    #expect(e.handle(.lidAngle(104)).isEmpty)   // ilk sapma
    let fx = e.handle(.lidAngle(104))           // ikinci → tetik
    #expect(contains(fx, lock: .lidAngle))
}

// Kilit açma -------------------------------------------------------------

@Test func faceUnlockClosesGuardByDefault() {
    var e = started()
    _ = e.handle(.input)                        // present: no-op
    _ = e.handle(.frame({ var f = FrameSummary.empty; f.timestamp = 2.0; return f }()))  // absent
    _ = e.handle(.input)                        // → locked(.input)
    let fx = e.handle(.frame(ownerFrame(at: 3.0)))
    #expect(e.state == .off)                    // closeGuard varsayılan
    #expect(fx.contains(.hideShield) && fx.contains(.stopSensors))
}

@Test func faceUnlockKeepsGuardingWhenConfigured() {
    var s = GuardSettings(); s.returnBehavior = .keepGuarding
    var e = started(settings: s)
    _ = e.handle(.frame({ var f = FrameSummary.empty; f.timestamp = 2.0; return f }()))
    _ = e.handle(.input)                        // locked
    _ = e.handle(.frame(ownerFrame(at: 3.0)))
    #expect(e.state == .guarding(.present))
}

@Test func passcodeUnlocksAndWrongPasscodeIsLogged() {
    var e = started(verify: { $0 == "dogru" })
    _ = e.handle(.frame({ var f = FrameSummary.empty; f.timestamp = 2.0; return f }()))
    _ = e.handle(.input)                        // locked
    let wrong = e.handle(.passcode("yanlis"))
    #expect(wrong.contains(.logEvent(.wrongPasscode)))
    if case .locked = e.state {} else { Issue.record("hâlâ kilitli olmalı") }
    let ok = e.handle(.passcode("dogru"))
    #expect(e.state == .off)
    #expect(ok.contains(.logEvent(.unlockedByPasscode)))
}

// Uyku / açılış ----------------------------------------------------------

@Test func sleepLocksAndWakeStaysLocked() {
    var e = started()
    let fx = e.handle(.willSleep)
    if case .locked(let c) = e.state { #expect(c.reason == .sleep) } else { Issue.record("kilit beklenirdi") }
    #expect(fx.contains(.setInputPolicy(.blockAll)))
    _ = e.handle(.didWake)
    if case .locked = e.state {} else { Issue.record("uyanınca kilitli kalmalı") }
}

@Test func relaunchInSameBootSessionStartsLocked() {
    var e = GuardEngine(clock: ManualClock())
    let prev = PersistedState(bootSession: "BOOT-1", active: true)
    let fx = e.handle(.launched(bootSession: "BOOT-1", previous: prev))
    if case .locked(let c) = e.state { #expect(c.reason == .relaunch) } else { Issue.record("kilit beklenirdi") }
    #expect(fx.contains(.setInputPolicy(.blockAll)) && fx.contains(.startSensors))
}

@Test func launchAfterRebootStartsOff() {
    var e = GuardEngine(clock: ManualClock())
    let prev = PersistedState(bootSession: "BOOT-1", active: true)
    _ = e.handle(.launched(bootSession: "BOOT-2", previous: prev))   // farklı oturum
    #expect(e.state == .off)
}

@Test func stopGuardWhileLockedIsIgnored() {
    var e = started()
    _ = e.handle(.frame({ var f = FrameSummary.empty; f.timestamp = 2.0; return f }()))
    _ = e.handle(.input)                        // locked
    _ = e.handle(.command(.stopGuard))
    if case .locked = e.state {} else { Issue.record("kilitliyken durdurulamamalı") }
}
