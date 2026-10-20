import Carbon
import Foundation

// Probe: what does each key produce on a given layout (none/shift/option), and which keys are dead keys?
func layoutData(_ id: String) -> Data? {
    guard let list = TISCreateInputSourceList([kTISPropertyInputSourceID as String: id] as CFDictionary, true)?.takeRetainedValue() as? [TISInputSource],
          let source = list.first,
          let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
    return Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
}

func translate(_ data: Data, _ keyCode: UInt16, _ mods: UInt32, _ dead: inout UInt32) -> String {
    data.withUnsafeBytes { buf in
        let layout = buf.bindMemory(to: UCKeyboardLayout.self).baseAddress!
        var chars = [UniChar](repeating: 0, count: 8)
        var length = 0
        UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), mods, UInt32(LMGetKbdType()), 0, &dead, 8, &length, &chars)
        return String(utf16CodeUnits: chars, count: length)
    }
}

for id in ["com.apple.keylayout.Turkish-QWERTY-PC", "com.apple.keylayout.US"] {
    guard let data = layoutData(id) else { print("\(id): NOT AVAILABLE"); continue }
    print("== \(id) (\(data.count) bytes)")
    var deadKeys: [String] = []
    var optionChars: [String] = []
    for code in UInt16(0)...UInt16(50) {
        for (label, mods) in [("none", UInt32(0)), ("shift", UInt32(2)), ("option", UInt32(8)), ("shift+option", UInt32(10))] {
            var dead: UInt32 = 0
            let out = translate(data, code, mods, &dead)
            if dead != 0 {
                var d1 = dead; let withE = translate(data, 14, 0, &d1)       // keyCode 14 = 'e' position
                var d2 = dead; let withSpace = translate(data, 49, 0, &d2)   // keyCode 49 = space
                deadKeys.append("key \(code) \(label): dead → +e '\(withE)' · +space '\(withSpace)'")
            } else if label == "option", !out.isEmpty {
                optionChars.append("\(code):\(out)")
            }
        }
    }
    var d: UInt32 = 0
    let row = [12, 13, 14, 33, 30, 39, 41, 43, 47, 34].map { code -> String in d = 0; return "\(code)=\(translate(data, UInt16(code), 0, &d))" }
    print("plain keys:", row.joined(separator: " "))
    print("dead keys:"); deadKeys.forEach { print("  ", $0) }
    print("option chars:", optionChars.joined(separator: " "))
}
