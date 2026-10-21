import CoreVideo
import CoreGraphics
import CoreImage
import ImageIO
import Foundation
import Vision
import NobetciCore

/// Görüntü hattının yapılandırması: sahip profili, eşikler ve mesafe (en küçük
/// normalize yüz yüksekliği). Değerler kurulum/ayarlardan gelir.
public struct PipelineConfig: Sendable {
    public var profile: [[Float]]
    public var thresholds: Thresholds
    public var minFaceHeight: CGFloat     // normalize (0–1); mesafe hassasiyeti
    public var minBodyHeight: CGFloat
    public var strictMode: Bool
    public var cameraShiftEnabled: Bool
    public init(profile: [[Float]], thresholds: Thresholds,
                minFaceHeight: CGFloat, minBodyHeight: CGFloat, strictMode: Bool, cameraShiftEnabled: Bool) {
        self.profile = profile
        self.thresholds = thresholds
        self.minFaceHeight = minFaceHeight
        self.minBodyHeight = minBodyHeight
        self.strictMode = strictMode
        self.cameraShiftEnabled = cameraShiftEnabled
    }

    public static func minFaceHeight(for distance: DistanceSensitivity) -> CGFloat {
        switch distance {
        case .near: return 0.18
        case .medium: return 0.12
        case .far: return 0.07
        }
    }
}

/// Kare işleme çıktısı: motor için özet (skip karelerde nil → motoru yanıltma) ve
/// gerekirse kamera sağlık olayı (T6 örtülü/karanlık, T8 kayma).
public struct PipelineOutput: Sendable {
    public var summary: FrameSummary?
    public var cameraHealth: CameraHealth?
}

/// Kareden `FrameSummary` üretir. Çekirdek yalnızca bu özeti görür. Ağ yok;
/// yabancı vektörleri saklanmaz. Çalışma anı doğruluğu cihazda ölçülür (D13/D14).
/// `@unchecked Sendable`: `process` yalnızca tek seri kamera kuyruğundan çağrılır;
/// `locked`/`requestedTurn` kilitle korunur (ana iş parçacığından yazılır).
public final class VisionPipeline: @unchecked Sendable {
    private let detector: FaceDetector
    private let embedder: FaceEmbedder
    /// Yalnızca kamera kuyruğunda değiştirilir (bekleyen eklemeler kare başında uygulanır).
    private var matcher: FaceMatcher
    private let scene: SceneHealthLogic
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private var analyzer = FrameAnalyzer()
    private var tracker = TrackManager()
    private var blink = BlinkDetector()

    private let config: PipelineConfig
    private var ownerRecognitions = RecentWindow()   // kilit açma: 1 sn içinde ≥5 tanıma (kayan)
    private var lastBlink: TimeInterval?
    private var lastPersonSeen: TimeInterval?
    private var lastFullAnalysis: TimeInterval = -.greatestFiniteMagnitude
    private var previousShiftBuffer: CVPixelBuffer?
    private var coveredDebounce = CoveredDebouncer()
    private var threats = ThreatTracker()
    /// Sahip kimliğinin çapası (bkz `OwnerAnchor`): tanıma kaybolsa da iz sürdükçe sahip oradadır.
    private var anchor = OwnerAnchor()
    /// Sahibin bölgesinde çapayı taşımak için gereken en az kişi-maskesi oranı.
    /// `nobetci-eval presence` çıktısındaki dağılımla kalibre edilir.
    private static let ownerRegionCoverage: Float = 0.20

    private let stateLock = NSLock()
    private var _requestedTurn: Turn?
    private var _locked = false
    private var _capturing = false
    private var _snapshot: Data?          // en son/en kaliteli aday (JPEG)
    private var _snapshotAt: TimeInterval = -.greatestFiniteMagnitude
    /// Şifreyle kilit açıldığında profile eklenecek aday vektör.
    private var _learningCandidate: [Float]?
    /// Profile eklenmeyi bekleyen vektörler (ana aktörden gelir, kamera kuyruğunda uygulanır).
    private var _pendingProfileAdditions: [[Float]] = []

    public init(detector: FaceDetector, embedder: FaceEmbedder, config: PipelineConfig) {
        self.detector = detector
        self.embedder = embedder
        self.config = config
        self.matcher = FaceMatcher(profile: config.profile, thresholds: config.thresholds)
        self.scene = SceneHealthLogic(cameraShiftEnabled: config.cameraShiftEnabled)
    }

    /// Sıkı modda istenen baş hareketi; motor gesture isteyince ana iş parçacığı ayarlar.
    public func setRequestedTurn(_ turn: Turn?) { stateLock.withLock { _requestedTurn = turn } }
    /// Kilit durumu; kilitliyken blink için her kare tam analiz yapılır (§6.2).
    public func setLocked(_ locked: Bool) { stateLock.withLock { _locked = locked } }

    /// Sahip yokken/kilitliyken fotoğraf adayı tutulur (yalnızca o zaman kodlanır).
    public func setCapturing(_ on: Bool) {
        stateLock.withLock {
            _capturing = on
            if !on { _snapshot = nil }
        }
    }

    /// Şifre doğru girildiğinde (kimlik kanıtlandı) profile eklenecek yüz vektörünü alır.
    /// Yalnızca kadrajda TEK ve okunabilir bir yüz varken doldurulur: yanındaki birini
    /// ya da kötü açılı bir kareyi profile yazmasın.
    /// Öğrenilen vektörü hemen devreye alır (sonraki nöbeti beklemeden).
    public func addProfileVector(_ vector: [Float]) {
        stateLock.withLock { _pendingProfileAdditions.append(vector) }
    }

    public func consumeLearningCandidate() -> [Float]? {
        stateLock.withLock { defer { _learningCandidate = nil }; return _learningCandidate }
    }

    /// Bekleyen fotoğrafı alır ve tüketir (motor `captureSnapshot` etkisi verince çağrılır).
    public func consumeSnapshot() -> Data? {
        stateLock.withLock { defer { _snapshot = nil }; return _snapshot }
    }

    public func process(_ pixelBuffer: CVPixelBuffer, now: TimeInterval) -> PipelineOutput {
        let additions = stateLock.withLock { defer { _pendingProfileAdditions = [] }; return _pendingProfileAdditions }
        if !additions.isEmpty { matcher = matcher.adding(additions) }
        let metrics = analyzer.analyze(gray: Self.downsampleGray(pixelBuffer))
        // T6: örtülü/karanlık — ≥ 0,5 sn sürmeli (spec). Kamera ısınmasındaki siyah kareler
        // (ölçüldü ~0,3 sn) ve anlık gölgeler sayılmaz; geçici karanlık karede motora özet gönderilmez.
        let coveredNow = scene.isCovered(brightness: Double(metrics.brightness), texture: Double(metrics.texture))
        if coveredDebounce.feed(covered: coveredNow, now: now) {
            return PipelineOutput(summary: nil, cameraHealth: .covered)
        }
        if coveredNow { return PipelineOutput(summary: nil, cameraHealth: nil) }
        let (locked, requestedTurn) = stateLock.withLock { (_locked, _requestedTurn) }
        // Biri görünür görünmez tam analiz HER karede (30 fps): yabancı/yaklaşan kişide blur gecikmesi
        // sahnenin durgunluğuna bağlı kalmasın. Kimse yokken 0,5 sn'de bir (pil).
        let personRecently = lastPersonSeen.map { now - $0 <= 1.0 } ?? false
        let needFull = locked || personRecently || metrics.motionEnergy > 0.02 || (now - lastFullAnalysis) >= 0.5
        // Maske yalnızca taşınacak bir çapa varken: sahip gerçekten yokken bedeli sıfır.
        let needsMask = anchor.isAlive(now: now)
        guard needFull, let detections = try? detector.detect(in: pixelBuffer, needsPersonMask: needsMask) else {
            return PipelineOutput(summary: nil, cameraHealth: nil)   // skip: motora kare gönderme
        }
        lastFullAnalysis = now

        var summary = FrameSummary.empty
        summary.timestamp = now
        let w = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let h = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        var ownerFace: DetectedFace?
        var strangerPresent = false
        var uncertainPresent = false

        // İz sürekliliği: sahibin KENDİ izi kötü açıda belirsiz skor verirse bu bir yabancı
        // değildir (ölçüldü: kafa çevirince 263 karenin 12'si 0,70 altı). Tehdit yalnızca
        // FARKLI bir izdir. Sahip izi 1,5 sn hatırlanır; sürdürme eşiği de buna bağlıdır.
        let ids = tracker.updateAssigning(boxes: detections.faces.map(\.boundingBox), now: now).ids
        threats.retain(onlyIDs: Set(ids))

        // Bu karedeki hangi yüz sahibin izi? Önce aynı iz; iz koptuysa aynı yerde beliren
        // yüz (el çekildi, kafa geri geldi) — kimlik sürekliliği, tanıma şartı yok.
        var ownerIndex: Int?
        if anchor.isAlive(now: now) {
            if let id = anchor.trackID, let i = ids.firstIndex(of: id) {
                ownerIndex = i
            } else if let i = detections.faces.firstIndex(where: { anchor.canRebind(to: $0.boundingBox, now: now) }) {
                anchor.rebind(trackID: ids[i], box: detections.faces[i].boundingBox, now: now)
                ownerIndex = i
            } else if anchor.canAdoptSoleFace(faceCount: detections.faces.count, now: now) {
                anchor.rebind(trackID: ids[0], box: detections.faces[0].boundingBox, now: now)
                ownerIndex = 0
            }
        }
        let anchoredAtStart = anchor.isAlive(now: now)   // eşik histerezisi kare boyunca sabit

        // T1 zamanlaması iz başına: belirsiz → 0,3 sn kabul süresi; yabancı → 3 ardışık T_red altı.
        func flag(_ r: (uncertain: Bool, stranger: Bool)) {
            if r.uncertain { uncertainPresent = true }
            if r.stranger { strangerPresent = true }
        }

        var ownerTrackFace: DetectedFace?   // sahip izindeki yüz (bu karede eşleşmese de): kırpma/kalite buradan okunur

        for (i, face) in detections.faces.enumerated() where face.boundingBox.height >= config.minFaceHeight {
            let isOwnerTrack = ownerIndex == i
            if isOwnerTrack { ownerTrackFace = face }
            // Okunamayan yüzden kimlik kararı çıkarılmaz: dik açı/bulanıklık ne "sahip"
            // ne "yabancı" demektir. Sahibin telefona bakan yüzü buradan geçer.
            let readable = FaceReadability.isReadable(yaw: face.yaw, pitch: face.pitch, quality: face.quality)
            guard face.landmarks5.count == 5,
                  let aligned = alignedFace(pixelBuffer: pixelBuffer, face: face, imageW: w, imageH: h),
                  let vector = try? embedder.embed(aligned) else {
                if isOwnerTrack { anchor.sustain(box: face.boundingBox, now: now) }
                else { flag(threats.observe(trackID: ids[i], belowReject: false, now: now)) }
                continue
            }
            let score = matcher.score(vector)
            // Öğrenme adayı: kadrajda tek yüz, okunabilir ve kalitesi yeterli. Şifre doğru
            // girilirse bu vektör profile eklenir (yeni ışık/gözlük/saç uyumu).
            if detections.faces.count == 1, readable, face.quality >= 0.2 {
                stateLock.withLock { _learningCandidate = vector }
            }
            // Düşük (sürdürme) eşiği YALNIZCA sahibin izindeki yüze uygulanır. Çapa uzun
            // yaşadığı için bunu tüm yüzlere açmak, 0,55–0,70 arası skorlayan bir yabancıyı
            // "sahip" sayardı; başka her yüz kabul eşiğine tabidir.
            switch matcher.classify(score: score, hasVerifiedTrack: anchoredAtStart && isOwnerTrack) {
            case .owner:
                ownerFace = face
                anchor.verify(trackID: ids[i], box: face.boundingBox, now: now)
                ownerIndex = i
                // Kilit açma penceresine yalnızca T_kabul üstü kareler girer (spec §5.4.1); sürdürme
                // eşiğiyle geçen kötü-açı kareleri varlığı korur ama kilidi tek başına açmaz.
                if score >= matcher.thresholds.accept { ownerRecognitions.add(now) }
                threats.clear(trackID: ids[i])
            case .stranger:
                if isOwnerTrack {
                    // Sahibin izinde OKUNABİLİR ve kesin yabancı bir yüz: koltuk el değiştirmiş
                    // olabilir → çapayı bırak, tehdit say. Okunamayan yüz karar vermez.
                    if readable {
                        anchor.drop()
                        ownerIndex = nil
                        flag(threats.observe(trackID: ids[i], belowReject: true, now: now))
                    } else {
                        anchor.sustain(box: face.boundingBox, now: now)
                    }
                } else {
                    flag(threats.observe(trackID: ids[i], belowReject: true, now: now))
                }
            case .uncertain:
                if isOwnerTrack { anchor.sustain(box: face.boundingBox, now: now) }
                else { flag(threats.observe(trackID: ids[i], belowReject: false, now: now)) }
            }
        }

        // Yüz hiç görünmüyor: sahibin DURDUĞU YERDE hâlâ biri var mı? Gövde dedektörü
        // yakın mesafede susuyor (ölçüldü), bu yüzden asıl dayanak kişi maskesi. Bölgeyle
        // sınırlı bakılır: sandalyedeki mont ya da arkadan geçen biri çapayı yaşatmasın.
        if detections.faces.isEmpty {
            let region = PersonMask.ownerRegion(faceBox: anchor.box)
            let covered = detections.personMask.map { $0.coverage(in: region) >= Self.ownerRegionCoverage } ?? false
            if covered || !detections.bodies.isEmpty { anchor.carry(now: now) }
        }
        let anchored = anchor.isAlive(now: now)

        let bodyPresent = detections.bodies.contains { $0.boundingBox.height >= config.minBodyHeight }
        let anyPerson = !detections.faces.isEmpty || !detections.bodies.isEmpty

        // Kilit açma sayacı: kayan pencere (spec §5.4.1); tek kaçan kare sıfırlamaz.
        let recentRecognitions = ownerRecognitions.count(within: 1.0, now: now)
        if ownerFace != nil || (anchored && recentRecognitions > 0) {
            // `present` kesin eşleşmedir (motorun varlık mantığı bunu kullanır); sayaç pencereden gelir.
            summary.ownerTrack = OwnerTrackState(recognizedFrameCount: recentRecognitions, present: ownerFace != nil)
        }
        // Kalite, göz kırpma ve baş hareketi sahip İZİNDEKİ yüzden okunur — bu karede eşleşmese bile.
        // Kırpma 100–300 ms sürer; yalnızca eşleşen karelerde dinlenirse kaçar (cihazda yaşandı).
        if let owner = ownerFace ?? ownerTrackFace {
            // Vision kalite ölçümü gece webcam'de 0,30–0,55 (min 0,21 ölçüldü); 0,25 taban.
            summary.ownerQualityOK = owner.quality >= 0.25 && owner.boundingBox.height >= PipelineConfig.minFaceHeight(for: .near)
            let ear = (owner.leftEyeAR + owner.rightEyeAR) / 2
            if blink.feed(ear: ear, now: now) { lastBlink = now }
            if config.strictMode, let turn = requestedTurn {
                summary.strictGestureSatisfied = Self.gestureSatisfied(turn: turn, yaw: owner.yaw, pitch: owner.pitch)
            }
        }

        // Fotoğraf adayı: yalnızca yakalama açıkken ve en fazla ~3/sn kodla (maliyet).
        let shouldSnap = stateLock.withLock { _capturing && now - _snapshotAt >= 0.3 }
        if shouldSnap, let jpeg = makeJPEG(from: pixelBuffer) {
            stateLock.withLock { _snapshot = jpeg; _snapshotAt = now }
        }

        summary.strangerFacePresent = strangerPresent
        summary.uncertainFacePresent = uncertainPresent
        summary.ownerAnchored = anchored
        // Çapa canlıyken kadrajdaki gövde sahibin kendi gövdesidir, yabancı değil.
        summary.bodyPresentBeyondThreshold = bodyPresent && ownerFace == nil && ownerTrackFace == nil && !anchored
        summary.anyPersonPresent = anyPerson
        summary.blinkObservedWithin = lastBlink.map { now - $0 }
        summary.sceneEmptyFor = sceneEmptyDuration(now: now, anyPerson: anyPerson)

        // T8: kişi yokken kamera açısı/konumu kaydı (kapak sensörü olmayan Mac yedeği).
        // Çapa canlıyken kadrajdaki değişim sahibin kendi hareketidir (el, saç düzeltme):
        // "kamera oynatıldı" sanılıp kilitlenmesin (cihazda yaşandı, 17:05).
        var health: CameraHealth?
        if !anyPerson, !anchored {
            if let prev = previousShiftBuffer, isShifted(from: prev, to: pixelBuffer, width: w) { health = .shifted }
            previousShiftBuffer = pixelBuffer
        } else {
            previousShiftBuffer = nil
        }
        return PipelineOutput(summary: summary, cameraHealth: health)
    }

    /// İki kare arasındaki genel öteleme kaydını Vision ile ölçer; eşiği aşarsa kayma.
    private func isShifted(from previous: CVPixelBuffer, to current: CVPixelBuffer, width: CGFloat) -> Bool {
        guard config.cameraShiftEnabled else { return false }
        let request = VNTranslationalImageRegistrationRequest(targetedCVPixelBuffer: current)
        guard (try? VNImageRequestHandler(cvPixelBuffer: previous, options: [:]).perform([request])) != nil,
              let observation = request.results?.first as? VNImageTranslationAlignmentObservation else { return false }
        let tx = abs(observation.alignmentTransform.tx)
        let ty = abs(observation.alignmentTransform.ty)
        let fraction = max(tx, ty) / max(width, 1)
        return scene.isShifted(translationFraction: Double(fraction))
    }

    /// Kareyi ~720 px genişliğe indirip JPEG'e kodlar (fotoğraf kaydı için).
    private func makeJPEG(from pixelBuffer: CVPixelBuffer, maxWidth: CGFloat = 720, quality: CGFloat = 0.7) -> Data? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let scale = min(1, maxWidth / max(image.extent.width, 1))
        let scaled = scale < 1 ? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) : image
        return ciContext.jpegRepresentation(of: scaled,
                                            colorSpace: CGColorSpaceCreateDeviceRGB(),
                                            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality])
    }

    private func sceneEmptyDuration(now: TimeInterval, anyPerson: Bool) -> TimeInterval {
        if anyPerson { lastPersonSeen = now; return 0 }
        guard let last = lastPersonSeen else { return .greatestFiniteMagnitude }
        return now - last
    }

    private func alignedFace(pixelBuffer: CVPixelBuffer, face: DetectedFace, imageW: CGFloat, imageH: CGFloat) -> CGImage? {
        // Kayıtla AYNI kesit (FaceCrop); ayrı uygulama profil/canlı uyumsuzluğu yaratmıştı.
        FaceCrop.aligned(pixelBuffer: pixelBuffer, landmarks: face.landmarks5, context: ciContext)
    }

    static func gestureSatisfied(turn: Turn, yaw: Float, pitch: Float) -> Bool {
        let threshold: Float = 0.26   // ~15°
        switch turn {
        case .left: return yaw < -threshold
        case .right: return yaw > threshold
        case .up: return pitch > threshold
        }
    }

    /// BGRA kareyi 64×36 gri diziye indirger (ucuz metrikler için örnekleme).
    public static func downsampleGray(_ pixelBuffer: CVPixelBuffer) -> [Float] {
        let outW = 64, outH = 36
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [Float](repeating: 0, count: outW * outH) }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var out = [Float](repeating: 0, count: outW * outH)
        for oy in 0..<outH {
            let sy = oy * h / outH
            for ox in 0..<outW {
                let sx = ox * w / outW
                let p = sy * stride + sx * 4
                let b = Float(ptr[p]), g = Float(ptr[p + 1]), r = Float(ptr[p + 2])
                out[oy * outW + ox] = (0.299 * r + 0.587 * g + 0.114 * b) / 255
            }
        }
        return out
    }
}
