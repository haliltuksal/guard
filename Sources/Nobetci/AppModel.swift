import SwiftUI
import CryptoKit
import NobetciCore
import NobetciVision
import NobetciSystem

/// Uygulamanın kompozisyon kökü ve olay döngüsü. Tüm adaptörleri kurar, kamera/
/// sensör/girdi geri çağırımlarını koordinatöre (GuardEngine) bağlar ve motorun
/// ürettiği etkileri adaptörlere dağıtır. Görünümler bu @Observable durumu izler.
/// Kamera geri çağırımı ana aktör dışında çalışır; kameraya oradan erişebilmek için
/// küçük bir taşıyıcı. Yalnızca kurulumda yazılır, sonra okunur.
final class CameraBox: @unchecked Sendable {
    var camera: CameraSource?
}

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
    /// Menüdeki "Fotoğraflar" satırının sayacı.
    var photoCount = 0
    /// Yüz profili, güncel kesit hattından daha eski bir sürümle kaydedildi mi?
    var profileNeedsRefresh = false
    /// Oda karanlık ve kilitliyiz: kalkan ekranı aydınlatıp yüzü görünür kılsın.
    var shieldNeedsLight = false

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
    private let photosPresenter = WindowPresenter()
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
    private var sessionSnapshots: [SnapshotRef] = []
    /// Sen yokken çekilip henüz gösterilmemiş fotoğraflar (dönüşte açılacak pencere).
    private var unseenSnapshots: [SnapshotRef] = []
    /// Tüm nöbetlerden kalan fotoğrafların künye dizini (galeri bunu okur).
    private var snapshotIndex = SnapshotIndex()
    /// Galeride aynı anda çözülecek en fazla görüntü (bellek tavanı).
    static let galleryLimit = 200
    static let snapshotPrefix = "snap-"
    /// Şifreyle açılışta öğrenilen yüz vektörleri (kayıt profili bozulmaz, ayrı dosya).
    static let adaptiveProfileFile = "profile-adaptive.bin"
    static let profileVersionFile = "profile-version.bin"
    static let maxAdaptiveVectors = 20
    static let snapshotIndexFile = "photos-index.bin"

    // Seri olay kanalı: tüm kaynaklardan gelen olaylar FIFO sırayla motora ulaşır.
    private let events: AsyncStream<GuardEvent>
    private let eventSink: AsyncStream<GuardEvent>.Continuation
    private let frameClock = LastFrameClock()
    private var watchdog: Timer?

    // MARK: Kurulum

    init() {
        let keys = AppModel.loadOrCreateKeys(keychain: keychain)
        fileStore = SecureFileStore(directory: SecureFileStore.defaultDirectory(),
                                    dataKey: keys.data, settingsKey: keys.settings)
        settings = fileStore.readSettings()
        (events, eventSink) = AsyncStream<GuardEvent>.makeStream()
        snapshotIndex = (try? fileStore.readEncrypted(SnapshotIndex.self, from: AppModel.snapshotIndexFile)) ?? SnapshotIndex()
        pruneSnapshots()                     // açılışta süresi geçenleri at (nöbet beklemeden)
        needsSetup = !isEnrolled()
        let storedVersion = (try? fileStore.readEncrypted(Int.self, from: AppModel.profileVersionFile)) ?? 1
        profileNeedsRefresh = !needsSetup && storedVersion != FaceCrop.pipelineVersion
        configureAdapters()
        rebuildCoordinator()
        startEventLoop()
        bootRecovery()
    }

    /// Olayları tek tek, geldikleri sırayla işler (sıra garantisi — başlat/hazırla
    /// yarışı ve şifre karakter karışması olmaz).
    private func startEventLoop() {
        Task { @MainActor in
            for await event in events {
                let effects = await coordinator.handle(event)
                apply(effects)
                let newState = await coordinator.state
                state = newState
                let locked: Bool = if case .locked = newState { true } else { false }
                pipeline?.setLocked(locked)
                // Fotoğraf adayı yalnızca sen yokken/kilitliyken tutulur (gereksiz kodlama yok).
                pipeline?.setCapturing(locked || newState == .guarding(.absent))
            }
        }
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

    /// Herhangi bir iş parçacığından olayı seri kanala koyar (sıra korunur).
    private nonisolated func sendFromAnywhere(_ event: GuardEvent) { eventSink.yield(event) }

    private func send(_ event: GuardEvent) { eventSink.yield(event) }

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
    }

    private func apply(_ effect: GuardEffect) {
        switch effect {
        case .startSensors: startSensors()
        case .stopSensors: stopSensors()
        case .showShield(let m):
            shieldMessage = m
            if case .gesture(let t) = m { pipeline?.setRequestedTurn(t) } else { pipeline?.setRequestedTurn(nil) }
            shield.show()
        case .hideShield: shield.hide(animated: true); passcodeBuffer = ""; passcodeCount = 0
        case .setInputPolicy(let p): inputFilter.setPolicy(Self.map(p))
        case .wakeKeep(let on): if on { try? wakeKeeper.start() } else { wakeKeeper.stop() }; sensorStatus.wakeKeep = on
        case .captureSnapshot(let reason): captureSnapshot(reason)
        case .logEvent(let kind):
            appendLog(kind)
            if kind == .unlockedByPasscode { learnFaceFromPasscodeUnlock() }
        case .notify(let kind): notifier.post(kind)
        case .showSnapshots: showUnseenSnapshots()
        case .showReport(let s):
            var merged = s
            merged.snapshots = sessionSnapshots      // fotoğraf künyeleri uygulama katmanında tutulur
            lastReport = merged
            showReportWindow(merged)
        case .persist(let p): persist(p)
        }
    }

    private func startSensors() {
        sessionSnapshots.removeAll()
        unseenSnapshots.removeAll()
        pruneSnapshots()                     // saklama süresi dolanları at
        buildPipelineAndCamera()
        camera?.start()
        lidSensor.start(); sensorStatus.lid = lidSensor.isAvailable
        accelerometer.start(); sensorStatus.accelerometer = accelerometer.isAvailable
        hardware.start()
        do { try inputFilter.install() } catch {
            send(.hardware(.filterUnhealthy))   // filtre kurulamadı → fail-closed (T14), sessizce "nöbette" kalma
        }
        if !lidSensor.isAvailable { send(.hardware(.lidSensorLost)) }
        startWatchdog()
    }

    private func stopSensors() {
        watchdog?.invalidate(); watchdog = nil
        camera?.stop(); lidSensor.stop(); accelerometer.stop(); hardware.stop(); inputFilter.uninstall()
        camera = nil; pipeline = nil        // her nöbet temiz başlar (eski iz/kırpma durumu taşınmaz)
        sensorStatus = SensorStatus()
        flushSession()                      // nöbet nasıl bitse bitsin (yüz/dönüş/durdur) kayıt yazılır
    }

    /// Kamera karesi akışı sessizce durursa (kesinti bildirimi gelmese bile) kilitler (T7).
    private func startWatchdog() {
        frameClock.reset()
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, case .guarding = self.state else { return }
                // Kamera ısınması normaldir (0,5–2 s; ilk açılışta model derleme). Yalnızca akış
                // BAŞLADIKTAN sonra durursa (>1 s) ya da hiç başlamazsa (>10 s) kilitle.
                if self.frameClock.isStalled(gap: 1.0, startupGrace: 10.0) { self.send(.cameraHealth(.lost)) }
            }
        }
    }

    nonisolated func markFrameArrived() { frameClock.mark() }

    // MARK: Fotoğraf (sen yokken kim yaklaştı)

    /// Bekleyen kamera karesini şifreleyip diske yazar. Ağ yok; dosya cihazdan çıkmaz.
    private func captureSnapshot(_ reason: SnapshotReason) {
        guard settings.captureSnapshots, let jpeg = pipeline?.consumeSnapshot() else { return }
        let id = "\(Self.snapshotPrefix)\(Int(Date().timeIntervalSince1970 * 1000))"
        let ref = SnapshotRef(id: id, at: Date(), reason: reason)
        do {
            try fileStore.writeEncrypted(jpeg, to: "\(id).bin")
            sessionSnapshots.append(ref)
            unseenSnapshots.append(ref)
            for dropped in snapshotIndex.add(ref) { removeSnapshotFile(dropped.id) }   // tavan aşıldıysa en eskisi gider
            saveSnapshotIndex()
            photoCount = snapshotIndex.count
        } catch {
            // Disk dolu/yazılamıyor: koruma etkilenmez, fotoğraf atlanır.
        }
    }

    /// Rapor ve galeri için fotoğrafları çözer (şifreli dosyadan görüntüye).
    func loadSnapshots(_ refs: [SnapshotRef]) -> [(ref: SnapshotRef, image: NSImage)] {
        refs.compactMap { ref in
            guard let data = try? fileStore.readEncrypted(Data.self, from: "\(ref.id).bin"),
                  let image = NSImage(data: data) else { return nil }
            return (ref, image)
        }
    }

    /// Galerinin içeriği: tüm nöbetlerden kalan fotoğraflar, yeniden eskiye.
    func allSnapshots() -> [(ref: SnapshotRef, image: NSImage)] {
        pruneSnapshots()
        return loadSnapshots(Array(snapshotIndex.newestFirst.prefix(Self.galleryLimit)))
    }

    /// Saklama süresi dolanları siler (künye + dosya) ve dizinde olmayan artıkları süpürür.
    func pruneSnapshots() {
        let dropped = snapshotIndex.prune(olderThan: settings.snapshotRetentionDays, now: Date())
        for ref in dropped { removeSnapshotFile(ref.id) }
        if !dropped.isEmpty { saveSnapshotIndex() }
        // Dizin kaybolursa diskte öksüz dosya kalmasın (dosya tarihine göre ikinci süpürme).
        fileStore.removeExpired(prefix: Self.snapshotPrefix, days: settings.snapshotRetentionDays)
        sessionSnapshots.removeAll { ref in dropped.contains { $0.id == ref.id } }
        unseenSnapshots.removeAll { ref in dropped.contains { $0.id == ref.id } }
        photoCount = snapshotIndex.count
    }

    @discardableResult
    func deleteSnapshot(id: String) -> Bool {
        let removed = snapshotIndex.remove(id: id)
        removeSnapshotFile(id)
        sessionSnapshots.removeAll { $0.id == id }
        unseenSnapshots.removeAll { $0.id == id }
        if removed { saveSnapshotIndex() }
        photoCount = snapshotIndex.count
        return removed
    }

    @discardableResult
    func deleteAllSnapshots() -> Int {
        sessionSnapshots.removeAll()
        unseenSnapshots.removeAll()
        snapshotIndex.removeAll()
        saveSnapshotIndex()
        photoCount = 0
        return fileStore.removeAll(prefix: Self.snapshotPrefix)
    }

    private func removeSnapshotFile(_ id: String) {
        fileStore.remove(name: "\(id).bin")
    }

    private func saveSnapshotIndex() {
        try? fileStore.writeEncrypted(snapshotIndex, to: Self.snapshotIndexFile)
    }

    /// Sen yokken çekilenleri döndüğün anda gösterir ("Buradayım" beklemeden).
    private func showUnseenSnapshots() {
        pruneSnapshots()
        let refs = unseenSnapshots
        unseenSnapshots.removeAll()
        let photos = loadSnapshots(refs)
        guard !photos.isEmpty else { return }      // yazılamadıysa boş pencere açma
        showPhotosWindow(photos, headline: L10n.t("photos.whileAway", "\(photos.count)"))
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
        if currentSession == nil { currentSession = SessionRecord(started: Date()) }   // relaunch oturumları dahil
        currentSession?.events.append(GuardEventRecord(at: Date(), kind: kind))
    }

    private func flushSession() {
        guard var s = currentSession else { return }
        s.ended = Date()
        try? fileStore.writeEncrypted(s, to: "session-\(Int(s.started.timeIntervalSince1970)).bin")
        currentSession = nil
    }

    /// Çalışma durumu + yanlış şifre sayacı Keychain'de (spec §9.1): düz dosyada değil,
    /// yeniden başlatmada da korunur (sayaç oynanamaz, sıfırlanmaz).
    private func persist(_ p: PersistedState) {
        if let data = try? JSONEncoder().encode(p) { try? keychain.set(data, account: "guardState") }
    }

    private func bootRecovery() {
        let previous = keychain.get(account: "guardState")
            .flatMap { try? JSONDecoder().decode(PersistedState.self, from: $0) }
        send(.launched(bootSession: BootSession.current(), previous: previous))
    }

    // MARK: Yüz kaydı (kurulum sihirbazı çağırır)

    func enroll(profile: [[Float]], passcode: String) throws {
        try fileStore.writeEncrypted(profile, to: "profile.bin")
        try? fileStore.writeEncrypted(FaceCrop.pipelineVersion, to: Self.profileVersionFile)
        let salt = AppModel.randomBytes(16)
        let rounds = PasscodeHasher.calibratedRounds(targetSeconds: 0.25, floor: 600_000)   // spec §9.2
        let hash = PasscodeHasher.hash(passcode, salt: salt, rounds: rounds)
        let record = PasscodeRecord(salt: salt, rounds: rounds, hash: hash)
        try keychain.set(try JSONEncoder().encode(record), account: "passcode")
        needsSetup = false
    }

    // MARK: Pencereler ve kurulum

    func presentSetupIfNeeded() {
        guard needsSetup, !setupPresenter.isShowing else { return }   // açılış + menü tıklaması çifte pencere açmasın
        setupPresenter.show(title: L10n.t("setup.title"), size: NSSize(width: 480, height: 420)) {
            SetupView(model: self) { [weak self] in self?.setupPresenter.close() }
        }
    }

    /// Menüdeki "Fotoğraflar" düğmesi: tüm kayıtlı fotoğraflar, yeniden eskiye.
    func openPhotoGallery() {
        showPhotosWindow(allSnapshots(), headline: nil)
    }

    private func showPhotosWindow(_ photos: [(ref: SnapshotRef, image: NSImage)], headline: String?) {
        photosPresenter.show(title: L10n.t("photos.title"), size: NSSize(width: 560, height: 580)) {
            PhotosView(model: self, photos: photos, headline: headline) { [weak self] in self?.photosPresenter.close() }
        }
    }

    private func showReportWindow(_ session: SessionRecord) {
        let photos = loadSnapshots(session.snapshots)
        reportPresenter.show(title: L10n.t("report.title"), size: NSSize(width: 520, height: 560)) {
            ReportView(session: session, photos: photos) { [weak self] in self?.reportPresenter.close() }
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

    /// Yüz profilini yeniler (Ayarlar → Kilit açma): yeni kayıt oturumu; tamamlanınca üzerine yazar.
    func reenrollFace(onProgress: @escaping @Sendable (Int, Int) -> Void,
                      onComplete: @escaping @Sendable (Bool) -> Void) {
        runEnrollment(onProgress: onProgress) { [weak self] vectors in
            Task { @MainActor in
                guard let self else { onComplete(false); return }
                self.stopEnrollment()
                guard !vectors.isEmpty else { onComplete(false); return }
                do {
                    try self.fileStore.writeEncrypted(vectors, to: "profile.bin")
                    self.fileStore.remove(name: AppModel.adaptiveProfileFile)   // yeni kayıt: öğrenilenler sıfırlanır
                    try self.fileStore.writeEncrypted(FaceCrop.pipelineVersion, to: AppModel.profileVersionFile)
                    self.profileNeedsRefresh = false
                    onComplete(true)
                }
                catch { onComplete(false) }
            }
        }
    }

    /// Nöbetçi'yi tümüyle kaldırır: launchd kaydı, Keychain kayıtları ve tüm veri.
    func uninstall() {
        try? LaunchAgent.unregister()
        for account in ["passcode", "dataKey", "settingsKey", "guardState"] { try? keychain.delete(account: account) }
        try? fileStore.removeAll()
        NSApp.terminate(nil)
    }

    func currentSettings() -> GuardSettings { settings }

    func update(_ newSettings: GuardSettings) {
        settings = newSettings
        try? fileStore.writeSettings(newSettings)
        pruneSnapshots()                     // saklama süresi kısaldıysa hemen uygula
        try? hotKey.register(newSettings.hotKey)
        pipeline = nil   // bir sonraki nöbette yeni ayarla kurulur
        if case .off = state {
            rebuildCoordinator()
            // Yeni motor bootSession'ı bilmez; yeniden tohumla, yoksa çökme sonrası kilitli açılış (T13) bozulur.
            send(.launched(bootSession: BootSession.current(), previous: nil))
        }
    }

    func isEnrolled() -> Bool {
        keychain.get(account: "passcode") != nil && (try? fileStore.readEncrypted([[Float]].self, from: "profile.bin")) != nil
    }

    private func buildPipelineAndCamera() {
        guard pipeline == nil,
              let profile = loadMergedProfile(),
              let packageURL = Bundle.main.url(forResource: "Model", withExtension: "mlpackage") else { return }
        Task { @MainActor in
            guard let embedder = try? await FaceEmbedder.load(packageURL: packageURL,
                                                              cacheDir: SecureFileStore.defaultDirectory()) else { return }
            let config = PipelineConfig(profile: profile,
                                        thresholds: Thresholds(accept: 0.70, sustain: 0.55, reject: 0.40),
                                        minFaceHeight: PipelineConfig.minFaceHeight(for: settings.distance),
                                        minBodyHeight: 0.25, strictMode: settings.strictMode,
                                        cameraShiftEnabled: settings.cameraShiftDetection)
            let builtPipeline = VisionPipeline(detector: FaceDetector(), embedder: embedder, config: config)
            self.pipeline = builtPipeline
            // Kamera kendi kare geri çağırımından erişilsin (ana aktör dışı): küçük kutu.
            let cameraBox = CameraBox()
            let builtCamera = CameraSource(
                onFrame: { [weak self] buffer, _ in
                    self?.markFrameArrived()   // VARIŞI işaretle (işleme süresini değil): watchdog kamerayı ölçer
                    // TEK zaman tabanı: motorun saati (mach_continuous). Kamera PTS'i KULLANILMAZ —
                    // o mach_absolute tabanlıdır (uykuda durur); motorun varlık tohumuyla
                    // karışırsa uyumuş bir Mac'te sahip saatlerce "var" sayılır (fail-open).
                    let output = builtPipeline.process(buffer, now: SystemClock().now())
                    guard let self else { return }
                    if let summary = output.summary { self.sendFromAnywhere(.frame(summary)) }
                    if let health = output.cameraHealth { self.sendFromAnywhere(.cameraHealth(health)) }
                    // Karanlıkta: kamerayı uzun pozlamaya al, kalkanı ışık kaynağı yap.
                    let dark = builtPipeline.isSceneDark
                    cameraBox.camera?.setLowLight(dark)
                    Task { @MainActor [weak self] in self?.shieldNeedsLight = dark }
                },
                onInterruption: { [weak self] in self?.sendFromAnywhere(.cameraHealth(.lost)) })
            cameraBox.camera = builtCamera
            self.camera = builtCamera
            try? self.camera?.configure()
            self.camera?.start()
            self.sensorStatus.camera = true
        }
    }

    /// Kayıt profili + şifreyle açılışta öğrenilenler. Öğrenilenler ayrı dosyada tutulur:
    /// "yüz profilini yenile" dediğinde kayıt temiz kalsın, öğrenilenler sıfırlansın.
    private func loadMergedProfile() -> [[Float]]? {
        guard let base = try? fileStore.readEncrypted([[Float]].self, from: "profile.bin") else { return nil }
        let adaptive = (try? fileStore.readEncrypted([[Float]].self, from: Self.adaptiveProfileFile)) ?? []
        return base + adaptive
    }

    /// Şifre doğru girildi: kimlik kanıtlandı. O anki yüz (yeni ışık, gözlük, saç) profile
    /// eklenir — bir daha aynı koşulda tanınmamak yerine öğrenir (Face ID'nin yaklaşımı).
    private func learnFaceFromPasscodeUnlock() {
        guard let vector = pipeline?.consumeLearningCandidate() else { return }
        var adaptive = (try? fileStore.readEncrypted([[Float]].self, from: Self.adaptiveProfileFile)) ?? []
        adaptive.append(vector)
        if adaptive.count > Self.maxAdaptiveVectors {
            adaptive.removeFirst(adaptive.count - Self.maxAdaptiveVectors)   // en eskisi düşer
        }
        try? fileStore.writeEncrypted(adaptive, to: Self.adaptiveProfileFile)
        pipeline?.addProfileVector(vector)      // sonraki nöbeti bekleme, hemen geçerli olsun
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

/// Kamera karesi varış zamanını iş parçacığı-güvenli tutar (kamera bg yazar, watchdog ana okur).
/// İlk kare gelmeden "durdu" demez: ısınma için ayrı, daha uzun bir başlangıç toleransı vardır.
final class LastFrameClock: @unchecked Sendable {
    private let lock = NSLock()
    private var started = Date()
    private var last: Date?
    func reset() { lock.withLock { started = Date(); last = nil } }
    func mark() { lock.withLock { last = Date() } }
    func isStalled(gap: TimeInterval, startupGrace: TimeInterval) -> Bool {
        lock.withLock {
            if let last { return Date().timeIntervalSince(last) > gap }
            return Date().timeIntervalSince(started) > startupGrace
        }
    }
}
