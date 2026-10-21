import Foundation

/// Sahip döndüğünde ne olacağı.
public enum ReturnBehavior: String, Codable, Sendable {
    case closeGuard   // varsayılan: nöbet kapanır
    case keepGuarding // nöbet sürer (omuz üstü koruması)
}

/// Kapak ve hareket hassasiyeti.
public enum Sensitivity: String, Codable, Sendable {
    case low, medium, high
}

/// Yabancı/kişi algılama mesafesi.
public enum DistanceSensitivity: String, Codable, Sendable {
    case near    // ≈ 0,8 m
    case medium  // ≈ 1,5 m
    case far     // ≈ 3 m
}

/// Global klavye kısayolu (Carbon keyCode + değiştirici maskesi).
public struct HotKeySpec: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var carbonModifiers: UInt32
    public init(keyCode: UInt16, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }
    /// ⌃⌥⌘L — keyCode 37 ('l'); Carbon RegisterEventHotKey maskeleri
    /// controlKey(0x1000) | optionKey(0x800) | cmdKey(0x100) = 0x1900.
    public static let `default` = HotKeySpec(keyCode: 37, carbonModifiers: 0x1900)
}

/// Kullanıcı tercihleri. İmzalı dosyada saklanır (spec §9.1); varsayılanlar spec §8.5.
public struct GuardSettings: Codable, Equatable, Sendable {
    public var returnBehavior: ReturnBehavior = .keepGuarding   // kullanıcı kararı: "Buradayım" diyene kadar nöbet sürer
    public var distance: DistanceSensitivity = .medium
    public var lid: Sensitivity = .medium
    public var motion: Sensitivity = .medium
    public var facelessDetection: Bool = true
    public var cameraShiftDetection: Bool = true
    public var displayTrigger: Bool = true
    public var usbTrigger: Bool = true
    public var powerTrigger: Bool = true
    public var strictMode: Bool = false
    /// Canlılık: kilit açmak için göz kırpma iste. Kullanıcı kararı (2026-10-21): varsayılan KAPALI —
    /// tanıyınca açılır. Açıldığında fotoğrafla kandırmayı zorlaştırır.
    public var requireBlink: Bool = false
    public var historyRetentionDays: Int = 30
    public var startAtLogin: Bool = true
    public var hotKey: HotKeySpec = .default

    public init() {}

    enum CodingKeys: String, CodingKey {
        case returnBehavior, distance, lid, motion, facelessDetection, cameraShiftDetection
        case displayTrigger, usbTrigger, powerTrigger, strictMode, requireBlink
        case historyRetentionDays, startAtLogin, hotKey
    }

    /// Eksik anahtarlar varsayılanla doldurulur: yeni bir ayar eklendiğinde diskteki eski
    /// settings.json geçersiz sayılıp tüm tercihler sıfırlanmasın.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GuardSettings()
        returnBehavior = try c.decodeIfPresent(ReturnBehavior.self, forKey: .returnBehavior) ?? d.returnBehavior
        distance = try c.decodeIfPresent(DistanceSensitivity.self, forKey: .distance) ?? d.distance
        lid = try c.decodeIfPresent(Sensitivity.self, forKey: .lid) ?? d.lid
        motion = try c.decodeIfPresent(Sensitivity.self, forKey: .motion) ?? d.motion
        facelessDetection = try c.decodeIfPresent(Bool.self, forKey: .facelessDetection) ?? d.facelessDetection
        cameraShiftDetection = try c.decodeIfPresent(Bool.self, forKey: .cameraShiftDetection) ?? d.cameraShiftDetection
        displayTrigger = try c.decodeIfPresent(Bool.self, forKey: .displayTrigger) ?? d.displayTrigger
        usbTrigger = try c.decodeIfPresent(Bool.self, forKey: .usbTrigger) ?? d.usbTrigger
        powerTrigger = try c.decodeIfPresent(Bool.self, forKey: .powerTrigger) ?? d.powerTrigger
        strictMode = try c.decodeIfPresent(Bool.self, forKey: .strictMode) ?? d.strictMode
        requireBlink = try c.decodeIfPresent(Bool.self, forKey: .requireBlink) ?? d.requireBlink
        historyRetentionDays = try c.decodeIfPresent(Int.self, forKey: .historyRetentionDays) ?? d.historyRetentionDays
        startAtLogin = try c.decodeIfPresent(Bool.self, forKey: .startAtLogin) ?? d.startAtLogin
        hotKey = try c.decodeIfPresent(HotKeySpec.self, forKey: .hotKey) ?? d.hotKey
    }
}
