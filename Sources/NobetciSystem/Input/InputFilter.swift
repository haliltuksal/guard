import CoreGraphics
import Foundation
import ApplicationServices

/// Nöbet süresince klavye/fare olaylarını, uygulamalara ve sistem kısayollarına
/// dağıtılmadan önce en alt seviyede süzen filtre. Yalnızca ASKIYA ALIR; sisteme ya
/// da başka uygulamaya hiçbir olay ENJEKTE ETMEZ (sahte girdi yok). Kilitliyken
/// tuş karakterleri çözülüp kalkanın kendi şifre alanına iletilir (başka yere değil).
///
/// Kararlar saf `InputPolicyEngine`'e devredilir. Filtre ayrı bir iş parçacığında ve
/// kendi run loop'unda çalışır; macOS tap'i devre dışı bırakırsa anında yeniden açar.
public final class InputFilter: @unchecked Sendable {
    private let lock = NSLock()           // engine + policy
    private let stateLock = NSLock()      // tap/health durumu (tap thread + health kuyruğu + main)
    private var engine: InputPolicyEngine
    private var currentPolicy: InputPolicy = .passThrough

    private var taps: [CFMachPort] = []
    private var sources: [CFRunLoopSource] = []
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var healthTimer: DispatchSourceTimer?
    private var reenableFailures = 0
    private var _isHealthy = false
    public var isHealthy: Bool { stateLock.withLock { _isHealthy } }

    private let onLockRequested: @Sendable () -> Void
    private let onPasscode: @Sendable (InputDecision) -> Void
    private let onHealthChange: @Sendable (Bool) -> Void

    public init(onLockRequested: @escaping @Sendable () -> Void,
                onPasscode: @escaping @Sendable (InputDecision) -> Void,
                onHealthChange: @escaping @Sendable (Bool) -> Void) {
        self.onLockRequested = onLockRequested
        self.onPasscode = onPasscode
        self.onHealthChange = onHealthChange
        self.engine = InputPolicyEngine(translator: KeyTranslator.currentLayoutData().map { KeyTranslator(layoutData: $0) })
    }

    public static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        // kAXTrustedCheckOptionPrompt Swift 6'da concurrency-safe değil; belgelenmiş anahtar dizesini kullan.
        let key = "AXTrustedCheckOptionPrompt" as CFString
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    public var policy: InputPolicy { lock.withLock { currentPolicy } }

    public func setPolicy(_ newPolicy: InputPolicy) { lock.withLock { currentPolicy = newPolicy } }

    public func install() throws {
        guard stateLock.withLock({ taps.isEmpty }) else { return }
        guard Self.hasAccessibilityPermission(prompt: false) else { throw InputFilterError.accessibilityDenied }
        // Etkin klavye düzenini her nöbet başında tazele (spec §7.3): düzen değiştiyse şifre karakterleri doğru çözülsün.
        lock.withLock {
            engine = InputPolicyEngine(translator: KeyTranslator.currentLayoutData().map { KeyTranslator(layoutData: $0) })
        }

        let mask: CGEventMask = ~0   // tüm olay türleri
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var created: [CFMachPort] = []
        for location in [CGEventTapLocation.cghidEventTap, .cgSessionEventTap] {
            guard let tap = CGEvent.tapCreate(tap: location, place: .headInsertEventTap, options: .defaultTap,
                                              eventsOfInterest: mask, callback: Self.callback, userInfo: refcon) else {
                created.forEach { CGEvent.tapEnable(tap: $0, enable: false) }
                throw InputFilterError.tapCreationFailed
            }
            created.append(tap)
        }
        stateLock.withLock { taps = created }

        let started = Thread { [weak self] in
            guard let self else { return }
            let taps = self.stateLock.withLock { self.taps }
            var sources: [CFRunLoopSource] = []
            for tap in taps {
                guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { continue }
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
                sources.append(source)
            }
            self.stateLock.withLock { self.sources = sources; self.runLoop = CFRunLoopGetCurrent() }
            CFRunLoopRun()
        }
        started.name = "com.halil.nobetci.inputfilter"
        stateLock.withLock { thread = started; _isHealthy = true; reenableFailures = 0 }
        started.start()
        startHealthTimer()
    }

    public func uninstall() {
        healthTimer?.cancel(); healthTimer = nil
        let (taps, sources, runLoop) = stateLock.withLock { (self.taps, self.sources, self.runLoop) }
        if let runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                for source in sources { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
            CFRunLoopWakeUp(runLoop)
        }
        for tap in taps { CGEvent.tapEnable(tap: tap, enable: false) }
        stateLock.withLock {
            self.taps.removeAll(); self.sources.removeAll(); self.runLoop = nil; self.thread = nil; _isHealthy = false
        }
    }

    // MARK: Olay işleme (tap iş parçacığında)

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reenableAll()
            return Unmanaged.passUnretained(event)
        }
        let keyCode: UInt16? = (type == .keyDown || type == .keyUp)
            ? UInt16(event.getIntegerValueField(.keyboardEventKeycode)) : nil
        let decision: InputDecision = lock.withLock { engine.decide(policy: currentPolicy, type: type, keyCode: keyCode, flags: event.flags) }

        switch decision {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .swallow:
            return nil
        case .swallowAndLock:
            lock.withLock { currentPolicy = .blockAll }   // kilitle-öncesi yarışı kapat
            onLockRequested()
            return nil
        case .passcodeText, .passcodeReturn, .passcodeDelete, .passcodeEscape, .passcodePending:
            onPasscode(decision)
            return nil
        }
    }

    private func reenableAll() {
        let taps = stateLock.withLock { self.taps }
        var ok = true
        for tap in taps {
            CGEvent.tapEnable(tap: tap, enable: true)
            if !CGEvent.tapIsEnabled(tap: tap) { ok = false }
        }
        if ok { stateLock.withLock { reenableFailures = 0 } } else { reportUnhealthy() }
    }

    private func startHealthTimer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.halil.nobetci.inputfilter.health"))
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in self?.checkHealth() }
        timer.resume()
        healthTimer = timer
    }

    private func checkHealth() {
        let taps = stateLock.withLock { self.taps }
        let allEnabled = !taps.isEmpty && taps.allSatisfy { CGEvent.tapIsEnabled(tap: $0) }
        if allEnabled { stateLock.withLock { reenableFailures = 0 }; return }
        reenableAll()
        if taps.contains(where: { !CGEvent.tapIsEnabled(tap: $0) }) { reportUnhealthy() }
    }

    private func reportUnhealthy() {
        let fire = stateLock.withLock { () -> Bool in
            reenableFailures += 1
            guard reenableFailures >= 3, _isHealthy else { return false }
            _isHealthy = false
            return true
        }
        if fire { onHealthChange(false) }   // çekirdek bunu T14 sayar
    }

    // CGEventTap C geri çağırımı; self refcon üzerinden geri alınır.
    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let filter = Unmanaged<InputFilter>.fromOpaque(refcon).takeUnretainedValue()
        return filter.handle(type: type, event: event)
    }
}

public enum InputFilterError: Error, Sendable { case accessibilityDenied, tapCreationFailed }
