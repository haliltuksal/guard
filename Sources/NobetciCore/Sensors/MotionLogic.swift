import Foundation

/// Mac'in kaldırılması/oynatılması tetikleyicisi (T5). Yerçekimi yönünden eğim
/// sapması ya da yüksek frekanslı enerji (darbe) eşiği aşılırsa tetikler.
/// Eşikler on-device kayıtlarla (D2) kesinleşir; buradakiler başlangıç.
public struct MotionLogic: Sendable {
    private let tiltThreshold: Double   // derece
    private let jerkThreshold: Double   // g

    public init(sensitivity: Sensitivity) {
        switch sensitivity {
        case .low: tiltThreshold = 12; jerkThreshold = 0.5
        case .medium: tiltThreshold = 8; jerkThreshold = 0.3
        case .high: tiltThreshold = 5; jerkThreshold = 0.2
        }
    }

    public func triggered(tiltDegrees: Double, jerkG: Double) -> Bool {
        tiltDegrees >= tiltThreshold || jerkG >= jerkThreshold
    }
}
