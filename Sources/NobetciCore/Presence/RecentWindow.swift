import Foundation

/// Kayan zaman penceresinde olay sayacı. Kilit açma için spec §5.4.1 "1 sn içinde ≥ 5
/// tanıma" der — ardışık değil; tek bir kaçan kare sayacı sıfırlamaz (cihazda 2–3 sn
/// gecikmenin nedeni ardışık sayımdı).
public struct RecentWindow: Sendable {
    private var times: [TimeInterval] = []
    public init() {}
    public mutating func add(_ t: TimeInterval) { times.append(t) }
    public mutating func count(within window: TimeInterval, now: TimeInterval) -> Int {
        times.removeAll { now - $0 > window }
        return times.count
    }
}
