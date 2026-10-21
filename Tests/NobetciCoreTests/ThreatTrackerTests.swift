import Testing
@testable import NobetciCore

// Spec T1: sahip olmayan bir iz, ilk gözleminden itibaren 0,5 sn içinde kabul edilmezse
// "belirsiz"; 3 ardışık karede T_red altındaysa "yabancı". (Cihazda: kadraja geri giren
// sahip 0,1 sn'de "yabancı yüz" sayılmıştı — kare sayısı yerine zaman gerekir.)

@Test func returningFaceGetsShortGraceBeforeUncertain() {
    // 0,3 sn: dönen sahip ~9 karede tanınma şansı bulur; yabancıda blur gecikmesi kısa kalır (cihaz geri bildirimi).
    var t = ThreatTracker()
    let a = t.observe(trackID: 7, belowReject: false, now: 0.00); #expect(!a.uncertain && !a.stranger)
    let b = t.observe(trackID: 7, belowReject: false, now: 0.20); #expect(!b.uncertain)
    let c = t.observe(trackID: 7, belowReject: false, now: 0.30); #expect(c.uncertain && !c.stranger)
}

@Test func strangerAfterThreeConsecutiveBelowRejectFramesRegardlessOfAge() {
    var t = ThreatTracker()
    let a = t.observe(trackID: 1, belowReject: true, now: 0.00); #expect(!a.stranger)
    let b = t.observe(trackID: 1, belowReject: true, now: 0.03); #expect(!b.stranger)
    let c = t.observe(trackID: 1, belowReject: true, now: 0.06); #expect(c.stranger)      // 3. kare, 0,06 sn
}

@Test func belowRejectStreakResetsOnBetterFrame() {
    var t = ThreatTracker()
    _ = t.observe(trackID: 1, belowReject: true, now: 0.00)
    _ = t.observe(trackID: 1, belowReject: true, now: 0.03)
    _ = t.observe(trackID: 1, belowReject: false, now: 0.06)                              // sıfırla
    let d = t.observe(trackID: 1, belowReject: true, now: 0.09); #expect(!d.stranger)
}

@Test func acceptedTrackIsClearedAndLostTracksAreForgotten() {
    var t = ThreatTracker()
    _ = t.observe(trackID: 1, belowReject: false, now: 0.0)
    t.clear(trackID: 1)                                                                     // sahip kabul edildi
    let a = t.observe(trackID: 1, belowReject: false, now: 0.6); #expect(!a.uncertain)    // saat yeniden başlar
    _ = t.observe(trackID: 2, belowReject: false, now: 0.6)
    t.retain(onlyIDs: [1])                                                                  // iz 2 kayboldu
    let b = t.observe(trackID: 2, belowReject: false, now: 1.5); #expect(!b.uncertain)    // unutuldu → yeni iz gibi
}
