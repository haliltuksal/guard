import Foundation
import CommonCrypto

/// Uygulama şifresini PBKDF2-HMAC-SHA256 ile işler. Şifre asla saklanmaz; yalnızca
/// bu özet (+ tuz + tur sayısı) Keychain'de durur (spec §9.2). Karşılaştırma sabit zamanlı.
public enum PasscodeHasher {
    public static let keyLength = 32

    public static func hash(_ passcode: String, salt: Data, rounds: Int) -> Data {
        let passwordBytes = Array(passcode.utf8)
        var derived = [UInt8](repeating: 0, count: keyLength)
        let status = salt.withUnsafeBytes { saltBuffer -> Int32 in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordBytes.map { Int8(bitPattern: $0) }, passwordBytes.count,
                saltBuffer.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(rounds),
                &derived, derived.count)
        }
        precondition(status == kCCSuccess, "PBKDF2 başarısız: \(status)")
        return Data(derived)
    }

    /// Bu makinede yaklaşık `targetSeconds` sürecek tur sayısı (spec §9.2: ~250 ms, alt sınır 600.000).
    /// 50.000 turluk bir ölçümden doğrusal ölçeklenir; üst sınır savunmacı.
    public static func calibratedRounds(targetSeconds: Double, floor: Int) -> Int {
        let probeRounds = 50_000
        let salt = Data(repeating: 0x5A, count: 16)
        let start = DispatchTime.now().uptimeNanoseconds
        _ = hash("kalibrasyon", salt: salt, rounds: probeRounds)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        guard elapsed > 0 else { return floor }
        let scaled = Int(Double(probeRounds) * targetSeconds / elapsed)
        return min(max(scaled, floor), 100_000_000)
    }

    /// Sabit zamanlı karşılaştırma (timingsafe_bcmp) — deneme-yanılmaya karşı.
    public static func verify(_ passcode: String, salt: Data, rounds: Int, expected: Data) -> Bool {
        let candidate = hash(passcode, salt: salt, rounds: rounds)
        guard candidate.count == expected.count else { return false }
        return candidate.withUnsafeBytes { c in
            expected.withUnsafeBytes { e in
                timingsafe_bcmp(c.baseAddress, e.baseAddress, candidate.count) == 0
            }
        }
    }
}
