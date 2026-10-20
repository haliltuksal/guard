import Foundation
import CryptoKit
import NobetciCore

/// Şifreli dosya deposu: yüz profili ve oturum kayıtları AES-GCM ile; ayarlar
/// HMAC-SHA256 imzalı. Anahtarlar enjekte edilir (üretimde Keychain'den gelir),
/// böylece depo gerçek Keychain'e dokunmadan test edilebilir.
public struct SecureFileStore {
    private let directory: URL
    private let dataKey: SymmetricKey
    private let settingsKey: SymmetricKey
    private let fm = FileManager.default

    public init(directory: URL, dataKey: SymmetricKey, settingsKey: SymmetricKey) {
        self.directory = directory
        self.dataKey = dataKey
        self.settingsKey = settingsKey
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Nöbetçi", isDirectory: true)
    }

    private func ensureDir() throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: Şifreli Codable (profil, oturum kayıtları)

    public func writeEncrypted<T: Encodable>(_ value: T, to name: String) throws {
        try ensureDir()
        let blob = try SealedBoxCodec.seal(value, key: dataKey)
        try blob.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    public func readEncrypted<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        let blob = try Data(contentsOf: directory.appendingPathComponent(name))
        return try SealedBoxCodec.open(type, from: blob, key: dataKey)
    }

    // MARK: İmzalı ayarlar

    public func writeSettings(_ settings: GuardSettings) throws {
        try ensureDir()
        let data = try SettingsCodec.encode(settings, hmacKey: settingsKey)
        try data.write(to: directory.appendingPathComponent("settings.json"), options: .atomic)
    }

    /// Ayarları çözer; imza bozuksa en güvenli varsayılanlara döner (spec §9.1).
    public func readSettings() -> GuardSettings {
        let url = directory.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: url),
              let settings = try? SettingsCodec.decode(data, hmacKey: settingsKey) else {
            return GuardSettings()
        }
        return settings
    }

    public func removeAll() throws {
        if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
    }
}
