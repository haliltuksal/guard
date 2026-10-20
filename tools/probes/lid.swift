import Foundation
import IOKit
import IOKit.hid

// Probe: read the MacBook lid (hinge) angle from the SPU HID sensor
// (Apple VID 0x05AC, PID 0x8104, usage page 0x20 Sensor, usage 0x8A Orientation) as a non-root user.

func hex(_ value: Int32) -> String { "0x" + String(UInt32(bitPattern: value), radix: 16) }

func devices(of manager: IOHIDManager) -> [IOHIDDevice] {
    guard let set = IOHIDManagerCopyDevices(manager) else { return [] }
    let count = CFSetGetCount(set)
    var values = [UnsafeRawPointer?](repeating: nil, count: count)
    CFSetGetValues(set, &values)
    return values.compactMap { $0 }.map { Unmanaged<IOHIDDevice>.fromOpaque($0).takeUnretainedValue() }
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matching: [String: Any] = [
    kIOHIDVendorIDKey: 0x05AC,
    kIOHIDProductIDKey: 0x8104,
    kIOHIDDeviceUsagePageKey: 0x0020,
    kIOHIDDeviceUsageKey: 0x008A,
]
IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
print("IOHIDManagerOpen:", hex(IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))))

let found = devices(of: manager)
print("Matching devices:", found.count)

for device in found {
    print("IOHIDDeviceOpen:", hex(IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))))
    for i in 0..<5 {
        var report = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(report.count)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
        let bytes = report.prefix(max(length, 0)).map { String(format: "%02x", $0) }.joined(separator: " ")
        if result == kIOReturnSuccess, length >= 3 {
            let angle = (UInt16(report[2]) << 8) | UInt16(report[1])
            print("sample \(i): result=\(hex(result)) len=\(length) bytes=[\(bytes)] angle=\(angle)")
        } else {
            print("sample \(i): result=\(hex(result)) len=\(length) bytes=[\(bytes)]")
        }
        usleep(200_000)
    }
    IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
}
