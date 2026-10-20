import Foundation

/// "Sen yokken olanlar" raporu mantığı (spec §5.6): rapor gerekir mi ve özet metni.
public enum ReportBuilder {
    /// Nöbette kilit, yanlış şifre, müdahale, kamera sorunu ya da yeniden başlama olduysa rapor gösterilir.
    public static func needsReport(_ s: SessionRecord) -> Bool {
        s.events.contains { event in
            switch event.kind {
            case .triggered, .wrongPasscode, .relaunched, .endedByRestart, .cameraIssue, .sensorIssue:
                return true
            default:
                return false
            }
        }
    }

    public static func summary(_ s: SessionRecord) -> String {
        let minutes = Int(((s.duration ?? 0) / 60).rounded())
        let locks = s.events.filter { if case .triggered = $0.kind { return true }; return false }.count
        let wrong = s.events.filter { $0.kind == .wrongPasscode }.count
        let notable = s.events.filter { event in
            switch event.kind {
            case .guardStarted, .guardEnded, .ownerLeft, .ownerReturned: return false
            default: return true
            }
        }.count
        return "\(minutes) dk · \(locks) kilit · \(notable) olay · \(wrong) yanlış şifre"
    }
}
