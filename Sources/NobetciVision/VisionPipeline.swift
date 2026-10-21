import CoreVideo
import CoreGraphics
import CoreImage
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
    private let matcher: FaceMatcher
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
    private var ownerTrackID: Int?
    private var ownerTrackLastSeen: TimeInterval = -.greatestFiniteMagnitude
    private static let ownerTrackMemory: TimeInterval = 1.5

    private let stateLock = NSLock()
    private var _requestedTurn: Turn?
    private var _locked = false

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

    public func process(_ pixelBuffer: CVPixelBuffer, now: TimeInterval) -> PipelineOutput {
        let metrics = analyzer.analyze(gray: Self.downsampleGray(pixelBuffer))
        // T6: örtülü/karanlık — ≥ 0,5 sn sürmeli (spec). Kamera ısınmasındaki siyah kareler
        // (ölçüldü ~0,3 sn) ve anlık gölgeler sayılmaz; geçici karanlık karede motora özet gönderilmez.
        let coveredNow = scene.isCovered(brightness: Double(metrics.brightness), texture: Double(metrics.texture))
        if coveredDebounce.feed(covered: coveredNow, now: now) {
            return PipelineOutput(summary: nil, cameraHealth: .covered)
        }
        if coveredNow { return PipelineOutput(summary: nil, cameraHealth: nil) }
        let (locked, requestedTurn) = stateLock.withLock { (_locked, _requestedTurn) }
        let needFull = locked || metrics.motionEnergy > 0.02 || (now - lastFullAnalysis) >= 0.5
        guard needFull, let detections = try? detector.detect(in: pixelBuffer) else {
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
        let ownerTrackRecent = ownerTrackID != nil && now - ownerTrackLastSeen <= Self.ownerTrackMemory
        threats.retain(onlyIDs: Set(ids))

        // T1 zamanlaması iz başına (spec): belirsiz → 0,5 sn kabul süresi; yabancı → 3 ardışık T_red altı.
        func flag(_ r: (uncertain: Bool, stranger: Bool)) {
            if r.uncertain { uncertainPresent = true }
            if r.stranger { strangerPresent = true }
        }

        var ownerTrackFace: DetectedFace?   // sahip izindeki yüz (bu karede eşleşmese de): kırpma/kalite buradan okunur

        for (i, face) in detections.faces.enumerated() where face.boundingBox.height >= config.minFaceHeight {
            let isOwnerTrack = ownerTrackRecent && ids[i] == ownerTrackID
            if isOwnerTrack { ownerTrackFace = face }
            guard face.landmarks5.count == 5,
                  let aligned = alignedFace(pixelBuffer: pixelBuffer, face: face, imageW: w, imageH: h),
                  let vector = try? embedder.embed(aligned) else {
                if !isOwnerTrack { flag(threats.observe(trackID: ids[i], belowReject: false, now: now)) }
                continue
            }
            switch matcher.classify(vector, hasVerifiedTrack: ownerTrackRecent) {
            case .owner:
                ownerFace = face
                ownerTrackID = ids[i]
                ownerTrackLastSeen = now
                ownerRecognitions.add(now)
                threats.clear(trackID: ids[i])
            case .stranger:
                if !isOwnerTrack { flag(threats.observe(trackID: ids[i], belowReject: true, now: now)) }
            case .uncertain:
                if !isOwnerTrack { flag(threats.observe(trackID: ids[i], belowReject: false, now: now)) }
            }
        }

        let bodyPresent = detections.bodies.contains { $0.boundingBox.height >= config.minBodyHeight }
        let anyPerson = !detections.faces.isEmpty || !detections.bodies.isEmpty

        // Kilit açma sayacı: kayan pencere (spec §5.4.1); tek kaçan kare sıfırlamaz.
        let recentRecognitions = ownerRecognitions.count(within: 1.0, now: now)
        if ownerFace != nil || (ownerTrackRecent && recentRecognitions > 0) {
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

        summary.strangerFacePresent = strangerPresent
        summary.uncertainFacePresent = uncertainPresent
        summary.bodyPresentBeyondThreshold = bodyPresent && ownerFace == nil && ownerTrackFace == nil
        summary.anyPersonPresent = anyPerson
        summary.blinkObservedWithin = lastBlink.map { now - $0 }
        summary.sceneEmptyFor = sceneEmptyDuration(now: now, anyPerson: anyPerson)

        // T8: kişi yokken kamera açısı/konumu kaydı (kapak sensörü olmayan Mac yedeği).
        var health: CameraHealth?
        if !anyPerson {
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
