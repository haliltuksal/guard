import Carbon
import CoreGraphics
import Foundation

public enum KeyOutput: Equatable, Sendable {
    case text(String)
    case pendingDeadKey
    case none
}

/// Bir tuş kodu + değiştiricileri, etkin klavye düzenine göre karaktere çevirir.
/// Ölü tuş durumunu (`deadKeyState`) yapı içinde taşır; böylece Türkçe Q'daki
/// `^ ~ ¨ ´ ` gibi aksan dizileri ve Option karakterleri doğru üretilir (V15).
public struct KeyTranslator {
    public static let shift: UInt32 = UInt32(shiftKey >> 8)      // 2
    public static let option: UInt32 = UInt32(optionKey >> 8)    // 8
    public static let control: UInt32 = UInt32(controlKey >> 8)  // 4
    public static let command: UInt32 = UInt32(cmdKey >> 8)      // 1

    private let layoutData: Data
    private let keyboardType: UInt32
    private var deadKeyState: UInt32 = 0

    public init(layoutData: Data, keyboardType: UInt32 = UInt32(LMGetKbdType())) {
        self.layoutData = layoutData
        self.keyboardType = keyboardType
    }

    public static func currentLayoutData() -> Data? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        return Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
    }

    /// `modifiers`: Carbon biçimi (shift=2, control=4, option=8, command=1).
    public mutating func translate(keyCode: UInt16, modifiers: UInt32) -> KeyOutput {
        var chars = [UniChar](repeating: 0, count: 8)
        var length = 0
        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), modifiers, keyboardType, 0,
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr else { deadKeyState = 0; return .none }
        // UCKeyTranslate, aksan dizisini tamamlayınca karakteri üretir (length>0) ama
        // deadKeyState'i sıfırlamaz (tamamlanmış terminatör değeri bırakır, ör. 65536).
        // Karakter üretildiyse metni döndür ve bir sonraki tuşu bozmaması için durumu sıfırla.
        if length > 0 {
            deadKeyState = 0
            let text = String(utf16CodeUnits: chars, count: length)
            // Kontrol karakterleri (Return, Delete, Esc, Tab) metin sayılmaz; filtre ayrı işler.
            if text.unicodeScalars.allSatisfy({ $0.value < 0x20 || $0.value == 0x7F }) { return .none }
            return .text(text)
        }
        if deadKeyState != 0 { return .pendingDeadKey }
        return .none
    }

    public static func carbonModifiers(from flags: CGEventFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.maskShift) { m |= shift }
        if flags.contains(.maskAlternate) { m |= option }
        if flags.contains(.maskControl) { m |= control }
        if flags.contains(.maskCommand) { m |= command }
        return m
    }
}
