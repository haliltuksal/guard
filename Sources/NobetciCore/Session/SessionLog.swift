import Foundation

/// Bir nöbet oturumunda kaydedilen olay türü. Fotoğraf alanı yoktur (spec §5.6 kaldırıldı).
public enum GuardLogKind: Equatable, Sendable, Codable {
    case guardStarted, guardEnded
    case ownerLeft, ownerReturned
    case triggered(LockReason)
    case unlockedByFace, unlockedByPasscode, wrongPasscode
    case sensorIssue(String), cameraIssue(String)
    case relaunched, slept, woke, endedByRestart
}

public struct GuardEventRecord: Equatable, Sendable, Codable {
    public var at: Date
    public var kind: GuardLogKind
    public init(at: Date, kind: GuardLogKind) {
        self.at = at
        self.kind = kind
    }
}

/// Bir nöbet oturumunun kaydı.
public struct SessionRecord: Equatable, Sendable, Codable {
    public var started: Date
    public var ended: Date?
    public var events: [GuardEventRecord]
    /// Bu nöbette çekilen fotoğrafların künyeleri (dosyalar şifreli, ayrı saklanır).
    public var snapshots: [SnapshotRef]

    public init(started: Date, ended: Date? = nil, events: [GuardEventRecord] = [], snapshots: [SnapshotRef] = []) {
        self.started = started
        self.ended = ended
        self.events = events
        self.snapshots = snapshots
    }

    /// Eski oturum dosyalarında `snapshots` yoktur; eksikse boş kabul edilir.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        started = try c.decode(Date.self, forKey: .started)
        ended = try c.decodeIfPresent(Date.self, forKey: .ended)
        events = try c.decodeIfPresent([GuardEventRecord].self, forKey: .events) ?? []
        snapshots = try c.decodeIfPresent([SnapshotRef].self, forKey: .snapshots) ?? []
    }
    public var duration: TimeInterval? { ended.map { $0.timeIntervalSince(started) } }
}
