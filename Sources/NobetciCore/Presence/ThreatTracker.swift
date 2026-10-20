import Foundation

/// T1 zamanlaması (spec §5.3), iz başına: sahip olmayan bir iz ilk gözleminden itibaren
/// 0,5 sn içinde kabul edilmezse "belirsiz"; 3 ardışık karede T_red altındaysa "yabancı".
/// Kare sayısı yerine ZAMAN: kadraja geri giren sahibin ilk eğik/kısmi kareleri
/// (cihazda 0,1 sn'de "yabancı yüz" sayılmıştı) tanınma şansı bulur; gerçek yabancı
/// (skor çok düşük) yine 3 karede yakalanır.
public struct ThreatTracker: Sendable {
    public static let uncertainGrace: TimeInterval = 0.5
    public static let strangerFrames = 3

    private struct State { var firstSeen: TimeInterval; var belowRejectStreak: Int }
    private var tracks: [Int: State] = [:]

    public init() {}

    /// Sahip olmayan bir iz gözlemi. `belowReject`: skor T_red altında mı.
    public mutating func observe(trackID: Int, belowReject: Bool, now: TimeInterval) -> (uncertain: Bool, stranger: Bool) {
        var s = tracks[trackID] ?? State(firstSeen: now, belowRejectStreak: 0)
        s.belowRejectStreak = belowReject ? s.belowRejectStreak + 1 : 0
        tracks[trackID] = s
        return (uncertain: now - s.firstSeen >= Self.uncertainGrace,
                stranger: s.belowRejectStreak >= Self.strangerFrames)
    }

    /// Sahip olarak kabul edilen iz tehdit değildir; kaydı silinir (saat yeniden başlar).
    public mutating func clear(trackID: Int) { tracks[trackID] = nil }

    /// Kaybolan izler unutulur.
    public mutating func retain(onlyIDs ids: Set<Int>) { tracks = tracks.filter { ids.contains($0.key) } }
}
