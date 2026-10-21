import Testing
import Foundation
@testable import NobetciVision

// Karanlık oda + arkada parlak ekran: yüz koyu kalıyor, gömme vektörü gündüz
// çekilmiş profille eşleşmiyordu. Kesit, gömmeden önce aynı aydınlığa çekilir.

private func solid(_ value: UInt8, count: Int = 16) -> [UInt8] {
    (0..<count).flatMap { _ in [value, value, value, 255] }
}

private func lumaMean(_ rgba: [UInt8]) -> Float {
    var sum: Float = 0
    var n = 0
    for i in stride(from: 0, to: rgba.count, by: 4) {
        sum += ExposureNormalizer.luma(r: rgba[i], g: rgba[i + 1], b: rgba[i + 2])
        n += 1
    }
    return sum / Float(max(n, 1))
}

@Test func darkCropIsBroughtUpToTarget() {
    // Gradyanlı ama karanlık kesit (ortalama ~0,12) hedefe yaklaşmalı.
    var rgba: [UInt8] = []
    for i in 0..<64 { let v = UInt8(20 + (i % 16)); rgba += [v, v, v, 255] }
    let before = lumaMean(rgba)
    ExposureNormalizer.normalize(rgba: &rgba)
    let after = lumaMean(rgba)
    #expect(before < 0.2)
    #expect(abs(after - ExposureNormalizer.targetMean) < 0.12)
    #expect(after > before)
}

@Test func wellExposedCropIsBarelyChanged() {
    var rgba: [UInt8] = []
    for i in 0..<64 { let v = UInt8(90 + (i % 80)); rgba += [v, v, v, 255] }
    let before = lumaMean(rgba)
    ExposureNormalizer.normalize(rgba: &rgba)
    let after = lumaMean(rgba)
    #expect(abs(after - before) < 0.25)   // zaten iyi pozlanmış: büyük oynama yok
}

@Test func flatCropDoesNotExplode() {
    // Tamamen düz (std=0) kesitte kazanç sınırlanmazsa gürültü patlar.
    var rgba = solid(10)
    ExposureNormalizer.normalize(rgba: &rgba)
    #expect(rgba.allSatisfy { $0 <= 255 })
    let mean = lumaMean(rgba)
    #expect(mean >= 0 && mean <= 1)
}

@Test func alphaChannelIsPreserved() {
    var rgba = solid(30)
    ExposureNormalizer.normalize(rgba: &rgba)
    for i in stride(from: 3, to: rgba.count, by: 4) { #expect(rgba[i] == 255) }
}

@Test func brightBacklitCropIsPulledDown() {
    var rgba: [UInt8] = []
    for i in 0..<64 { let v = UInt8(200 + (i % 50)); rgba += [v, v, v, 255] }
    let before = lumaMean(rgba)
    ExposureNormalizer.normalize(rgba: &rgba)
    let after = lumaMean(rgba)
    #expect(after < before)
}
