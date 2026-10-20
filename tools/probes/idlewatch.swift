import Foundation
import CoreGraphics
import IOKit
// Sample idle timers once per second to see whether something keeps resetting them.
let anyInput = CGEventType(rawValue: ~0)!
func hidIdle() -> Double {
    let s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem")); defer { IOObjectRelease(s) }
    return ((IORegistryEntryCreateCFProperty(s, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.doubleValue ?? -1e9) / 1e9
}
for i in 0..<12 {
    print(String(format: "t=%2ds combinedSession=%7.2f hidSystem=%7.2f HIDIdleTime=%7.2f | key=%7.2f mouseMoved=%7.2f", i,
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput),
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput), hidIdle(),
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown),
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)))
    sleep(1)
}
