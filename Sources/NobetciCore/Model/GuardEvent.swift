import Foundation

public enum UserCommand: Equatable, Sendable { case startGuard, stopGuard }

/// Kamera sağlık durumu (görüntü hattından).
public enum CameraHealth: Equatable, Sendable { case ok, covered, lost, shifted }

/// Fiziksel müdahale olayları (spec §7.7, T9–T11, T14).
public enum HardwareChange: Equatable, Sendable {
    case display, usb, power
    case lidSensorLost, accelerometerLost
    case filterUnhealthy
}

/// Açılışta geri yüklenen durum (spec §7.10).
public struct PersistedState: Equatable, Sendable, Codable {
    public var bootSession: String
    public var active: Bool          // nöbette ya da kilitliydi
    public var lockout: LockoutPolicy
    public init(bootSession: String, active: Bool, lockout: LockoutPolicy = LockoutPolicy()) {
        self.bootSession = bootSession
        self.active = active
        self.lockout = lockout
    }
}

/// Çekirdeğe gelen tüm olaylar (spec §4.2).
public enum GuardEvent: Sendable {
    case command(UserCommand)
    case prepareResult(ok: Bool, missing: [String])
    case frame(FrameSummary)
    case cameraHealth(CameraHealth)
    case lidAngle(Double)
    case motion(tiltDegrees: Double, jerkG: Double)
    case input
    case hardware(HardwareChange)
    case passcode(String)
    case willSleep
    case didWake
    case launched(bootSession: String, previous: PersistedState?)
}
