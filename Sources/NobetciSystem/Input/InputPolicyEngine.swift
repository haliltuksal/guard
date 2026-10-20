import CoreGraphics

/// Girdi filtresinin o anki davranışı. Yalnızca nöbet süresince kuruludur.
public enum InputPolicy: Sendable {
    case passThrough       // Nöbette · sahip var — her şey geçer
    case lockOnFirstInput  // Nöbette · sahip yok — ilk girdi yutulur ve kilitler
    case blockAll          // Kilitli — her şey yutulur; tuşlar kalkandaki şifre alanına
}

public enum InputDecision: Equatable, Sendable {
    case pass
    case swallow
    case swallowAndLock
    case passcodeText(String)
    case passcodeReturn
    case passcodeDelete
    case passcodeEscape
    case passcodePending
}

/// Saf karar mantığı: (politika, olay) → karar. Girdi filtresinin tap gövdesi
/// bu kararı uygular; mantık tekrarı olmaz ve burası donanımsız test edilir.
public struct InputPolicyEngine {
    private var translator: KeyTranslator?
    public init(translator: KeyTranslator?) { self.translator = translator }

    public mutating func decide(policy: InputPolicy, type: CGEventType,
                                keyCode: UInt16?, flags: CGEventFlags) -> InputDecision {
        switch policy {
        case .passThrough:
            return .pass
        case .lockOnFirstInput:
            return .swallowAndLock
        case .blockAll:
            guard type == .keyDown, let keyCode else { return .swallow }
            if flags.contains(.maskCommand) || flags.contains(.maskControl) { return .swallow }
            switch keyCode {
            case 36, 76: return .passcodeReturn   // Return / Enter
            case 51, 117: return .passcodeDelete  // Delete / Forward Delete
            case 53: return .passcodeEscape       // Esc
            default: break
            }
            guard var t = translator else { return .swallow }
            let out = t.translate(keyCode: keyCode, modifiers: KeyTranslator.carbonModifiers(from: flags))
            translator = t
            switch out {
            case .text(let s): return .passcodeText(s)
            case .pendingDeadKey: return .passcodePending
            case .none: return .swallow
            }
        }
    }
}
