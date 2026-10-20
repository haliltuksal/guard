import AppKit

/// Uyku/uyanma bildirimleri (spec §7.8). Uykuda ne olduğu bilinemez → uyanınca Kilitli.
public final class SleepObserver: @unchecked Sendable {
    private let onWillSleep: @Sendable () -> Void
    private let onDidWake: @Sendable () -> Void
    private var tokens: [NSObjectProtocol] = []

    public init(onWillSleep: @escaping @Sendable () -> Void, onDidWake: @escaping @Sendable () -> Void) {
        self.onWillSleep = onWillSleep
        self.onDidWake = onDidWake
    }

    public func start() {
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [onWillSleep] _ in onWillSleep() })
        tokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [onDidWake] _ in onDidWake() })
    }

    public func stop() {
        let center = NSWorkspace.shared.notificationCenter
        tokens.forEach { center.removeObserver($0) }
        tokens.removeAll()
    }
}
