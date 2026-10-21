import Testing
import Foundation
@testable import NobetciCore

@Test func settingsDefaultsMatchSpec() {
    let s = GuardSettings()
    #expect(s.returnBehavior == .keepGuarding)   // kullanıcı kararı (2026-10-21): "Buradayım" diyene kadar nöbet sürer
    #expect(s.distance == .medium && s.lid == .medium && s.motion == .medium)
    #expect(s.facelessDetection && s.cameraShiftDetection && s.displayTrigger && s.usbTrigger && s.powerTrigger)
    #expect(!s.strictMode)
    #expect(!s.requireBlink)   // kullanıcı kararı (2026-10-21): tanıyınca aç, göz kırpma isteğe bağlı
    #expect(s.captureSnapshots)                 // sen yokken yaklaşanların fotoğrafı (kullanıcı isteği)
    #expect(s.snapshotRetentionDays == 1)    // kullanıcı kararı (2026-10-21): fotoğraflar 1 gün sonra silinir
    #expect(s.historyRetentionDays == 30 && s.startAtLogin)
}

@Test func decodesOlderSettingsMissingNewKeysWithDefaults() throws {
    // Yeni bir ayar anahtarı eklenince diskteki eski settings.json geçersiz sayılmamalı.
    let json = Data(#"{"strictMode":true}"#.utf8)
    let s = try JSONDecoder().decode(GuardSettings.self, from: json)
    #expect(s.strictMode)
    #expect(!s.requireBlink)
    #expect(s.returnBehavior == .keepGuarding)
}

@Test func settingsRoundTripJSON() throws {
    var s = GuardSettings()
    s.strictMode = true
    s.distance = .near
    let data = try JSONEncoder().encode(s)
    #expect(try JSONDecoder().decode(GuardSettings.self, from: data) == s)
}
