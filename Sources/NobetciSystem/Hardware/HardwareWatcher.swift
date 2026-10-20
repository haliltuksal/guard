import Foundation
import IOKit.hid
import IOKit.ps
import CoreGraphics

/// Fiziksel müdahaleyi izler (spec §7.7): ekran yapılandırması (T9), yeni HID/USB
/// cihazı (T10) ve güç kaynağı AC↔pil geçişi (T11). Ana run loop'ta çalışır.
/// Başlangıçta var olan cihazlar yok sayılır; yalnızca sonradan eklenenler tetikler.
public final class HardwareWatcher: @unchecked Sendable {
    private let onChange: @Sendable (HardwareKind) -> Void
    public enum HardwareKind: Sendable { case display, hidOrUSB, power }

    private let hidManager: IOHIDManager
    private var powerSource: CFRunLoopSource?
    private var armed = false
    private var lastOnAC: Bool?

    public init(onChange: @escaping @Sendable (HardwareKind) -> Void) {
        self.onChange = onChange
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    public func start() {
        // Ekran yapılandırması.
        CGDisplayRegisterReconfigurationCallback(Self.displayCallback, Unmanaged.passUnretained(self).toOpaque())

        // Yeni HID cihazları (klavye/fare/USB giriş).
        IOHIDManagerSetDeviceMatching(hidManager, nil)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(hidManager, Self.hidMatchCallback, refcon)
        IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))

        // Güç kaynağı.
        lastOnAC = Self.isOnAC()
        let src = IOPSNotificationCreateRunLoopSource(Self.powerCallback, refcon).takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        powerSource = src

        // İlk cihaz patlamasını yok say; kısa gecikme sonra tetiklemeyi aç.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.armed = true }
    }

    public func stop() {
        CGDisplayRemoveReconfigurationCallback(Self.displayCallback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerUnscheduleFromRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes); self.powerSource = nil }
        armed = false
    }

    fileprivate func displayReconfigured(flags: CGDisplayChangeSummaryFlags) {
        guard armed else { return }
        if flags.contains(.addFlag) || flags.contains(.removeFlag) { onChange(.display) }
    }

    fileprivate func hidAdded() {
        guard armed else { return }
        onChange(.hidOrUSB)
    }

    fileprivate func powerChanged() {
        let nowAC = Self.isOnAC()
        defer { lastOnAC = nowAC }
        guard armed, let was = lastOnAC, was != nowAC else { return }
        onChange(.power)
    }

    static func isOnAC() -> Bool {
        let type = IOPSGetProvidingPowerSourceType(IOPSCopyPowerSourcesInfo().takeRetainedValue()).takeRetainedValue()
        return (type as String) == (kIOPSACPowerValue as String)
    }

    private static let displayCallback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
        guard let userInfo else { return }
        Unmanaged<HardwareWatcher>.fromOpaque(userInfo).takeUnretainedValue().displayReconfigured(flags: flags)
    }
    private static let hidMatchCallback: IOHIDDeviceCallback = { context, _, _, _ in
        guard let context else { return }
        Unmanaged<HardwareWatcher>.fromOpaque(context).takeUnretainedValue().hidAdded()
    }
    private static let powerCallback: IOPowerSourceCallbackType = { context in
        guard let context else { return }
        Unmanaged<HardwareWatcher>.fromOpaque(context).takeUnretainedValue().powerChanged()
    }
}
