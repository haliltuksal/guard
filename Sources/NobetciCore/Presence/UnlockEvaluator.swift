import Foundation

/// Sıkı modda istenen baş hareketi yönü.
public enum Turn: Equatable, Sendable {
    case left, right, up
}

public enum UnlockDecision: Equatable, Sendable {
    case unlock
    case needBlink
    case bystander
    case lowQuality
    case keepWaiting
    case needGesture(Turn)
}

/// Yüzle kilit açma kararı (spec §5.4). Dört koşul birlikte sağlanmalı; sıkı modda
/// ayrıca rastgele bir baş hareketi istenir.
public struct UnlockEvaluator: Sendable {
    public static let framesRequired = 5
    public static let blinkWindow: TimeInterval = 3.0

    public init() {}

    public func evaluate(frame: FrameSummary, settings: GuardSettings,
                         requestedTurn: Turn, now: TimeInterval) -> UnlockDecision {
        // 1) Son 1 sn içinde ≥5 tanıma (kayan pencere). Bu karede eşleşme şart değil:
        //    tek kaçan kare kilit açmayı geciktirmemeli.
        guard let track = frame.ownerTrack, track.recognizedFrameCount >= Self.framesRequired else {
            return .keepWaiting
        }
        // 3) Karede başka bir yüz ya da gövde olmamalı → yanında biri varsa şifre gerekir.
        if frame.strangerFacePresent || frame.uncertainFacePresent || frame.bodyPresentBeyondThreshold {
            return .bystander
        }
        // 4) Yüz kalitesi/boyutu yeterli olmalı.
        if !frame.ownerQualityOK { return .lowQuality }
        // 2) Canlılık (isteğe bağlı; kullanıcı kararı: varsayılan kapalı — tanıyınca aç).
        if settings.requireBlink {
            guard let since = frame.blinkObservedWithin, since <= Self.blinkWindow else {
                return .needBlink
            }
        }
        // Sıkı mod: istenen baş hareketi.
        if settings.strictMode, !frame.strictGestureSatisfied {
            return .needGesture(requestedTurn)
        }
        return .unlock
    }
}
