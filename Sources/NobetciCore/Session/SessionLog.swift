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
    public init(started: Date, ended: Date? = nil, events: [GuardEventRecord] = []) {
        self.started = started
        self.ended = ended
        self.events = events
    }
    public var duration: TimeInterval? { ended.map { $0.timeIntervalSince(started) } }
}
