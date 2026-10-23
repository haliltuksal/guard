import Testing
@testable import NobetciCore

// MARK: LidAngleLogic (T4)

@Test func lidTriggersOnTwoConsecutiveSamplesBeyondThreshold() {
    var l = LidAngleLogic(sensitivity: .medium)   // eşik 3°
    l.setBaseline(100)
    let a = l.feed(angle: 101); #expect(!a)   // 1° < 3
    let b = l.feed(angle: 104); #expect(!b)   // ilk sapma
    let c = l.feed(angle: 104); #expect(c)    // ikinci ardışık sapma → tetik
}

@Test func lidIgnoresSingleSpike() {
    var l = LidAngleLogic(sensitivity: .medium)
    l.setBaseline(100)
    let a = l.feed(angle: 104); #expect(!a)   // tek sapma
    let b = l.feed(angle: 100); #expect(!b)   // geri döndü, sayaç sıfırlanır
    let c = l.feed(angle: 104); #expect(!c)   // yine tek sapma
}

// MARK: MotionLogic (T5)

@Test func motionTriggersOnTiltOrJerk() {
    let m = MotionLogic(sensitivity: .medium)  // tilt 8°, jerk 0.3g
    #expect(!m.triggered(tiltDegrees: 2, jerkG: 0.05))  // masada
    #expect(m.triggered(tiltDegrees: 15, jerkG: 0.0))   // eğildi/kaldırıldı
    #expect(m.triggered(tiltDegrees: 0, jerkG: 0.5))    // ani darbe
}

// MARK: SceneHealthLogic (T6, T7, T8)

@Test func sceneCoveredByDarknessOrDimTextureCollapse() {
    let s = SceneHealthLogic(cameraShiftEnabled: true)
    #expect(s.isCovered(brightness: 0.02, texture: 0.5))    // karanlık → örtülü
    #expect(s.isCovered(brightness: 0.15, texture: 0.005))  // loş + dokusuz (parmak/bez) → örtülü
    #expect(!s.isCovered(brightness: 0.29, texture: 0.015)) // gece odası, sahip çıkmış düz arka plan → ÖRTÜLÜ DEĞİL (ölçüldü: 0,29/0,04)
    #expect(!s.isCovered(brightness: 0.5, texture: 0.001))  // parlak düz duvar → ÖRTÜLÜ DEĞİL
    #expect(!s.isCovered(brightness: 0.5, texture: 0.5))
}

@Test func coveredRequiresHalfSecondPersistence() {
    // Spec T6: ≥ 0,5 sn süreklilik. Kamera ısınmasındaki birkaç siyah kare (ölçüldü: 9 kare ≈ 0,3 sn) tetiklememeli.
    var d = CoveredDebouncer()
    let a = d.feed(covered: true, now: 0.0); #expect(!a)
    let b = d.feed(covered: true, now: 0.3); #expect(!b)   // ısınma süresi kadar → henüz değil
    let c = d.feed(covered: true, now: 0.5); #expect(c)    // 0,5 sn sürdü → örtülü
    let e = d.feed(covered: false, now: 0.6); #expect(!e)  // açıldı → sıfırlanır
    let f = d.feed(covered: true, now: 0.7); #expect(!f)   // yeniden başlar
}

@Test func sceneFreezeAndShift() {
    let s = SceneHealthLogic(cameraShiftEnabled: true)
    #expect(s.isFrozen(frameGap: 1.2))
    #expect(!s.isFrozen(frameGap: 0.3))
    #expect(s.isShifted(translationFraction: 0.05))
    #expect(!s.isShifted(translationFraction: 0.01))
}

@Test func shiftDisabledWhenSettingOff() {
    let s = SceneHealthLogic(cameraShiftEnabled: false)
    #expect(!s.isShifted(translationFraction: 0.5))
}

// Karanlık oda: kalite tabanı ışığa göre uyarlanır. Vision'ın yakalama kalitesi
// karanlıkta herkes için düşer; sabit taban sahibi dışarıda bırakıyordu.

@Test func qualityFloorDropsInLowLight() {
    #expect(QualityFloor.value(brightness: 0.45) == QualityFloor.normal)
    #expect(QualityFloor.value(brightness: 0.05) == QualityFloor.dark)
    #expect(QualityFloor.dark < QualityFloor.normal)
}

@Test func lowLightIsDebouncedSoFlickerDoesNotSwitchModes() {
    var d = LowLightDetector()                           // mutating: sonuçları önce değişkene al
    let a = d.update(brightness: 0.05, now: 0); #expect(!a)      // tek kare yetmez
    let b = d.update(brightness: 0.05, now: 0.5); #expect(!b)
    let c = d.update(brightness: 0.05, now: 1.6); #expect(c)     // süreklilik → karanlık
    let e = d.update(brightness: 0.05, now: 2.0); #expect(e)
    let f = d.update(brightness: 0.50, now: 2.1); #expect(!f)    // ışık yanınca hemen çık
}

// Kalkan ışığı: bir kez yanınca kalkan kapanana kadar yanık kalır. Yoksa beyaz ekran
// odayı aydınlatır → "karanlık" algısı biter → ışık söner → oda kararır → 1,5 sn sonra
// yeniden yanar: sürekli titreme (review bulgusu).

@Test func shieldLightTurnsOnOnlyWhileShieldIsVisibleInTheDark() {
    var l = ShieldLightLatch()
    let hidden = l.update(dark: true, shieldVisible: false); #expect(!hidden)   // kalkan yokken ışık yok
    let shown = l.update(dark: true, shieldVisible: true); #expect(shown)
}

@Test func shieldLightStaysOnWhenItsOwnGlowBrightensTheRoom() {
    var l = ShieldLightLatch()
    _ = l.update(dark: true, shieldVisible: true)
    let lit = l.update(dark: false, shieldVisible: true); #expect(lit)          // kendi ışığı odayı aydınlattı: sönmez
}

@Test func shieldLightResetsWhenShieldHides() {
    var l = ShieldLightLatch()
    _ = l.update(dark: true, shieldVisible: true)
    let unlocked = l.update(dark: false, shieldVisible: false); #expect(!unlocked)   // kilit açıldı
    let nextLock = l.update(dark: false, shieldVisible: true); #expect(!nextLock)    // sonraki kilit aydınlıkta
}
