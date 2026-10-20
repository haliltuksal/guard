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
    /// ⌃⌥⌘L — keyCode 37 ('l'), control+option+command.
    public static let `default` = HotKeySpec(keyCode: 37, carbonModifiers: 0x1 | 0x4 | 0x8)
}

/// Kullanıcı tercihleri. İmzalı dosyada saklanır (spec §9.1); varsayılanlar spec §8.5.
public struct GuardSettings: Codable, Equatable, Sendable {
    public var returnBehavior: ReturnBehavior = .closeGuard
    public var distance: DistanceSensitivity = .medium
    public var lid: Sensitivity = .medium
    public var motion: Sensitivity = .medium
    public var facelessDetection: Bool = true
    public var cameraShiftDetection: Bool = true
    public var displayTrigger: Bool = true
    public var usbTrigger: Bool = true
    public var powerTrigger: Bool = true
    public var strictMode: Bool = false
    public var historyRetentionDays: Int = 30
    public var startAtLogin: Bool = true
    public var hotKey: HotKeySpec = .default

    public init() {}
}
