import Testing
import Foundation
@testable import NobetciCore

// MARK: PasscodeHasher (düşük tur sayısı yalnızca testte; üretimde ≥600.000)

@Test func hashVerifiesCorrectRejectsWrong() {
    let salt = Data((0..<16).map { UInt8($0) })
    let h = PasscodeHasher.hash("gizli123", salt: salt, rounds: 1000)
    #expect(h.count == 32)
    #expect(PasscodeHasher.verify("gizli123", salt: salt, rounds: 1000, expected: h))
    #expect(!PasscodeHasher.verify("yanlış", salt: salt, rounds: 1000, expected: h))
}

@Test func differentSaltGivesDifferentHash() {
    let a = PasscodeHasher.hash("aynı", salt: Data(repeating: 1, count: 16), rounds: 1000)
    let b = PasscodeHasher.hash("aynı", salt: Data(repeating: 2, count: 16), rounds: 1000)
    #expect(a != b)
}

@Test func calibratedRoundsRespectFloor() {
    // Spec §9.2: tur sayısı bu Mac'te ~250 ms sürecek şekilde ölçülür; alt sınır 600.000.
    let rounds = PasscodeHasher.calibratedRounds(targetSeconds: 0.25, floor: 600_000)
    #expect(rounds >= 600_000)
    #expect(rounds <= 100_000_000)
}

// MARK: LockoutPolicy (Review Focus 4: yalnızca monoton saat)

@Test func lockoutUsesMonotonicClockOnly() {
    var p = LockoutPolicy()
    for _ in 0..<5 { _ = p.registerFailure(now: 0) }
    #expect(p.remaining(now: 0) == 30)    // 5. yanlış → 30 sn
    #expect(p.remaining(now: 15) == 15)   // monoton 15 sn ilerledi
    #expect(p.remaining(now: 30) == 0)    // monoton 30 sn → bitti
}

@Test func firstFourFailuresHaveNoWait() {
    var p = LockoutPolicy()
    for _ in 0..<4 {
        let w = p.registerFailure(now: 0)
        #expect(w == 0)
    }
}

@Test func lockoutDoublesAndCapsAt15Minutes() {
    var p = LockoutPolicy()
    for _ in 0..<5 { _ = p.registerFailure(now: 0) }   // 30
    #expect(p.registerFailure(now: 100) == 60)
    #expect(p.registerFailure(now: 200) == 120)
    #expect(p.registerFailure(now: 400) == 240)
    #expect(p.registerFailure(now: 700) == 480)
    #expect(p.registerFailure(now: 1200) == 900)        // cap 15 dk
    #expect(p.registerFailure(now: 2200) == 900)        // cap'te kalır
}

@Test func resetClearsLockout() {
    var p = LockoutPolicy()
    for _ in 0..<6 { _ = p.registerFailure(now: 0) }
    p.reset()
    #expect(p.remaining(now: 0) == 0)
    #expect(p.registerFailure(now: 0) == 0)             // sayaç sıfırdan başladı
}
