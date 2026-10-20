import Testing
import Carbon
@testable import NobetciSystem

private func layout(_ id: String) -> Data? {
    guard let list = TISCreateInputSourceList([kTISPropertyInputSourceID as String: id] as CFDictionary, true)?
        .takeRetainedValue() as? [TISInputSource], let source = list.first,
          let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
    return Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
}

@Test @MainActor func turkishQComposesAndOptionChars() throws {
    let d = try #require(layout("com.apple.keylayout.Turkish-QWERTY-PC"))
    var t = KeyTranslator(layoutData: d)
    #expect(t.translate(keyCode: 33, modifiers: 0) == .text("ğ"))
    #expect(t.translate(keyCode: 20, modifiers: KeyTranslator.shift) == .pendingDeadKey)  // ^
    #expect(t.translate(keyCode: 14, modifiers: 0) == .text("ê"))                          // ^ + e
    #expect(t.translate(keyCode: 17, modifiers: KeyTranslator.option) == .text("₺"))
    #expect(t.translate(keyCode: 14, modifiers: KeyTranslator.option) == .text("€"))
}

@Test @MainActor func deadKeyThenSpaceYieldsSymbol() throws {
    let d = try #require(layout("com.apple.keylayout.Turkish-QWERTY-PC"))
    var t = KeyTranslator(layoutData: d)
    _ = t.translate(keyCode: 20, modifiers: KeyTranslator.shift)   // ölü tuş ^
    #expect(t.translate(keyCode: 49, modifiers: 0) == .text("^"))  // + boşluk
}
