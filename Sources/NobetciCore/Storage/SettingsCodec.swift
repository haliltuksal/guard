import Foundation
import CryptoKit

public enum SettingsCodecError: Error, Sendable { case tampered }

/// Ayarları HMAC-SHA256 imzalı JSON olarak kodlar/çözer (spec §9.1). Mod kapalıyken
/// Terminal'den ayar dosyasını değiştirip korumayı sessizce zayıflatmayı önler:
/// imza tutmazsa çözme başarısız olur, çağıran en güvenli varsayılanlara döner.
public enum SettingsCodec {
    struct Envelope: Codable {
        var payload: Data
        var mac: Data
    }

    public static func encode(_ settings: GuardSettings, hmacKey: SymmetricKey) throws -> Data {
        let payload = try JSONEncoder().encode(settings)
        let mac = HMAC<SHA256>.authenticationCode(for: payload, using: hmacKey)
        return try JSONEncoder().encode(Envelope(payload: payload, mac: Data(mac)))
    }

    public static func decode(_ data: Data, hmacKey: SymmetricKey) throws -> GuardSettings {
        let env = try JSONDecoder().decode(Envelope.self, from: data)
        let valid = HMAC<SHA256>.isValidAuthenticationCode(env.mac, authenticating: env.payload, using: hmacKey)
        guard valid else { throw SettingsCodecError.tampered }
        return try JSONDecoder().decode(GuardSettings.self, from: env.payload)
    }
}
