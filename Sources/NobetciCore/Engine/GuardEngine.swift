import Foundation

/// Koruma durum makinesi (spec §5). Olayları sırayla işler, durumu ilerletir ve
/// yan etki listesi döndürür. Donanıma dokunmaz; ManualClock ile tam deterministik.
/// Kararların hepsi burada; fail-closed: emin olunamayan her durum → Kilitli.
public struct GuardEngine: Sendable {
    private let clock: Clock
    private let verifyPasscode: @Sendable (String) -> Bool

    public private(set) var settings: GuardSettings
    public private(set) var state: GuardState = .off

    private var ownerPresence = OwnerPresence()
    private let unlockEvaluator = UnlockEvaluator()
    private var lockout = LockoutPolicy()
    private var lid: LidAngleLogic
    private var motion: MotionLogic
    private var session: SessionRecord?
    private var bootSession = ""
    private var requestedTurn: Turn = .left
    private var strangerStreak = 0   // T1 debounce: ardışık yabancı/belirsiz kare sayısı
    private static let strangerFramesToLock = 2   // pipeline iz başına zamanlıyor; burası yalnızca tek-kare arıza koruması
    private var lastBlinkPromptAt: TimeInterval = -.greatestFiniteMagnitude
    private static let promptStickiness: TimeInterval = 1.0   // "göz kırp" istemi tek kaçan karede düşmesin

    public init(clock: Clock,
                settings: GuardSettings = GuardSettings(),
                verifyPasscode: @escaping @Sendable (String) -> Bool = { _ in false }) {
        self.clock = clock
        self.settings = settings
        self.verifyPasscode = verifyPasscode
        self.lid = LidAngleLogic(sensitivity: settings.lid)
        self.motion = MotionLogic(sensitivity: settings.motion)
    }

    public mutating func handle(_ event: GuardEvent) -> [GuardEffect] {
        switch event {
        case .command(let c): return handleCommand(c)
        case .prepareResult(let ok, let missing): return handlePrepare(ok: ok, missing: missing)
        case .frame(let f): return handleFrame(f)
        case .cameraHealth(let h): return handleCamera(h)
        case .lidAngle(let a): return handleLid(a)
        case .motion(let t, let j): return handleMotion(tilt: t, jerk: j)
        case .input: return handleInput()
        case .hardware(let c): return handleHardware(c)
        case .passcode(let p): return handlePasscode(p)
        case .willSleep: return handleWillSleep()
        case .didWake: return handleDidWake()
        case .launched(let boot, let prev): return handleLaunched(boot: boot, previous: prev)
        }
    }

    // MARK: Komutlar

    private mutating func handleCommand(_ c: UserCommand) -> [GuardEffect] {
        switch c {
        case .startGuard:
            guard case .off = state else { return [] }
            state = .preparing
            return []
        case .stopGuard:
            guard case .guarding = state else { return [] }   // kilitliyken komutla durdurulamaz
            return endGuard(reason: .guardEnded)
        }
    }

    private mutating func handlePrepare(ok: Bool, missing: [String]) -> [GuardEffect] {
        guard case .preparing = state else { return [] }
        guard ok else { state = .off; return [.notify(.prepareFailed(missing))] }
        session = SessionRecord(started: clock.wallNow())
        ownerPresence = OwnerPresence()
        ownerPresence.seedPresent(now: clock.now())
        state = .guarding(.present)
        var fx: [GuardEffect] = [.startSensors, .wakeKeep(true), .setInputPolicy(.passThrough)]
        fx.append(log(.guardStarted))
        fx.append(.notify(.guardStarted))
        fx.append(persist(active: true))
        return fx
    }

    // MARK: Kareler

    private mutating func handleFrame(_ f: FrameSummary) -> [GuardEffect] {
        switch state {
        case .guarding(let presence):
            // Yabancı/belirsiz yüz her alt durumda kilitler (T1) — ama tek kare değil:
            // 3 ardışık tehdit karesi gerekir (sahibin kafasını çevirdiği tek kötü kareyi eler).
            if f.strangerFacePresent || f.uncertainFacePresent {
                strangerStreak += 1
                if strangerStreak >= Self.strangerFramesToLock {
                    return lock(.strangerFace, now: f.timestamp, bystander: true)
                }
            } else {
                strangerStreak = 0
            }
            let ownerThisFrame = f.ownerTrack?.present == true
            let match: MatchResult = ownerThisFrame ? .owner : .uncertain
            let newPresence = ownerPresence.update(match: match, trackAlive: f.ownerTrack != nil, now: f.timestamp)

            if presence == .absent {
                // T2: sahne ≥ 3 sn boşken beliren yüzsüz gövde (Review Focus 1).
                if settings.facelessDetection, f.bodyPresentBeyondThreshold, !ownerThisFrame, f.sceneEmptyFor >= 3 {
                    return lock(.facelessPerson, now: f.timestamp, bystander: true)
                }
                if newPresence == .present { return ownerReturnedWhileUnlocked() }
                return []
            } else {
                // present → absent
                if newPresence == .absent {
                    state = .guarding(.absent)
                    return [.setInputPolicy(.lockOnFirstInput), log(.ownerLeft)]
                }
                return []
            }
        case .locked:
            return faceUnlockAttempt(f)
        default:
            return []
        }
    }

    private mutating func faceUnlockAttempt(_ f: FrameSummary) -> [GuardEffect] {
        if lockout.remaining(now: clock.now()) > 0 {
            return [.showShield(.retry(seconds: Int(lockout.remaining(now: clock.now()).rounded(.up))))]
        }
        let message: ShieldMessage
        switch unlockEvaluator.evaluate(frame: f, settings: settings, requestedTurn: requestedTurn, now: f.timestamp) {
        case .unlock: return unlock(by: .unlockedByFace)
        case .needBlink: message = .blink; lastBlinkPromptAt = f.timestamp
        case .bystander: message = .bystander
        case .needGesture(let t): message = .gesture(t)
        case .lowQuality, .keepWaiting:
            // Yapışkan istem: az önce "göz kırp" denmişse tek kaçan kare mesajı "arıyorum"a düşürmesin.
            message = (f.timestamp - lastBlinkPromptAt <= Self.promptStickiness) ? .blink : .searching
        }
        return [.showShield(message)]
    }

    // MARK: Sensörler / sahne

    private mutating func handleCamera(_ h: CameraHealth) -> [GuardEffect] {
        switch (state, h) {
        case (.guarding, .lost):
            return lock(.cameraLost, now: clock.now())               // her alt durumda (kör kaldık)
        case (.guarding(.present), .covered):
            // Örtülü kamera sahibi göremez; kare gelmediği için varlık zaman aşımı ancak
            // burada ilerletilebilir. Kısa örtme tolere edilir; 1,5 sn sonra "yok" →
            // ilk girdi kilitler, sonraki örtülü kare T6 ile kilitler (fail-closed).
            if ownerPresence.update(match: .uncertain, trackAlive: false, now: clock.now()) == .absent {
                state = .guarding(.absent)
                return [.setInputPolicy(.lockOnFirstInput), log(.ownerLeft)]
            }
            return []
        case (.guarding(.absent), .covered):
            return lock(.cameraCovered, now: clock.now())
        case (.guarding(.absent), .shifted):
            return settings.cameraShiftDetection ? lock(.cameraShift, now: clock.now()) : []
        default:
            return []
        }
    }

    private mutating func handleLid(_ angle: Double) -> [GuardEffect] {
        switch state {
        case .guarding(.present):
            lid.setBaseline(angle)        // sahip karşıdayken güvenli tabanı güncelle
            return []
        case .guarding(.absent):
            return lid.feed(angle: angle) ? lock(.lidAngle, now: clock.now()) : []
        default:
            return []
        }
    }

    private mutating func handleMotion(tilt: Double, jerk: Double) -> [GuardEffect] {
        guard case .guarding(.absent) = state else { return [] }
        return motion.triggered(tiltDegrees: tilt, jerkG: jerk) ? lock(.motion, now: clock.now()) : []
    }

    private mutating func handleInput() -> [GuardEffect] {
        guard case .guarding(.absent) = state else { return [] }   // sahip yokken ilk girdi kilitler (T3)
        return lock(.input, now: clock.now())
    }

    private mutating func handleHardware(_ c: HardwareChange) -> [GuardEffect] {
        switch c {
        case .filterUnhealthy:
            guard case .guarding = state else { return [] }
            return lock(.filterLost, now: clock.now())
        case .lidSensorLost:
            return [.notify(.sensorFallback("kapak"))]              // uyar, kilitleme (Review Focus 5)
        case .accelerometerLost:
            return [.notify(.sensorFallback("ivmeölçer"))]
        case .display:
            return settings.displayTrigger && isAbsent ? lock(.display, now: clock.now()) : []
        case .usb:
            return settings.usbTrigger && isAbsent ? lock(.usb, now: clock.now()) : []
        case .power:
            return settings.powerTrigger && isAbsent ? lock(.power, now: clock.now()) : []
        }
    }

    // MARK: Şifre

    private mutating func handlePasscode(_ passcode: String) -> [GuardEffect] {
        guard case .locked = state else { return [] }
        let now = clock.now()
        if lockout.remaining(now: now) > 0 {
            return [.showShield(.retry(seconds: Int(lockout.remaining(now: now).rounded(.up))))]
        }
        if verifyPasscode(passcode) {
            return unlock(by: .unlockedByPasscode)
        }
        let wait = lockout.registerFailure(now: now)
        var effects: [GuardEffect] = []
        effects.append(log(.wrongPasscode))
        effects.append(persist(active: true))
        effects.append(wait > 0 ? .showShield(.retry(seconds: Int(wait.rounded(.up)))) : .showShield(.searching))
        return effects
    }

    // MARK: Uyku / açılış

    private mutating func handleWillSleep() -> [GuardEffect] {
        switch state {
        case .guarding, .locked:
            state = .locked(LockedContext(reason: .sleep, since: clock.now()))
            var fx: [GuardEffect] = [.showShield(.searching), .setInputPolicy(.blockAll), .wakeKeep(true)]
            fx.append(log(.slept))
            fx.append(persist(active: true))
            return fx
        default:
            return []
        }
    }

    private mutating func handleDidWake() -> [GuardEffect] {
        guard case .locked = state else { return [] }
        return [log(.woke)]
    }

    private mutating func handleLaunched(boot: String, previous: PersistedState?) -> [GuardEffect] {
        bootSession = boot
        if let prev = previous, prev.active, prev.bootSession == boot {
            // Aynı açılış oturumunda çökme/öldürme sonrası → Kilitli başla (T13).
            lockout = prev.lockout
            lockout.rearm(now: clock.now())
            session = SessionRecord(started: clock.wallNow())
            state = .locked(LockedContext(reason: .relaunch, since: clock.now()))
            var fx: [GuardEffect] = [.startSensors, .showShield(.searching), .setInputPolicy(.blockAll), .wakeKeep(true)]
            fx.append(log(.relaunched))
            fx.append(persist(active: true))
            return fx
        }
        state = .off
        return []
    }

    // MARK: Yardımcılar

    private var isAbsent: Bool { if case .guarding(.absent) = state { return true }; return false }

    private mutating func lock(_ reason: LockReason, now: TimeInterval, bystander: Bool = false) -> [GuardEffect] {
        requestedTurn = [.left, .right, .up][Int(now.magnitude) % 3]
        strangerStreak = 0
        lastBlinkPromptAt = -.greatestFiniteMagnitude
        state = .locked(LockedContext(reason: reason, since: now, bystanderPresent: bystander))
        var fx: [GuardEffect] = [.showShield(.searching), .setInputPolicy(.blockAll), .wakeKeep(true)]
        fx.append(log(.triggered(reason)))
        fx.append(persist(active: true))
        return fx
    }

    private mutating func ownerReturnedWhileUnlocked() -> [GuardEffect] {
        if settings.returnBehavior == .keepGuarding {
            state = .guarding(.present)
            return [.setInputPolicy(.passThrough), log(.ownerReturned)]
        }
        return endGuard(reason: .ownerReturned)
    }

    private mutating func unlock(by kind: GuardLogKind) -> [GuardEffect] {
        lockout.reset()
        if settings.returnBehavior == .keepGuarding {
            ownerPresence = OwnerPresence()
            ownerPresence.seedPresent(now: clock.now())
            state = .guarding(.present)
            var fx: [GuardEffect] = [.hideShield, .setInputPolicy(.passThrough), .wakeKeep(true)]
            fx.append(log(kind))
            fx.append(persist(active: true))
            return fx
        }
        var effects: [GuardEffect] = [.hideShield]
        effects.append(log(kind))
        effects.append(contentsOf: endGuard(reason: nil))
        return effects
    }

    /// Nöbeti kapatır: oturumu bitirir, rapor gerekiyorsa gösterir, Kapalı'ya geçer.
    private mutating func endGuard(reason: GuardLogKind?) -> [GuardEffect] {
        var effects: [GuardEffect] = []
        if let reason { effects.append(log(reason)) }
        if var s = session {
            s.ended = clock.wallNow()
            session = s
            effects.append(ReportBuilder.needsReport(s) ? .showReport(s) : .notify(.guardEndedNoEvents))
        }
        session = nil
        state = .off
        effects.append(contentsOf: [.stopSensors, .wakeKeep(false), .setInputPolicy(.passThrough), persist(active: false)])
        return effects
    }

    private mutating func log(_ kind: GuardLogKind) -> GuardEffect {
        if var s = session {
            s.events.append(GuardEventRecord(at: clock.wallNow(), kind: kind))
            session = s
        }
        return .logEvent(kind)
    }

    private func persist(active: Bool) -> GuardEffect {
        .persist(PersistedState(bootSession: bootSession, active: active, lockout: lockout))
    }
}
