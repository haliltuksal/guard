import Foundation
import CoreGraphics
import IOKit
import IOKit.pwr_mgt
import ApplicationServices

// Probe: which "stay active" mechanisms reset the idle timers that apps read?
// Each test waits for natural idle >= 5 s, applies one mechanism, then re-reads the timers.

let anyInput = CGEventType(rawValue: ~0)!

func idle(_ state: CGEventSourceStateID) -> Double { CGEventSource.secondsSinceLastEventType(state, eventType: anyInput) }

func hidIdle() -> Double {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
    defer { IOObjectRelease(service) }
    guard let value = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue() as? NSNumber else { return -1 }
    return value.doubleValue / 1_000_000_000
}

func report(_ label: String) {
    let padded = label.padding(toLength: 46, withPad: " ", startingAt: 0)
    print(padded + String(format: "combinedSession: %6.2fs  hidSystem: %6.2fs  HIDIdleTime: %6.2fs",
                          idle(.combinedSessionState), idle(.hidSystemState), hidIdle()))
}

func waitForIdle(atLeast seconds: Double) -> Bool {
    let deadline = Date().addingTimeInterval(90)
    while Date() < deadline {
        if idle(.combinedSessionState) >= seconds, hidIdle() >= seconds { return true }
        usleep(250_000)
    }
    return false
}

print("AXIsProcessTrusted (Accessibility):", AXIsProcessTrusted())

guard waitForIdle(atLeast: 5) else { print("User kept interacting; test A inconclusive"); exit(2) }
report("A. before IOPMAssertionDeclareUserActivity")
var assertionID: IOPMAssertionID = 0
let result = IOPMAssertionDeclareUserActivity("probe" as CFString, kIOPMUserActiveLocal, &assertionID)
print("   IOPMAssertionDeclareUserActivity ->", "0x" + String(UInt32(bitPattern: result), radix: 16))
usleep(500_000)
report("A. after  IOPMAssertionDeclareUserActivity")
IOPMAssertionRelease(assertionID)

let location = CGEvent(source: nil)!.location

guard waitForIdle(atLeast: 5) else { print("User kept interacting; test B inconclusive"); exit(2) }
report("B. before mouseMoved posted at HID tap")
CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved,
        mouseCursorPosition: location, mouseButton: .left)!.post(tap: .cghidEventTap)
usleep(500_000)
report("B. after  mouseMoved posted at HID tap")

guard waitForIdle(atLeast: 5) else { print("User kept interacting; test C inconclusive"); exit(2) }
report("C. before mouseMoved posted at session tap")
CGEvent(mouseEventSource: CGEventSource(stateID: .combinedSessionState), mouseType: .mouseMoved,
        mouseCursorPosition: location, mouseButton: .left)!.post(tap: .cgSessionEventTap)
usleep(500_000)
report("C. after  mouseMoved posted at session tap")
