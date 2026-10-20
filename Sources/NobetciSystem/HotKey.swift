import Carbon
import Foundation
import NobetciCore

/// Global klavye kısayolu (varsayılan ⌃⌥⌘L). Carbon `RegisterEventHotKey` izin
/// gerektirmez. Basıldığında `onFire` çağrılır (ana iş parçacığında).
public final class HotKey: @unchecked Sendable {
    private let onFire: @Sendable () -> Void
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static let signature = OSType(0x4E4F4245)   // 'NOBE'

    public init(onFire: @escaping @Sendable () -> Void) { self.onFire = onFire }

    public func register(_ spec: HotKeySpec) throws {
        unregister()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), Self.handlerCallback, 1, &eventType, refcon, &handler)

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(UInt32(spec.keyCode), spec.carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { throw HotKeyError.registrationFailed(status) }
    }

    public func unregister() {
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }

    deinit { unregister() }

    private static let handlerCallback: EventHandlerUPP = { _, _, userData in
        guard let userData else { return noErr }
        Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().onFire()
        return noErr
    }
}

public enum HotKeyError: Error, Sendable { case registrationFailed(OSStatus) }
