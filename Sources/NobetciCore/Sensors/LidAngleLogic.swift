import Foundation

/// Kapak açısı değişimi tetikleyicisi (T4). Taban açısından sapma eşiği aşılıp
/// iki ardışık örnekte sürerse tetikler (tek örnek gürültüsünü eler).
/// Eşik derece değerleri on-device ölçümle (D1) kesinleşir; buradakiler başlangıç.
public struct LidAngleLogic: Sendable {
    private let threshold: Double
    private var baseline: Double?
    private var consecutiveBeyond = 0

    public init(sensitivity: Sensitivity) {
        switch sensitivity {
        case .low: threshold = 5
        case .medium: threshold = 3
        case .high: threshold = 2
        }
    }

    public mutating func setBaseline(_ angle: Double) {
        baseline = angle
        consecutiveBeyond = 0
    }

    public mutating func feed(angle: Double) -> Bool {
        guard let base = baseline else { baseline = angle; return false }
        if abs(angle - base) >= threshold {
            consecutiveBeyond += 1
            return consecutiveBeyond >= 2
        }
        consecutiveBeyond = 0
        return false
    }
}
