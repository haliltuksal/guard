import Testing
import Foundation
import CoreGraphics
@testable import NobetciVision

// Kişi maskesi: yüz dedektörü profil/örtülü yüzü kaçırdığında ve üst gövde dedektörü
// yakın mesafede hiç tetiklenmediğinde (cihazda ölçüldü: %0) "kadrajda insan var mı"
// sorusunu yöne bağlı olmadan yanıtlar.

/// 4x4 maske: üst iki satır dolu (Vision koordinatı sol-alt başlangıçlı, yani y büyük = üst).
private func mask(_ rows: [[UInt8]]) -> PersonMask {
    PersonMask(values: rows.flatMap { $0 }, width: rows[0].count, height: rows.count)
}

@Test func totalCoverageCountsPersonPixels() {
    let m = mask([[255, 255, 0, 0],
                  [255, 255, 0, 0],
                  [0, 0, 0, 0],
                  [0, 0, 0, 0]])
    #expect(abs(m.total - 0.25) < 0.001)
}

@Test func coverageInRegionIgnoresPixelsOutside() {
    // Sol yarı dolu (ör. sandalyedeki mont), sağ yarı boş.
    let m = mask([[255, 255, 0, 0],
                  [255, 255, 0, 0],
                  [255, 255, 0, 0],
                  [255, 255, 0, 0]])
    let right = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
    let left = CGRect(x: 0, y: 0, width: 0.5, height: 1)
    #expect(m.coverage(in: right) < 0.01)   // sahibin bölgesi boş → çapa taşınmaz
    #expect(m.coverage(in: left) > 0.99)
}

@Test func emptyMaskHasNoCoverage() {
    let m = mask([[0, 0], [0, 0]])
    #expect(m.total == 0)
    #expect(m.coverage(in: CGRect(x: 0, y: 0, width: 1, height: 1)) == 0)
}

@Test func coverageClampsRegionToImage() {
    let m = mask([[255, 255], [255, 255]])
    let huge = CGRect(x: -1, y: -1, width: 4, height: 4)
    #expect(abs(m.coverage(in: huge) - 1.0) < 0.001)
}

// Sahibin bölgesi: son yüz kutusundan gövdeyi de kapsayan dikdörtgen.

@Test func ownerRegionCoversTorsoBelowTheFace() {
    let face = CGRect(x: 0.4, y: 0.6, width: 0.2, height: 0.2)
    let region = PersonMask.ownerRegion(faceBox: face)
    #expect(region.minY == 0)                 // gövde aşağıda
    #expect(region.maxY >= face.maxY)         // başı da kapsar
    #expect(region.width > face.width)        // omuzlar için geniş
    #expect(region.minX >= 0 && region.maxX <= 1)
}

@Test func ownerRegionStaysInsideFrameAtTheEdge() {
    let face = CGRect(x: 0.02, y: 0.8, width: 0.2, height: 0.2)
    let region = PersonMask.ownerRegion(faceBox: face)
    #expect(region.minX >= 0 && region.maxX <= 1)
    #expect(region.maxY <= 1)
}
