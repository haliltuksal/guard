import Testing
import Foundation
import CryptoKit
@testable import NobetciSystem
import NobetciCore

private func tempStore() -> (SecureFileStore, URL) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("nobetci-test-\(UUID().uuidString)", isDirectory: true)
    return (SecureFileStore(directory: dir, dataKey: SymmetricKey(size: .bits256),
                            settingsKey: SymmetricKey(size: .bits256)), dir)
}

@Test func encryptedProfileRoundTrips() throws {
    let (store, dir) = tempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    let profile: [[Float]] = [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]]
    try store.writeEncrypted(profile, to: "profile.bin")
    let back = try store.readEncrypted([[Float]].self, from: "profile.bin")
    #expect(back == profile)
}

@Test func profileFileOnDiskIsNotPlaintext() throws {
    let (store, dir) = tempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    try store.writeEncrypted(["gizli-işaret-12345"], to: "profile.bin")
    let raw = try Data(contentsOf: dir.appendingPathComponent("profile.bin"))
    #expect(!String(decoding: raw, as: UTF8.self).contains("gizli-işaret"))   // şifreli, düz metin yok
}

@Test func settingsRoundTripAndTamperFallsBackToDefaults() throws {
    let (store, dir) = tempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    var s = GuardSettings(); s.strictMode = true
    try store.writeSettings(s)
    #expect(store.readSettings().strictMode)

    // Diskteki ayar dosyasını boz → en güvenli varsayılanlara dönmeli (strictMode false).
    let url = dir.appendingPathComponent("settings.json")
    try Data("bozuk".utf8).write(to: url)
    #expect(!store.readSettings().strictMode)
}
