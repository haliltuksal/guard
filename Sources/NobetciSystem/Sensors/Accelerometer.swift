import Foundation
import IOKit
import IOKit.hid

/// Apple Silicon SPU ivmeölçerini okur (UsagePage 0xFF00, Usage 3). Root gerekmez (V3).
/// Ham eksenlerden eğim (yerçekimi yönünden sapma, derece) ve darbe (jerk, g) türetir;
/// çekirdek bunları T5 için kullanır. Eksen çözümü başlangıçtır (D2 ile kesinleşir).
public final class Accelerometer: @unchecked Sendable {
    private let manager: IOHIDManager
    private let reportSize = 64
    private let buffer: UnsafeMutablePointer<UInt8>
    private let onMotion: @Sendable (_ tiltDegrees: Double, _ jerkG: Double) -> Void

    private var baselineGravity: (x: Double, y: Double, z: Double)?
    private var lastMagnitude: Double = 1.0
    private var devices: [IOHIDDevice] = []
    public private(set) var isAvailable = false

    public init(onMotion: @escaping @Sendable (_ tiltDegrees: Double, _ jerkG: Double) -> Void) {
        self.onMotion = onMotion
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportSize)
    }

    deinit { buffer.deallocate() }

    public func start() {
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: 0xFF00, kIOHIDDeviceUsageKey: 3] as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !set.isEmpty else {
            isAvailable = false
            return
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for dev in set {
            IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDDeviceRegisterInputReportCallback(dev, buffer, reportSize, Self.callback, refcon)
            IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            devices.append(dev)
        }
        isAvailable = true
    }

    public func stop() {
        for dev in devices {
            IOHIDDeviceUnscheduleFromRunLoop(dev, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        devices.removeAll()
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Nöbet başında / sahip karşıdayken çağrılır: mevcut duruşu "sakin" taban sayar.
    public func resetBaseline() { baselineGravity = nil }

    fileprivate func process(report: UnsafePointer<UInt8>, length: Int) {
        guard length >= 18 else { return }
        func axis(_ offset: Int) -> Double {
            let raw = Int32(report[offset]) | Int32(report[offset + 1]) << 8
                | Int32(report[offset + 2]) << 16 | Int32(report[offset + 3]) << 24
            return Double(raw) / 65536.0   // g (D2 provisional)
        }
        let x = axis(6), y = axis(10), z = axis(14)
        let magnitude = (x * x + y * y + z * z).squareRoot()
        let jerk = abs(magnitude - lastMagnitude)
        lastMagnitude = magnitude

        guard let base = baselineGravity else { baselineGravity = (x, y, z); return }
        // İki yerçekimi vektörü arasındaki açı (derece).
        let dot = x * base.x + y * base.y + z * base.z
        let denom = magnitude * (base.x * base.x + base.y * base.y + base.z * base.z).squareRoot()
        let cosAngle = denom > 0 ? max(-1, min(1, dot / denom)) : 1
        let tilt = acos(cosAngle) * 180 / .pi
        onMotion(tilt, jerk)
    }

    private static let callback: IOHIDReportCallback = { context, _, _, _, _, report, length in
        guard let context else { return }
        Unmanaged<Accelerometer>.fromOpaque(context).takeUnretainedValue().process(report: report, length: length)
    }
}
