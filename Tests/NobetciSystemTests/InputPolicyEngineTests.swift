import Testing
import CoreGraphics
@testable import NobetciSystem

@Test @MainActor func policyDecisions() throws {
    var e = InputPolicyEngine(translator: KeyTranslator.currentLayoutData().map { KeyTranslator(layoutData: $0) })
    #expect(e.decide(policy: .passThrough, type: .keyDown, keyCode: 0, flags: []) == .pass)
    #expect(e.decide(policy: .lockOnFirstInput, type: .mouseMoved, keyCode: nil, flags: []) == .swallowAndLock)
    #expect(e.decide(policy: .blockAll, type: .leftMouseDown, keyCode: nil, flags: []) == .swallow)
    #expect(e.decide(policy: .blockAll, type: .keyDown, keyCode: 36, flags: []) == .passcodeReturn)
    #expect(e.decide(policy: .blockAll, type: .keyDown, keyCode: 51, flags: []) == .passcodeDelete)
    #expect(e.decide(policy: .blockAll, type: .keyDown, keyCode: 53, flags: []) == .passcodeEscape)
    #expect(e.decide(policy: .blockAll, type: .keyDown, keyCode: 48, flags: .maskCommand) == .swallow) // Cmd+Tab
    if case .passcodeText = e.decide(policy: .blockAll, type: .keyDown, keyCode: 33, flags: []) {} else {
        Issue.record("harf bekleniyordu")
    }
}
