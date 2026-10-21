import Foundation

/// Fotoğrafın neden çekildiği.
public enum SnapshotReason: Equatable, Sendable, Codable {
    case personSeen              // sen yokken biri kadrajda
    case locked(LockReason)      // bir tetikleyici kilitledi
    case wrongPasscode           // kilitliyken yanlış şifre denendi
}

/// Kaydedilmiş bir fotoğrafın künyesi (dosya şifreli; burada yalnızca referans).
public struct SnapshotRef: Equatable, Sendable, Codable {
    public var id: String
    public var at: Date
    public var reason: SnapshotReason
    public init(id: String, at: Date, reason: SnapshotReason) {
        self.id = id
        self.at = at
        self.reason = reason
    }
}

/// Fotoğraf hız sınırı: her karede değil, en fazla `minInterval` saniyede bir ve
/// nöbet başına `maxPerSession` adet. Depolamayı ve gereksiz görüntü birikimini sınırlar.
public struct SnapshotPolicy: Sendable {
    public static let minInterval: TimeInterval = 3
    public static let maxPerSession = 50

    private var lastCapture: TimeInterval = -.greatestFiniteMagnitude
    private var count = 0

    public init() {}

    /// `urgent`: yanlış şifre gibi seyrek ama kritik olaylar aralığı atlar (kilitlenme
    /// politikası zaten sınırlar); oturum üst sınırına yine tabidir.
    public mutating func allow(now: TimeInterval, urgent: Bool = false) -> Bool {
        guard count < Self.maxPerSession else { return false }
        guard urgent || now - lastCapture >= Self.minInterval else { return false }
        lastCapture = now
        count += 1
        return true
    }

    public mutating func reset() {
        lastCapture = -.greatestFiniteMagnitude
        count = 0
    }
}
