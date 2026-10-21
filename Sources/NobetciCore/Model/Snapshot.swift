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

/// Fotoğrafların kalıcı dizini: galeri bunu okur, saklama süresi bunu budar.
/// Yalnızca künyeler (kimlik, saat, sebep) burada; görüntüler ayrı şifreli dosyalarda.
public struct SnapshotIndex: Equatable, Sendable, Codable {
    /// Dizin sınırsız büyümesin (saklama süresi kapalıysa da geçerli bir tavan).
    public static let maxEntries = 500

    private var entries: [SnapshotRef] = []

    public init(entries: [SnapshotRef] = []) { self.entries = entries }

    /// Yeniden eskiye sıralı künyeler (galeri ve rapor bu sırayı kullanır).
    public var newestFirst: [SnapshotRef] { entries.sorted { $0.at > $1.at } }

    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }

    /// Künye ekler; tavan aşılırsa en eskileri düşürür ve dosyası silinsin diye döndürür.
    @discardableResult
    public mutating func add(_ ref: SnapshotRef) -> [SnapshotRef] {
        entries.append(ref)
        guard entries.count > Self.maxEntries else { return [] }
        let sorted = entries.sorted { $0.at > $1.at }
        entries = Array(sorted.prefix(Self.maxEntries))
        return Array(sorted.dropFirst(Self.maxEntries))
    }

    /// `days` günden eski künyeleri çıkarır ve dosyaları silinsin diye döndürür.
    /// `days <= 0` "süresiz sakla" demektir (ayarda kapatma karşılığı).
    @discardableResult
    public mutating func prune(olderThan days: Int, now: Date) -> [SnapshotRef] {
        guard days > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let dropped = entries.filter { $0.at < cutoff }
        entries.removeAll { $0.at < cutoff }
        return dropped
    }

    @discardableResult
    public mutating func remove(id: String) -> Bool {
        let before = entries.count
        entries.removeAll { $0.id == id }
        return entries.count != before
    }

    public mutating func removeAll() { entries.removeAll() }
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
