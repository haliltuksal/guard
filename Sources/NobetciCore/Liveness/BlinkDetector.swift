import Foundation

/// Göz açıklık oranından (EAR) kırpma tespiti. Taban (açık göz) uyarlanır; oran
/// tabanın %60'ının altına inip 50–400 ms içinde geri dönerse bu bir kırpmadır.
/// Canlılık kontrolü (spec §6.7): önceden çekilmiş fotoğrafla kandırmayı zorlaştırır.
public struct BlinkDetector {
    public static let closedRatio: Float = 0.6
    public static let minClosure: TimeInterval = 0.05
    public static let maxClosure: TimeInterval = 0.4

    private var baseline: Float?
    private var closedSince: TimeInterval?
    private var lastBlink: TimeInterval = -.greatestFiniteMagnitude

    public init() {}

    /// EAR örneğini işler; kırpma bu karede tamamlandıysa `true` döner.
    public mutating func feed(ear: Float, now: TimeInterval) -> Bool {
        guard let base = baseline else { baseline = ear; return false }
        let threshold = base * Self.closedRatio
        if ear < threshold {
            if closedSince == nil { closedSince = now }
            return false
        }
        // Göz açık.
        var blinked = false
        if let start = closedSince {
            let duration = now - start
            closedSince = nil
            if duration >= Self.minClosure, duration <= Self.maxClosure {
                lastBlink = now
                blinked = true
            }
        }
        baseline = base * 0.9 + ear * 0.1   // açık gözle tabanı uyarla
        return blinked
    }

    public func blinkedWithin(_ window: TimeInterval, now: TimeInterval) -> Bool {
        now - lastBlink <= window
    }
}
