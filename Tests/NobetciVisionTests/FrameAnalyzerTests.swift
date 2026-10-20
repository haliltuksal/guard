import Testing
@testable import NobetciVision

@Test func constantFrameHasNoMotionOrTexture() {
    var a = FrameAnalyzer()
    let gray = [Float](repeating: 0.5, count: 64)
    let m1 = a.analyze(gray: gray)
    #expect(abs(m1.brightness - 0.5) < 1e-6)
    #expect(m1.texture < 1e-6)
    #expect(m1.motionEnergy < 1e-6)          // ilk kare: önceki yok → 0
    let m2 = a.analyze(gray: gray)
    #expect(m2.motionEnergy < 1e-6)          // değişmedi
}

@Test func changedFrameHasMotion() {
    var a = FrameAnalyzer()
    _ = a.analyze(gray: [Float](repeating: 0.2, count: 64))
    let m = a.analyze(gray: [Float](repeating: 0.8, count: 64))
    #expect(abs(m.motionEnergy - 0.6) < 1e-6) // ortalama |0.8-0.2|
}

@Test func highContrastFrameHasTexture() {
    var a = FrameAnalyzer()
    var gray = [Float](repeating: 0, count: 64)
    for i in stride(from: 0, to: 64, by: 2) { gray[i] = 1 }  // satranç tahtası
    let m = a.analyze(gray: gray)
    #expect(m.texture > 0.1)
    #expect(abs(m.brightness - 0.5) < 1e-6)
}

@Test func darkFrameHasLowBrightness() {
    var a = FrameAnalyzer()
    let m = a.analyze(gray: [Float](repeating: 0.02, count: 64))
    #expect(m.brightness < 0.08)              // T6 örtülü/karanlık eşiğinin altında
}
