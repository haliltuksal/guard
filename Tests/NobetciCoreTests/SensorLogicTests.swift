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
    #expect(s.isCovered(brightness: 0.2, texture: 0.001))   // loş + dokusuz (parmak/bez) → örtülü
    #expect(!s.isCovered(brightness: 0.5, texture: 0.001))  // parlak düz duvar → ÖRTÜLÜ DEĞİL (yanlış alarm değil)
    #expect(!s.isCovered(brightness: 0.5, texture: 0.5))
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
