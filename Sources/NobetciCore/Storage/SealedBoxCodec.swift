import Foundation
import CryptoKit

/// Codable bir değeri AES-GCM-256 ile şifreleyip çözer (spec §9.2). Anahtar
/// Keychain'de durur; yüz profili, oturum kayıtları bu zarfla saklanır.
public enum SealedBoxCodec {
    public static func seal<T: Encodable>(_ value: T, key: SymmetricKey) throws -> Data {
        let plain = try JSONEncoder().encode(value)
        let sealed = try AES.GCM.seal(plain, using: key)
        guard let combined = sealed.combined else { throw SealedBoxError.sealFailed }
        return combined
    }

    public static func open<T: Decodable>(_ type: T.Type, from data: Data, key: SymmetricKey) throws -> T {
        let box = try AES.GCM.SealedBox(combined: data)
        let plain = try AES.GCM.open(box, using: key)   // yanlış anahtar/bozuk veri → throws
        return try JSONDecoder().decode(type, from: plain)
    }
}

public enum SealedBoxError: Error, Sendable { case sealFailed }
