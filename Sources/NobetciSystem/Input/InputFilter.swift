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
    private let lock = NSLock()
    private var engine: InputPolicyEngine
    private var currentPolicy: InputPolicy = .passThrough

    private var taps: [CFMachPort] = []
    private var sources: [CFRunLoopSource] = []
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var healthTimer: DispatchSourceTimer?
    private var reenableFailures = 0
    public private(set) var isHealthy = false

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
        guard taps.isEmpty else { return }
        guard Self.hasAccessibilityPermission(prompt: false) else { throw InputFilterError.accessibilityDenied }

        let mask: CGEventMask = ~0   // tüm olay türleri
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for location in [CGEventTapLocation.cghidEventTap, .cgSessionEventTap] {
            guard let tap = CGEvent.tapCreate(tap: location, place: .headInsertEventTap, options: .defaultTap,
                                              eventsOfInterest: mask, callback: Self.callback, userInfo: refcon) else {
                uninstall()
                throw InputFilterError.tapCreationFailed
            }
            taps.append(tap)
        }

        let started = Thread { [weak self] in
            guard let self else { return }
            self.runLoop = CFRunLoopGetCurrent()
            for tap in self.taps {
                guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { continue }
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
                self.sources.append(source)
            }
            CFRunLoopRun()
        }
        started.name = "com.halil.nobetci.inputfilter"
        thread = started
        started.start()

        isHealthy = true
        startHealthTimer()
    }

    public func uninstall() {
        healthTimer?.cancel(); healthTimer = nil
        if let runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [self] in
                for source in sources { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
            CFRunLoopWakeUp(runLoop)
        }
        for tap in taps { CGEvent.tapEnable(tap: tap, enable: false) }
        taps.removeAll(); sources.removeAll(); runLoop = nil; thread = nil
        isHealthy = false
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
        var ok = true
        for tap in taps {
            CGEvent.tapEnable(tap: tap, enable: true)
            if !CGEvent.tapIsEnabled(tap: tap) { ok = false }
        }
        if ok { reenableFailures = 0 } else { reportUnhealthy() }
    }

    private func startHealthTimer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.halil.nobetci.inputfilter.health"))
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in self?.checkHealth() }
        timer.resume()
        healthTimer = timer
    }

    private func checkHealth() {
        let allEnabled = !taps.isEmpty && taps.allSatisfy { CGEvent.tapIsEnabled(tap: $0) }
        if allEnabled { reenableFailures = 0; return }
        reenableAll()
        let stillBad = taps.contains { !CGEvent.tapIsEnabled(tap: $0) }
        if stillBad { reportUnhealthy() }
    }

    private func reportUnhealthy() {
        reenableFailures += 1
        if reenableFailures >= 3, isHealthy {
            isHealthy = false
            onHealthChange(false)   // çekirdek bunu T14 sayar
        }
    }

    // CGEventTap C geri çağırımı; self refcon üzerinden geri alınır.
    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let filter = Unmanaged<InputFilter>.fromOpaque(refcon).takeUnretainedValue()
        return filter.handle(type: type, event: event)
    }
}

public enum InputFilterError: Error, Sendable { case accessibilityDenied, tapCreationFailed }
