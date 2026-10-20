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
    private var ownerConsecutive = 0
    private var lastBlink: TimeInterval?
    private var lastPersonSeen: TimeInterval?
    private var lastFullAnalysis: TimeInterval = -.greatestFiniteMagnitude
    private var previousShiftBuffer: CVPixelBuffer?

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
        // T6: örtülü/karanlık — her karede (ucuz). Kilit tetiklenmesi çekirdekte.
        if scene.isCovered(brightness: Double(metrics.brightness), texture: Double(metrics.texture)) {
            return PipelineOutput(summary: nil, cameraHealth: .covered)
        }
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

        for face in detections.faces where face.boundingBox.height >= config.minFaceHeight {
            guard face.landmarks5.count == 5,
                  let aligned = alignedFace(pixelBuffer: pixelBuffer, face: face, imageW: w, imageH: h),
                  let vector = try? embedder.embed(aligned) else {
                uncertainPresent = true
                continue
            }
            switch matcher.classify(vector, hasVerifiedTrack: ownerConsecutive >= 3) {
            case .owner: ownerFace = face
            case .stranger: strangerPresent = true
            case .uncertain: uncertainPresent = true
            }
        }

        let bodyPresent = detections.bodies.contains { $0.boundingBox.height >= config.minBodyHeight }
        let anyPerson = !detections.faces.isEmpty || !detections.bodies.isEmpty

        if let owner = ownerFace {
            ownerConsecutive += 1
            summary.ownerTrack = OwnerTrackState(recognizedFrameCount: ownerConsecutive, present: true)
            summary.ownerQualityOK = owner.quality >= 0.3 && owner.boundingBox.height >= PipelineConfig.minFaceHeight(for: .near)
            let ear = (owner.leftEyeAR + owner.rightEyeAR) / 2
            if blink.feed(ear: ear, now: now) { lastBlink = now }
            if config.strictMode, let turn = requestedTurn {
                summary.strictGestureSatisfied = Self.gestureSatisfied(turn: turn, yaw: owner.yaw, pitch: owner.pitch)
            }
        } else {
            ownerConsecutive = 0
        }

        summary.strangerFacePresent = strangerPresent
        summary.uncertainFacePresent = uncertainPresent
        summary.bodyPresentBeyondThreshold = bodyPresent && ownerFace == nil
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
        let size = CGFloat(FaceEmbedder.inputSize)
        let template = FaceAligner.canonicalTemplate(size: size)
        let transform = FaceAligner.similarityTransform(from: face.landmarks5, to: template)
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        // Görüntü pikseli (y aşağı) → CIImage (y yukarı) dönüşümü için dikey çevir.
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: imageH)
        let affine = flip.concatenating(transform).concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size))
        let transformed = ci.transformed(by: affine)
        return ciContext.createCGImage(transformed, from: CGRect(x: 0, y: 0, width: size, height: size))
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
    static func downsampleGray(_ pixelBuffer: CVPixelBuffer) -> [Float] {
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
