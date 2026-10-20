import Foundation

/// Zaman kaynağı soyutlaması. `now()` bekleme sürelerini ölçmek için uyku dahil
/// ilerleyen monoton saniye; `wallNow()` rapor zaman damgaları için duvar saati.
/// Tüm Core bileşenleri saati enjekte alır, böylece zamana bağlı mantık test edilebilir.
public protocol Clock: Sendable {
    func now() -> TimeInterval
    func wallNow() -> Date
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> TimeInterval {
        var info = mach_timebase_info()
        mach_timebase_info(&info)
        let ns = mach_continuous_time() &* UInt64(info.numer) / UInt64(info.denom)
        return Double(ns) / 1e9
    }
    public func wallNow() -> Date { Date() }
}

public final class ManualClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var mono: TimeInterval
    private var wall: Date
    public init(now: TimeInterval = 0, wall: Date = Date(timeIntervalSince1970: 0)) {
        mono = now
        self.wall = wall
    }
    public func now() -> TimeInterval { lock.withLock { mono } }
    public func wallNow() -> Date { lock.withLock { wall } }
    public func advance(by s: TimeInterval) { lock.withLock { mono += s; wall.addTimeInterval(s) } }
    public func setWall(_ d: Date) { lock.withLock { wall = d } }
}
