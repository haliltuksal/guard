import Foundation
/// Sahibin karşıda olup olmadığı (son ~1,5 sn içinde tanınma).
public enum Presence: Equatable, Sendable {
    case present, absent
}

/// Kilitli durumun bağlamı.
public struct LockedContext: Equatable, Sendable {
    public var reason: LockReason
    public var since: TimeInterval
    public var bystanderPresent: Bool
    public init(reason: LockReason, since: TimeInterval, bystanderPresent: Bool = false) {
        self.reason = reason
        self.since = since
        self.bystanderPresent = bystanderPresent
    }
}

/// Koruma durum makinesinin durumu (spec §5.1).
public enum GuardState: Equatable, Sendable {
    case off
    case preparing
    case guarding(Presence)
    case locked(LockedContext)
}

/// Kilidin neden tetiklendiği (spec §5.3 T1–T14 karşılığı).
public enum LockReason: String, Codable, Equatable, Sendable {
    case strangerFace, facelessPerson, input, lidAngle, motion
    case cameraCovered, cameraLost, cameraShift
    case display, usb, power, sleep, relaunch, filterLost
}
