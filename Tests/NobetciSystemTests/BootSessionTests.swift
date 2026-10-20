import Testing
@testable import NobetciSystem

@Test func bootSessionIsStableNonEmpty() {
    let a = BootSession.current()
    #expect(!a.isEmpty)
    #expect(a == BootSession.current())   // aynı açılış oturumunda değişmez
}
