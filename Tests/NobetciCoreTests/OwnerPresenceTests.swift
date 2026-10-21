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

@Test func seedDoesNotAgeBeforeFirstObservation() {
    // Nöbet başında tohumlanır; kamera asenkron açılır (model yükleme + ısınma, ölçüldü ~1-2 sn).
    // İlk gözlem gelene kadar geçen süre varlığı eskitmemeli — yoksa ilk belirsiz kare "yok" der.
    var p = OwnerPresence()
    p.seedPresent(now: 0)
    #expect(p.update(match: .uncertain, trackAlive: false, now: 5.0) == .present)  // ilk gözlem: saat buradan başlar
    #expect(p.update(match: .uncertain, trackAlive: false, now: 6.0) == .present)  // 1,0 sn < 1,5
    #expect(p.update(match: .uncertain, trackAlive: false, now: 6.6) == .absent)   // 1,6 sn > 1,5
}

@Test func brokenTrackStaysPresentUntilTimeout() {
    // Tek bir kaçırılan karede (iz koptu) sahip anında "yok" sayılmamalı; 1,5 sn
    // zaman aşımı tek de-doğrulama yolu olmalı (yoksa karşıdaki sahip yanlışlıkla kilitlenir).
    var p = OwnerPresence()
    for t in [0.0, 0.1, 0.2] { _ = p.update(match: .owner, trackAlive: true, now: t) }
    #expect(p.update(match: .owner, trackAlive: false, now: 0.4) == .present) // kısa kayıp → hâlâ present
    #expect(p.update(match: .uncertain, trackAlive: false, now: 2.0) == .absent) // 1,5 sn sonra → absent
    #expect(!p.hasVerifiedTrack)
}

// Çapa: yüz okunamasa da sahip oradaysa varlık düşmez (telefona bakma, burun kaşıma).

@Test func anchorKeepsPresenceWithoutAnyMatch() {
    var p = OwnerPresence()
    p.seedPresent(now: 0)
    var t = 0.0
    while t < 60 {
        t += 0.1
        let presence = p.update(match: .uncertain, trackAlive: false, anchored: true, now: t)
        #expect(presence == .present)      // çapa taze tutar
    }
}

@Test func presenceDropsAfterAnchorBreaks() {
    var p = OwnerPresence()
    p.seedPresent(now: 0)
    _ = p.update(match: .uncertain, trackAlive: false, anchored: true, now: 5.0)
    #expect(p.update(match: .uncertain, trackAlive: false, anchored: false, now: 6.0) == .present)   // 1,5 sn dolmadı
    #expect(p.update(match: .uncertain, trackAlive: false, anchored: false, now: 6.6) == .absent)    // doldu
}

@Test func anchorDoesNotResurrectPresenceAfterRealAbsence() {
    // Çapa kopmuş ve sahip yok sayılmışken, geç gelen bir "anchored" karesi tek başına
    // sahibi geri getirmemeli — geri dönüş yalnızca tanımayla olur.
    var p = OwnerPresence()
    p.seedPresent(now: 0)
    _ = p.update(match: .owner, trackAlive: true, anchored: true, now: 0)   // ilk gözlem (tohum eskimesin)
    #expect(p.update(match: .uncertain, trackAlive: false, anchored: false, now: 2.0) == .absent)
    #expect(p.update(match: .uncertain, trackAlive: false, anchored: true, now: 2.1) == .absent)
}
