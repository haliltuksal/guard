import Foundation
import IOKit
import IOKit.hid

// Probe: can a non-root process read the Apple Silicon SPU accelerometer (usage page 0xFF00, usage 3)?

func hex(_ value: Int32) -> String { "0x" + String(UInt32(bitPattern: value), radix: 16) }

func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
    IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
}

func devices(of manager: IOHIDManager) -> [IOHIDDevice] {
    guard let set = IOHIDManagerCopyDevices(manager) else { return [] }
    let count = CFSetGetCount(set)
    var values = [UnsafeRawPointer?](repeating: nil, count: count)
    CFSetGetValues(set, &values)
    return values.compactMap { $0 }.map { Unmanaged<IOHIDDevice>.fromOpaque($0).takeUnretainedValue() }
}

// 1) Try to wake the sensor through its driver properties.
var iterator: io_iterator_t = 0
IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDriver"), &iterator)
while case let service = IOIteratorNext(iterator), service != 0 {
    defer { IOObjectRelease(service) }
    guard property(service, "PrimaryUsagePage") as? Int == 0xFF00, property(service, "PrimaryUsage") as? Int == 3 else { continue }
    for (key, value) in [("SensorPropertyReportingState", 1), ("SensorPropertyPowerState", 1), ("ReportInterval", 1000)] {
        print("set \(key)=\(value):", hex(IORegistryEntrySetCFProperty(service, key as CFString, value as CFNumber)))
    }
}
IOObjectRelease(iterator)

// 2) Open the HID device and count input reports for 2 seconds.
var reportCount = 0
var lastReport: [UInt8] = []

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: 0xFF00, kIOHIDDeviceUsageKey: 3] as CFDictionary)
print("IOHIDManagerOpen:", hex(IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))))

let found = devices(of: manager)
print("Matching devices:", found.count)
for device in found {
    print("IOHIDDeviceOpen:", hex(IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))))
    let size = 64
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
    IOHIDDeviceRegisterInputReportCallback(device, buffer, size, { _, _, _, _, _, report, length in
        reportCount += 1
        lastReport = Array(UnsafeBufferPointer(start: report, count: length))
    }, nil)
    IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
}
CFRunLoopRunInMode(.defaultMode, 2.0, false)
print("Input reports in 2s:", reportCount)
print("Last report:", lastReport.map { String(format: "%02x", $0) }.joined(separator: " "))
