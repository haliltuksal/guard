import Testing
@testable import NobetciSystem

@Test func wakeKeeperStartsStopsAndIsIdempotent() throws {
    let k = WakeKeeper()
    #expect(!k.isActive)
    try k.start()
    try k.start()          // ikinci çağrı yeni bildirim açmaz
    #expect(k.isActive)
    k.stop()
    #expect(!k.isActive)
}
