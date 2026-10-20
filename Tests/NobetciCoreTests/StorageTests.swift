import Testing
import Foundation
import CryptoKit
@testable import NobetciCore

@Test func sealedBoxRoundTrips() throws {
    let key = SymmetricKey(size: .bits256)
    var s = GuardSettings(); s.strictMode = true
    let blob = try SealedBoxCodec.seal(s, key: key)
    let back = try SealedBoxCodec.open(GuardSettings.self, from: blob, key: key)
    #expect(back == s)
}

@Test func sealedBoxRejectsWrongKey() throws {
    let blob = try SealedBoxCodec.seal(GuardSettings(), key: SymmetricKey(size: .bits256))
    #expect(throws: (any Error).self) {
        _ = try SealedBoxCodec.open(GuardSettings.self, from: blob, key: SymmetricKey(size: .bits256))
    }
}

@Test func settingsCodecRoundTrips() throws {
    let key = SymmetricKey(size: .bits256)
    var s = GuardSettings(); s.distance = .far
    let data = try SettingsCodec.encode(s, hmacKey: key)
    #expect(try SettingsCodec.decode(data, hmacKey: key) == s)
}

@Test func settingsCodecRejectsTamperedPayload() throws {
    let key = SymmetricKey(size: .bits256)
    let data = try SettingsCodec.encode(GuardSettings(), hmacKey: key)
    var env = try JSONDecoder().decode(SettingsCodec.Envelope.self, from: data)
    env.payload[0] ^= 0xFF                              // diskte oynanmış gibi
    let tampered = try JSONEncoder().encode(env)
    #expect(throws: SettingsCodecError.self) {
        _ = try SettingsCodec.decode(tampered, hmacKey: key)
    }
}
