/// Sahibin karşıda olup olmadığı (son ~1,5 sn içinde tanınma).
public enum Presence: Equatable, Sendable {
    case present, absent
}

/// Kilidin neden tetiklendiği (spec §5.3 T1–T14 karşılığı).
public enum LockReason: String, Codable, Equatable, Sendable {
    case strangerFace, facelessPerson, input, lidAngle, motion
    case cameraCovered, cameraLost, cameraShift
    case display, usb, power, sleep, relaunch, filterLost
}
