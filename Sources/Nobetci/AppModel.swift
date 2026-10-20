import SwiftUI
import CryptoKit
import NobetciCore
import NobetciVision
import NobetciSystem

/// Uygulamanın kompozisyon kökü ve olay döngüsü. Tüm adaptörleri kurar, kamera/
/// sensör/girdi geri çağırımlarını koordinatöre (GuardEngine) bağlar ve motorun
/// ürettiği etkileri adaptörlere dağıtır. Görünümler bu @Observable durumu izler.
@MainActor
@Observable
final class AppModel {
    // Gözlemlenen durum
    var state: GuardState = .off
    var shieldMessage: ShieldMessage = .searching
    var passcodeCount = 0
    var sensorStatus = SensorStatus()
    var lastReport: SessionRecord?
    var showingReport = false
    var needsSetup = false
    var prepareProblems: [String] = []

    struct SensorStatus: Equatable {
        var camera = false, lid = false, accelerometer = false, wakeKeep = false
    }

    // Depolama
    private let fileStore: SecureFileStore
    private let keychain = KeychainStore()
    private var settings: GuardSettings

    // Adaptörler
    private var shield: ShieldWindowController!
    private let wakeKeeper = WakeKeeper()
    private let setupPresenter = WindowPresenter()
    private let reportPresenter = WindowPresenter()
    private var enrollment: EnrollmentSession?
    private let notifier = Notifier()
    private var inputFilter: InputFilter!
    private var lidSensor: LidAngleSensor!
    private var accelerometer: Accelerometer!
    private var hardware: HardwareWatcher!
    private var sleepObserver: SleepObserver!
    private var hotKey: HotKey!

    private var coordinator: GuardCoordinator!
    private var pipeline: VisionPipeline?
    private var camera: CameraSource?
    private var passcodeBuffer = ""
    private var currentSession: SessionRecord?

    // MARK: Kurulum

    init() {
        let keys = AppModel.loadOrCreateKeys(keychain: keychain)
        fileStore = SecureFileStore(directory: SecureFileStore.defaultDirectory(),
                                    dataKey: keys.data, settingsKey: keys.settings)
        settings = fileStore.readSettings()
        needsSetup = !isEnrolled()
        configureAdapters()
        rebuildCoordinator()
        bootRecovery()
    }

    private func configureAdapters() {
        shield = ShieldWindowController(screens: SystemScreens()) { [weak self] in
            guard let self else { return NSView() }
            return NSHostingView(rootView: ShieldView(model: self))
        }
        inputFilter = InputFilter(
            onLockRequested: { [weak self] in self?.sendFromAnywhere(.input) },
            onPasscode: { [weak self] decision in Task { @MainActor in self?.handlePasscode(decision) } },
            onHealthChange: { [weak self] healthy in if !healthy { self?.sendFromAnywhere(.hardware(.filterUnhealthy)) } })
        lidSensor = LidAngleSensor(onAngle: { [weak self] a in self?.sendFromAnywhere(.lidAngle(a)) })
        accelerometer = Accelerometer(onMotion: { [weak self] tilt, jerk in self?.sendFromAnywhere(.motion(tiltDegrees: tilt, jerkG: jerk)) })
        hardware = HardwareWatcher(onChange: { [weak self] kind in
            let change: HardwareChange = switch kind { case .display: .display; case .hidOrUSB: .usb; case .power: .power }
            self?.sendFromAnywhere(.hardware(change))
        })
        sleepObserver = SleepObserver(onWillSleep: { [weak self] in self?.sendFromAnywhere(.willSleep) },
                                      onDidWake: { [weak self] in self?.sendFromAnywhere(.didWake) })
        hotKey = HotKey(onFire: { [weak self] in Task { @MainActor in self?.toggleGuard() } })
        try? hotKey.register(settings.hotKey)
        sleepObserver.start()
        notifier.requestAuthorization()
    }

    private func rebuildCoordinator() {
        // Şifre doğrulama Keychain okur (iş parçacığından bağımsız); ana aktör durumunu
        // yakalamayan @Sendable kapanış kullanırız, böylece motor actor'a güvenle geçer.
        let keychain = self.keychain
        let verify: @Sendable (String) -> Bool = { passcode in
            guard let blob = keychain.get(account: "passcode"),
                  let record = try? JSONDecoder().decode(PasscodeRecord.self, from: blob) else { return false }
            return PasscodeHasher.verify(passcode, salt: record.salt, rounds: record.rounds, expected: record.hash)
        }
        let engine = GuardEngine(clock: SystemClock(), settings: settings, verifyPasscode: verify)
        coordinator = GuardCoordinator(engine: engine)
    }

    // MARK: Olay döngüsü

    /// Herhangi bir iş parçacığından gelen geri çağırımları koordinatöre taşır.
    private nonisolated func sendFromAnywhere(_ event: GuardEvent) {
        Task { [weak self] in
            guard let self else { return }
            let effects = await self.coordinator.handle(event)
            await MainActor.run { self.apply(effects) }
        }
    }

    private func send(_ event: GuardEvent) { sendFromAnywhere(event) }

    // MARK: Kullanıcı komutları

    func toggleGuard() {
        switch state {
        case .off: startGuard()
        case .guarding: send(.command(.stopGuard))
        case .preparing, .locked: break
        }
    }

    private func startGuard() {
        let problems = preflight()
        send(.command(.startGuard))
        send(.prepareResult(ok: problems.isEmpty, missing: problems))
        prepareProblems = problems
    }

    private func preflight() -> [String] {
        var problems: [String] = []
        if !InputFilter.hasAccessibilityPermission(prompt: true) { problems.append(L10n.t("preflight.accessibility")) }
        if !isEnrolled() { problems.append(L10n.t("preflight.enrollment")) }
        return problems
    }

    // MARK: Etkileri uygula

    private func apply(_ effects: [GuardEffect]) {
        for effect in effects { apply(effect) }
        Task { state = await coordinator.state }
    }

    private func apply(_ effect: GuardEffect) {
        switch effect {
        case .startSensors: startSensors()
        case .stopSensors: stopSensors()
        case .showShield(let m): shieldMessage = m; passcodeCount = 0; shield.show()
        case .hideShield: shield.hide(animated: true); passcodeBuffer = ""; passcodeCount = 0
        case .setInputPolicy(let p): inputFilter.setPolicy(Self.map(p))
        case .wakeKeep(let on): if on { try? wakeKeeper.start() } else { wakeKeeper.stop() }; sensorStatus.wakeKeep = on
        case .logEvent(let kind): appendLog(kind)
        case .notify(let kind): notifier.post(kind)
        case .showReport(let s): lastReport = s; showReportWindow(s)
        case .persist(let p): persist(p)
        }
    }

    private func startSensors() {
        buildPipelineAndCamera()
        camera?.start()
        lidSensor.start(); sensorStatus.lid = lidSensor.isAvailable
        accelerometer.start(); sensorStatus.accelerometer = accelerometer.isAvailable
        hardware.start()
        try? inputFilter.install()
        sensorStatus.camera = camera != nil
        if !lidSensor.isAvailable { send(.hardware(.lidSensorLost)) }
    }

    private func stopSensors() {
        camera?.stop(); lidSensor.stop(); accelerometer.stop(); hardware.stop(); inputFilter.uninstall()
        sensorStatus = SensorStatus()
    }

    // MARK: Şifre

    private func handlePasscode(_ decision: InputDecision) {
        switch decision {
        case .passcodeText(let s): passcodeBuffer += s; passcodeCount = passcodeBuffer.count
        case .passcodeDelete: if !passcodeBuffer.isEmpty { passcodeBuffer.removeLast() }; passcodeCount = passcodeBuffer.count
        case .passcodeEscape: passcodeBuffer = ""; passcodeCount = 0
        case .passcodeReturn: send(.passcode(passcodeBuffer)); passcodeBuffer = ""; passcodeCount = 0
        case .passcodePending, .pass, .swallow, .swallowAndLock: break
        }
    }

    // MARK: Kayıt ve kalıcılık

    private func appendLog(_ kind: GuardLogKind) {
        if case .guardStarted = kind { currentSession = SessionRecord(started: Date()) }
        currentSession?.events.append(GuardEventRecord(at: Date(), kind: kind))
        if case .guardEnded = kind { flushSession() }
    }

    private func flushSession() {
        guard var s = currentSession else { return }
        s.ended = Date()
        try? fileStore.writeEncrypted(s, to: "session-\(Int(s.started.timeIntervalSince1970)).bin")
        currentSession = nil
    }

    private func persist(_ p: PersistedState) {
        if let data = try? JSONEncoder().encode(p) {
            try? data.write(to: SecureFileStore.defaultDirectory().appendingPathComponent("state.json"), options: .atomic)
        }
    }

    private func bootRecovery() {
        let url = SecureFileStore.defaultDirectory().appendingPathComponent("state.json")
        let previous = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(PersistedState.self, from: $0) }
        send(.launched(bootSession: BootSession.current(), previous: previous))
    }

    // MARK: Yüz kaydı (kurulum sihirbazı çağırır)

    func enroll(profile: [[Float]], passcode: String) throws {
        try fileStore.writeEncrypted(profile, to: "profile.bin")
        let salt = AppModel.randomBytes(16)
        let rounds = 600_000
        let hash = PasscodeHasher.hash(passcode, salt: salt, rounds: rounds)
        let record = PasscodeRecord(salt: salt, rounds: rounds, hash: hash)
        try keychain.set(try JSONEncoder().encode(record), account: "passcode")
        needsSetup = false
    }

    // MARK: Pencereler ve kurulum

    func presentSetupIfNeeded() {
        guard needsSetup else { return }
        setupPresenter.show(title: L10n.t("setup.title"), size: NSSize(width: 480, height: 420)) {
            SetupView(model: self) { [weak self] in self?.setupPresenter.close() }
        }
    }

    private func showReportWindow(_ session: SessionRecord) {
        reportPresenter.show(title: L10n.t("report.title"), size: NSSize(width: 460, height: 420)) {
            ReportView(session: session) { [weak self] in self?.reportPresenter.close() }
        }
    }

    /// Kameradan kısa bir kayıt oturumu: sahip yüzünden hedef sayıda gömme toplar.
    func runEnrollment(onProgress: @escaping @Sendable (Int, Int) -> Void,
                       onComplete: @escaping @Sendable ([[Float]]) -> Void) {
        guard let packageURL = Bundle.main.url(forResource: "Model", withExtension: "mlpackage") else {
            onComplete([]); return
        }
        Task { @MainActor in
            guard let embedder = try? await FaceEmbedder.load(packageURL: packageURL,
                                                              cacheDir: SecureFileStore.defaultDirectory()) else {
                onComplete([]); return
            }
            let session = EnrollmentSession(embedder: embedder, onProgress: onProgress, onComplete: onComplete)
            session.start()
            self.enrollment = session
        }
    }

    func stopEnrollment() { enrollment?.stop(); enrollment = nil }

    func currentSettings() -> GuardSettings { settings }

    func update(_ newSettings: GuardSettings) {
        settings = newSettings
        try? fileStore.writeSettings(newSettings)
        try? hotKey.register(newSettings.hotKey)
        pipeline = nil   // bir sonraki nöbette yeni ayarla kurulur
        if case .off = state { rebuildCoordinator() }
    }

    func isEnrolled() -> Bool {
        keychain.get(account: "passcode") != nil && (try? fileStore.readEncrypted([[Float]].self, from: "profile.bin")) != nil
    }

    private func buildPipelineAndCamera() {
        guard pipeline == nil,
              let profile = try? fileStore.readEncrypted([[Float]].self, from: "profile.bin"),
              let packageURL = Bundle.main.url(forResource: "Model", withExtension: "mlpackage") else { return }
        Task { @MainActor in
            guard let embedder = try? await FaceEmbedder.load(packageURL: packageURL,
                                                              cacheDir: SecureFileStore.defaultDirectory()) else { return }
            let config = PipelineConfig(profile: profile,
                                        thresholds: Thresholds(accept: 0.70, sustain: 0.55, reject: 0.40),
                                        minFaceHeight: PipelineConfig.minFaceHeight(for: settings.distance),
                                        minBodyHeight: 0.25, strictMode: settings.strictMode)
            let builtPipeline = VisionPipeline(detector: FaceDetector(), embedder: embedder, config: config)
            self.pipeline = builtPipeline
            self.camera = CameraSource(
                onFrame: { [weak self] buffer, ts in
                    self?.sendFromAnywhere(.frame(builtPipeline.process(buffer, now: ts)))
                },
                onInterruption: { [weak self] in self?.sendFromAnywhere(.cameraHealth(.lost)) })
            try? self.camera?.configure()
            self.camera?.start()
        }
    }

    // MARK: Yardımcılar

    static func map(_ p: CoreInputPolicy) -> InputPolicy {
        switch p { case .passThrough: .passThrough; case .lockOnFirstInput: .lockOnFirstInput; case .blockAll: .blockAll }
    }

    private static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    private static func loadOrCreateKeys(keychain: KeychainStore) -> (data: SymmetricKey, settings: SymmetricKey) {
        func key(_ account: String) -> SymmetricKey {
            if let existing = keychain.get(account: account) { return SymmetricKey(data: existing) }
            let fresh = SymmetricKey(size: .bits256)
            let raw = fresh.withUnsafeBytes { Data($0) }
            try? keychain.set(raw, account: account)
            return fresh
        }
        return (key("dataKey"), key("settingsKey"))
    }
}

private struct PasscodeRecord: Codable {
    var salt: Data
    var rounds: Int
    var hash: Data
}
