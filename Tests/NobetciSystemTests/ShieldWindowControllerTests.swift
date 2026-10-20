import Testing
import AppKit
@testable import NobetciSystem

@MainActor
final class FakeScreens: ScreenProvider {
    var frames: [CGRect]
    var onChange: (() -> Void)?
    init(_ f: [CGRect]) { frames = f }
    func change(to f: [CGRect]) { frames = f; onChange?() }
}

@Test @MainActor func windowsTrackScreenSet() {
    let s = FakeScreens([CGRect(x: 0, y: 0, width: 1512, height: 982)])
    let c = ShieldWindowController(screens: s) { NSView() }
    c.show()
    #expect(c.windowFrames.count == 1)
    s.change(to: [CGRect(x: 0, y: 0, width: 1512, height: 982),
                  CGRect(x: 1512, y: 0, width: 2560, height: 1440)])
    #expect(c.windowFrames.count == 2)
    s.change(to: [CGRect(x: 0, y: 0, width: 1512, height: 982)])
    #expect(c.windowFrames.count == 1)
    c.hide(animated: false)
    #expect(c.windowFrames.isEmpty)
}

@Test @MainActor func shieldSitsAtShieldingLevel() {
    let c = ShieldWindowController(screens: FakeScreens([CGRect(x: 0, y: 0, width: 800, height: 600)])) { NSView() }
    c.show()
    #expect(c.debugWindowLevel == Int(CGShieldingWindowLevel()))
    c.hide(animated: false)
}
