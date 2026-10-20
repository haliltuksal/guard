import Testing
import Foundation
@testable import NobetciCore

@Test func settingsDefaultsMatchSpec() {
    let s = GuardSettings()
    #expect(s.returnBehavior == .keepGuarding)   // kullanıcı kararı (2026-10-21): "Buradayım" diyene kadar nöbet sürer
    #expect(s.distance == .medium && s.lid == .medium && s.motion == .medium)
    #expect(s.facelessDetection && s.cameraShiftDetection && s.displayTrigger && s.usbTrigger && s.powerTrigger)
    #expect(!s.strictMode)
    #expect(s.historyRetentionDays == 30 && s.startAtLogin)
}

@Test func settingsRoundTripJSON() throws {
    var s = GuardSettings()
    s.strictMode = true
    s.distance = .near
    let data = try JSONEncoder().encode(s)
    #expect(try JSONDecoder().decode(GuardSettings.self, from: data) == s)
}
