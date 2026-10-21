import Testing
import Foundation
import CoreGraphics
@testable import NobetciVision

// Sahip çapası: kimlik kare kare tanımaya değil, kesintisiz ize dayanır.
// "Yüzünü okuyamıyorum" ile "masadan kalktın" aynı şey değildir.

private let box = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)

@Test func verifyBindsTrackAndStaysAlive() {
    var a = OwnerAnchor()
    #expect(!a.isAlive(now: 0))
    a.verify(trackID: 7, box: box, now: 0)
    #expect(a.isAlive(now: 0))
    #expect(a.trackID == 7)
}

@Test func sustainKeepsAnchorWithoutAnyRecognition() {
    // Telefona bakarken yüz tanınmaz ama iz yaşar → sahip hâlâ masada.
    var a = OwnerAnchor()
    a.verify(trackID: 7, box: box, now: 0)
    var t = 0.0
    while t < 60 {                        // bir dakika boyunca tanıma yok
        t += 0.1
        a.sustain(box: box, now: t)
    }
    #expect(a.isAlive(now: t))            // eski davranış: 1,5 sn sonra "yok" derdi
}

@Test func anchorDiesWhenFaceDisappearsAndNothingCarriesIt() {
    var a = OwnerAnchor()
    a.verify(trackID: 7, box: box, now: 0)
    #expect(a.isAlive(now: OwnerAnchor.rebindWindow - 0.1))
    #expect(!a.isAlive(now: OwnerAnchor.rebindWindow + 0.1))
}

@Test func rebindAdoptsFaceReappearingInSamePlace() {
    // El yüzü kapatır, çekilir: aynı yerde beliren yüz yeni bir yabancı değildir.
    var a = OwnerAnchor()
    a.verify(trackID: 7, box: box, now: 0)
    #expect(a.canRebind(to: box.offsetBy(dx: 0.01, dy: 0.01), now: 0.8))
    a.rebind(trackID: 9, box: box, now: 0.8)
    #expect(a.trackID == 9)
    #expect(a.isAlive(now: 0.8))
}

@Test func rebindRejectsDistantFaceOrLateReturn() {
    var a = OwnerAnchor()
    a.verify(trackID: 7, box: box, now: 0)
    #expect(!a.canRebind(to: CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2), now: 0.5))   // başka yer
    #expect(!a.canRebind(to: box, now: OwnerAnchor.rebindWindow + 0.5))                     // çok geç
}

@Test func carryKeepsAnchorWhileSceneStaysOccupied() {
    // Yüz hiç görünmüyor ama kadrajda bir gövde var: sahne hiç boşalmadıysa sahip oradadır.
    var a = OwnerAnchor()
    a.verify(trackID: 7, box: box, now: 0)
    var t = 0.0
    while t < 30 {
        t += 0.2
        let carried = a.carry(now: t)
        #expect(carried)
    }
    #expect(a.isAlive(now: t))
}

@Test func carryStopsAtLimit() {
    var a = OwnerAnchor()
    a.verify(trackID: 7, box: box, now: 0)
    let carried = a.carry(now: OwnerAnchor.carryLimit + 1)
    #expect(!carried)
    #expect(!a.isAlive(now: OwnerAnchor.carryLimit + 1))
}

@Test func dropEndsTheAnchorImmediately() {
    var a = OwnerAnchor()
    a.verify(trackID: 7, box: box, now: 0)
    a.drop()
    #expect(!a.isAlive(now: 0))
    #expect(a.trackID == nil)
}

// Okunabilirlik: okunamayan yüzden kimlik kararı çıkarılmaz.

@Test func frontalSharpFaceIsReadable() {
    #expect(FaceReadability.isReadable(yaw: 0.1, pitch: -0.1, quality: 0.5))
}

@Test func steeplyAngledOrBlurryFaceIsUnreadable() {
    #expect(!FaceReadability.isReadable(yaw: 0.1, pitch: -0.9, quality: 0.5))   // telefona bakma
    #expect(!FaceReadability.isReadable(yaw: 1.0, pitch: 0.0, quality: 0.5))    // profil
    #expect(!FaceReadability.isReadable(yaw: 0.0, pitch: 0.0, quality: 0.05))   // bulanık/karanlık
}
