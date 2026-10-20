import Testing
import Foundation
@testable import NobetciCore

private func session(_ kinds: [GuardLogKind], durationSeconds: TimeInterval = 60) -> SessionRecord {
    let start = Date(timeIntervalSince1970: 1000)
    var s = SessionRecord(started: start)
    for k in kinds { s.events.append(GuardEventRecord(at: start, kind: k)) }
    s.ended = start.addingTimeInterval(durationSeconds)
    return s
}

@Test func quietSessionNeedsNoReport() {
    let s = session([.guardStarted, .ownerLeft, .ownerReturned, .guardEnded])
    #expect(!ReportBuilder.needsReport(s))
}

@Test func lockOrWrongPasscodeNeedsReport() {
    #expect(ReportBuilder.needsReport(session([.guardStarted, .triggered(.strangerFace)])))
    #expect(ReportBuilder.needsReport(session([.guardStarted, .wrongPasscode])))
    #expect(ReportBuilder.needsReport(session([.guardStarted, .endedByRestart])))
}

@Test func summaryShowsCounts() {
    let s = session([.guardStarted, .triggered(.input), .wrongPasscode, .wrongPasscode, .unlockedByPasscode],
                    durationSeconds: 2820) // 47 dk
    let text = ReportBuilder.summary(s)
    #expect(text.contains("47 dk"))
    #expect(text.contains("1 kilit"))
    #expect(text.contains("2 yanlış şifre"))
}

@Test func recordRoundTripsJSON() throws {
    let s = session([.guardStarted, .triggered(.lidAngle), .unlockedByFace])
    let data = try JSONEncoder().encode(s)
    #expect(try JSONDecoder().decode(SessionRecord.self, from: data) == s)
}
