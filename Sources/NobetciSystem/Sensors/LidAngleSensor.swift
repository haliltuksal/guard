import Foundation
import IOKit
import IOKit.hid

/// MacBook menteşe açısını okur (Apple SPU HID: VID 0x05AC, PID 0x8104,
/// UsagePage 0x20, Usage 0x8A). Root gerekmez (V2). 20 Hz feature report polling.
/// Sensör yoksa `isAvailable == false` (çekirdek T8 kamera yedeğine geçer).
public final class LidAngleSensor: @unchecked Sendable {
    private let manager: IOHIDManager
    private var device: IOHIDDevice?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.halil.nobetci.lid")
    private let onAngle: @Sendable (Double) -> Void

    public private(set) var isAvailable = false

    public init(onAngle: @escaping @Sendable (Double) -> Void) {
        self.onAngle = onAngle
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    public func start() {
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: 0x05AC, kIOHIDProductIDKey: 0x8104,
            kIOHIDDeviceUsagePageKey: 0x0020, kIOHIDDeviceUsageKey: 0x008A,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let dev = set.first else {
            isAvailable = false
            return
        }
        device = dev
        IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        isAvailable = true

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(50))   // 20 Hz
        t.setEventHandler { [weak self] in self?.read() }
        t.resume()
        timer = t
    }

    public func stop() {
        timer?.cancel(); timer = nil
        if let device { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func read() {
        guard let device else { return }
        var report = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(report.count)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
        guard result == kIOReturnSuccess, length >= 3 else { return }
        let angle = Double((UInt16(report[2]) << 8) | UInt16(report[1]))
        onAngle(angle)
    }
}
