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

/// Gerçek akış: sahip görünür (t=0; gözlem saati burada başlar), sonra kadrajdan çıkar (t=2,0 → 1,5 sn aşıldı → "yok").
/// Tohum, kamera asenkron açılırken eskimez; o yüzden "yok" için önce bir gözlem gerekir.
private func leave(_ e: inout GuardEngine) {
    _ = e.handle(.frame(ownerFrame(at: 0)))
    var empty = FrameSummary.empty
    empty.timestamp = 2.0
    _ = e.handle(.frame(empty))
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

@Test func strangerLocksOnSecondConsecutiveFrameNotFirst() {
    // Pipeline iz başına zamanlıyor (0,3 sn / 3 kare); motor yalnızca tek-kare arızasına karşı 2 kare ister.
    var e = started()
    func stranger(_ t: TimeInterval) -> FrameSummary { var f = FrameSummary.empty; f.strangerFacePresent = true; f.timestamp = t; return f }
    _ = e.handle(.frame(stranger(0.1)))   // 1 — tek kare kilitlemez
    if case .guarding = e.state {} else { Issue.record("tek karede kilitlenmemeli") }
    let fx = e.handle(.frame(stranger(0.2)))   // 2 → kilit
    if case .locked(let c) = e.state { #expect(c.reason == .strangerFace) } else { Issue.record("ikinci karede kilit beklenirdi") }
    #expect(fx.contains(.setInputPolicy(.blockAll)))
}

@Test func ownerFrameResetsStrangerStreak() {
    var e = started()
    func stranger(_ t: TimeInterval) -> FrameSummary { var f = FrameSummary.empty; f.strangerFacePresent = true; f.timestamp = t; return f }
    _ = e.handle(.frame(stranger(0.1)))
    _ = e.handle(.frame(ownerFrame(at: 0.15)))   // sahip göründü → sayaç sıfırlanır
    _ = e.handle(.frame(stranger(0.2)))
    if case .guarding = e.state {} else { Issue.record("sayaç sıfırlandığı için kilitlenmemeli") }
}

@Test func inputLocksOnlyWhenOwnerAbsent() {
    var e = started()
    #expect(e.handle(.input).isEmpty)           // sahip varken girdi serbest
    leave(&e)  // absent
    let fx = e.handle(.input)
    #expect(contains(fx, lock: .input))
}

@Test func facelessPersonRequiresPriorEmptyScene() {
    var e = started()
    leave(&e)  // absent
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
    leave(&e)  // absent
    let warn = e.handle(.hardware(.lidSensorLost))
    #expect(e.state == .guarding(.absent))
    #expect(warn.contains(.notify(.sensorFallback("kapak"))))
    let fx = e.handle(.cameraHealth(.lost))
    if case .locked(let c) = e.state { #expect(c.reason == .cameraLost) } else { Issue.record("kilit beklenirdi") }
    #expect(contains(fx, lock: .cameraLost))
}

@Test func coveredCameraWhilePresentDecaysPresenceThenLocks() {
    // Kamera örtülüyken sahip görülemez: kısa örtme tolere edilir, 1,5 sn sonra varlık
    // düşer (ilk girdi kilitler), bir sonraki örtülü kare T6 ile kilitler (fail-closed).
    let clock = ManualClock()
    var e = GuardEngine(clock: clock)
    _ = e.handle(.command(.startGuard))
    _ = e.handle(.prepareResult(ok: true, missing: []))
    #expect(e.handle(.cameraHealth(.covered)).isEmpty)          // kısa örtme → hiçbir şey
    #expect(e.state == .guarding(.present))
    clock.advance(by: 2.0)
    let fx = e.handle(.cameraHealth(.covered))                   // 1,5 sn geçti → absent
    #expect(e.state == .guarding(.absent))
    #expect(fx.contains(.setInputPolicy(.lockOnFirstInput)))
    let lockFx = e.handle(.cameraHealth(.covered))               // absent + örtülü → T6
    #expect(lockFx.contains(.logEvent(.triggered(.cameraCovered))))
}

@Test func lidTriggersOnlyWhenAbsentAndBaselineRefreshedWhenPresent() {
    var e = started()
    _ = e.handle(.lidAngle(100))                // present: taban 100
    leave(&e)  // absent
    #expect(e.handle(.lidAngle(104)).isEmpty)   // ilk sapma
    let fx = e.handle(.lidAngle(104))           // ikinci → tetik
    #expect(contains(fx, lock: .lidAngle))
}

// Fotoğraf (sen yokken kim yaklaştı) -------------------------------------

private func hasCapture(_ fx: [GuardEffect]) -> Bool {
    fx.contains { if case .captureSnapshot = $0 { return true }; return false }
}

@Test func capturesWhenPersonSeenWhileOwnerAway() {
    var e = started()
    leave(&e)
    var f = FrameSummary.empty; f.anyPersonPresent = true; f.timestamp = 2.1
    #expect(e.handle(.frame(f)).contains(.captureSnapshot(.personSeen)))
}

@Test func doesNotCaptureWhileOwnerPresent() {
    var e = started()
    var f = ownerFrame(at: 0.1); f.anyPersonPresent = true
    #expect(!hasCapture(e.handle(.frame(f))))
}

@Test func capturesOnLockTrigger() {
    var e = started()
    leave(&e)
    #expect(hasCapture(e.handle(.input)))          // T3 kilidi → kim dokundu
}

@Test func capturesOnWrongPasscode() {
    var e = started(verify: { $0 == "dogru" })
    leave(&e)
    _ = e.handle(.input)                            // locked
    #expect(hasCapture(e.handle(.passcode("yanlis"))))
}

@Test func snapshotsAreRateLimitedAcrossFrames() {
    var e = started()
    leave(&e)
    func person(_ t: TimeInterval) -> FrameSummary { var f = FrameSummary.empty; f.anyPersonPresent = true; f.timestamp = t; return f }
    #expect(hasCapture(e.handle(.frame(person(2.1)))))
    #expect(!hasCapture(e.handle(.frame(person(2.2)))))   // 3 sn dolmadı
    #expect(hasCapture(e.handle(.frame(person(5.2)))))
}

@Test func capturingDisabledBySetting() {
    var s = GuardSettings(); s.captureSnapshots = false
    var e = started(settings: s)
    leave(&e)
    var f = FrameSummary.empty; f.anyPersonPresent = true; f.timestamp = 2.1
    #expect(!hasCapture(e.handle(.frame(f))))
}

// Kilit açma -------------------------------------------------------------

@Test func faceUnlockKeepsGuardingByDefault() {
    var e = started()
    _ = e.handle(.input)                        // present: no-op
    leave(&e)  // absent
    _ = e.handle(.input)                        // → locked(.input)
    let fx = e.handle(.frame(ownerFrame(at: 3.0)))
    #expect(e.state == .guarding(.present))     // varsayılan: nöbet sürer ("Buradayım" diyene kadar)
    #expect(fx.contains(.hideShield) && !fx.contains(.stopSensors))
}

@Test func faceUnlockClosesGuardWhenConfigured() {
    var s = GuardSettings(); s.returnBehavior = .closeGuard
    var e = started(settings: s)
    leave(&e)
    _ = e.handle(.input)                        // → locked(.input)
    let fx = e.handle(.frame(ownerFrame(at: 3.0)))
    #expect(e.state == .off)
    #expect(fx.contains(.hideShield) && fx.contains(.stopSensors))
}

@Test func faceUnlockKeepsGuardingWhenConfigured() {
    var s = GuardSettings(); s.returnBehavior = .keepGuarding
    var e = started(settings: s)
    leave(&e)
    _ = e.handle(.input)                        // locked
    _ = e.handle(.frame(ownerFrame(at: 3.0)))
    #expect(e.state == .guarding(.present))
}

@Test func passcodeUnlocksAndWrongPasscodeIsLogged() {
    var e = started(verify: { $0 == "dogru" })
    leave(&e)
    _ = e.handle(.input)                        // locked
    let wrong = e.handle(.passcode("yanlis"))
    #expect(wrong.contains(.logEvent(.wrongPasscode)))
    if case .locked = e.state {} else { Issue.record("hâlâ kilitli olmalı") }
    let ok = e.handle(.passcode("dogru"))
    #expect(e.state == .guarding(.present))     // açıldı; varsayılan nöbet sürer
    #expect(ok.contains(.logEvent(.unlockedByPasscode)))
}

@Test func blinkPromptIsStickyForOneSecond() {
    // (Göz kırpma açıkken) istemden sonra tek bir kaçan kare mesajı "Seni arıyorum"a düşürmemeli (titreme).
    var s = GuardSettings(); s.requireBlink = true
    var e = started(settings: s)
    leave(&e)
    _ = e.handle(.input)                        // locked
    var ask = ownerFrame(at: 3.0); ask.blinkObservedWithin = nil
    #expect(e.handle(.frame(ask)).contains(.showShield(.blink)))
    var missed = FrameSummary.empty; missed.timestamp = 3.3     // kaçan kare → normalde "arıyorum"
    #expect(e.handle(.frame(missed)).contains(.showShield(.blink)))   // 1 sn içinde yapışkan
    var later = FrameSummary.empty; later.timestamp = 4.6
    #expect(e.handle(.frame(later)).contains(.showShield(.searching)))
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
    leave(&e)
    _ = e.handle(.input)                        // locked
    _ = e.handle(.command(.stopGuard))
    if case .locked = e.state {} else { Issue.record("kilitliyken durdurulamamalı") }
}

// Dönüşte "sen yokken bunlar oldu" — "Buradayım" beklemeden ------------------

/// Sahibi t=`seen`'de görüp t=`gone`'da kadrajı boş bırakır (ikinci kez uzaklaşma).
private func leaveAgain(_ e: inout GuardEngine, seen: TimeInterval, gone: TimeInterval) {
    _ = e.handle(.frame(ownerFrame(at: seen)))
    var empty = FrameSummary.empty
    empty.timestamp = gone
    _ = e.handle(.frame(empty))
}

/// Kilit yokken dönüş: OwnerPresence 3 ardışık sahip karesiyle izi yeniden doğrular.
private func comeBack(_ e: inout GuardEngine, from t: TimeInterval) -> [GuardEffect] {
    _ = e.handle(.frame(ownerFrame(at: t)))
    _ = e.handle(.frame(ownerFrame(at: t + 0.1)))
    return e.handle(.frame(ownerFrame(at: t + 0.2)))
}

private func personFrame(_ t: TimeInterval) -> FrameSummary {
    var f = FrameSummary.empty; f.anyPersonPresent = true; f.timestamp = t; return f
}

private func snapshotAlertCount(_ fx: [GuardEffect]) -> Int? {
    for case .showSnapshots(let n) in fx { return n }
    return nil
}

@Test func showsSnapshotsWhenOwnerReturnsFromLock() {
    // Sen yokken biri kadraja girdi → fotoğraf; sen dönünce yüzün tanınır tanınmaz görürsün.
    var e = started()
    leave(&e)
    #expect(hasCapture(e.handle(.frame(personFrame(2.1)))))
    _ = e.handle(.input)                                     // → locked
    let fx = e.handle(.frame(ownerFrame(at: 6.0)))           // yüz tanındı
    #expect(e.state == .guarding(.present))
    #expect(snapshotAlertCount(fx) != nil)                   // nöbet sürerken bile gösterilir
}

@Test func showsSnapshotsWhenOwnerReturnsWithoutLock() {
    // Kilit hiç devreye girmediyse de (yalnız kadrajda biri göründüyse) dönüşte gösterilir.
    var e = started()
    leave(&e)
    _ = e.handle(.frame(personFrame(2.1)))
    let fx = comeBack(&e, from: 3.0)
    #expect(e.state == .guarding(.present))
    #expect(snapshotAlertCount(fx) == 1)
}

@Test func noSnapshotAlertWhenNothingWasCaptured() {
    // Kimse yaklaşmadıysa dönüşte pencere açılmaz.
    var e = started()
    leave(&e)
    let fx = comeBack(&e, from: 3.0)
    #expect(e.state == .guarding(.present))
    #expect(snapshotAlertCount(fx) == nil)
}

@Test func snapshotAlertIsShownOnlyOncePerCapture() {
    var e = started()
    leave(&e)
    _ = e.handle(.frame(personFrame(2.1)))
    #expect(snapshotAlertCount(comeBack(&e, from: 3.0)) == 1)
    leaveAgain(&e, seen: 4.0, gone: 6.0)                     // tekrar uzaklaş (kimse yaklaşmıyor)
    #expect(snapshotAlertCount(comeBack(&e, from: 7.0)) == nil)   // aynı fotoğraf ikinci kez gösterilmez
}

@Test func passcodeUnlockAlsoShowsSnapshots() {
    var e = started(verify: { $0 == "dogru" })
    leave(&e)
    _ = e.handle(.frame(personFrame(2.1)))
    _ = e.handle(.input)                                     // locked
    let fx = e.handle(.passcode("dogru"))
    #expect(snapshotAlertCount(fx) != nil)
}

@Test func endingGuardDoesNotDuplicateAlertBesideReport() {
    // "Buradayım" raporu fotoğrafları zaten içeriyor; ayrıca uyarı penceresi açılmamalı.
    var e = started()
    leave(&e)
    _ = e.handle(.input)                                     // kilit (rapora konu olan olay)
    _ = e.handle(.frame(ownerFrame(at: 3.0)))                // yüzle açıldı → bekleyenler gösterildi
    leaveAgain(&e, seen: 4.0, gone: 6.0)
    _ = e.handle(.frame(personFrame(6.1)))                   // yeni fotoğraf (gösterilmedi)
    let fx = e.handle(.command(.stopGuard))
    #expect(snapshotAlertCount(fx) == nil)
    #expect(fx.contains { if case .showReport = $0 { return true }; return false })
}
