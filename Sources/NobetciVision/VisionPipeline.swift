import CoreVideo
import CoreGraphics
import CoreImage
import Foundation
import NobetciCore

/// Görüntü hattının yapılandırması: sahip profili, eşikler ve mesafe (en küçük
/// normalize yüz yüksekliği). Değerler kurulum/ayarlardan gelir.
public struct PipelineConfig: Sendable {
    public var profile: [[Float]]
    public var thresholds: Thresholds
    public var minFaceHeight: CGFloat     // normalize (0–1); mesafe hassasiyeti
    public var minBodyHeight: CGFloat
    public var strictMode: Bool
    public init(profile: [[Float]], thresholds: Thresholds,
                minFaceHeight: CGFloat, minBodyHeight: CGFloat, strictMode: Bool) {
        self.profile = profile
        self.thresholds = thresholds
        self.minFaceHeight = minFaceHeight
        self.minBodyHeight = minBodyHeight
        self.strictMode = strictMode
    }

    public static func minFaceHeight(for distance: DistanceSensitivity) -> CGFloat {
        switch distance {
        case .near: return 0.18
        case .medium: return 0.12
        case .far: return 0.07
        }
    }
}

/// Kareden `FrameSummary` üretir. Çekirdek yalnızca bu özeti görür. Ağ yok;
/// yabancı vektörleri saklanmaz. Çalışma anı doğruluğu cihazda ölçülür (D13/D14).
public final class VisionPipeline {
    private let detector: FaceDetector
    private let embedder: FaceEmbedder
    private let matcher: FaceMatcher
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private var analyzer = FrameAnalyzer()
    private var tracker = TrackManager()
    private var blink = BlinkDetector()

    private let config: PipelineConfig
    private var ownerConsecutive = 0
    private var lastBlink: TimeInterval?
    private var lastPersonSeen: TimeInterval?
    private var lastFullAnalysis: TimeInterval = -.greatestFiniteMagnitude

    /// Sıkı modda istenen baş hareketi; uygulama katmanı motor istedikçe ayarlar.
    public var requestedTurn: Turn?

    public init(detector: FaceDetector, embedder: FaceEmbedder, config: PipelineConfig) {
        self.detector = detector
        self.embedder = embedder
        self.config = config
        self.matcher = FaceMatcher(profile: config.profile, thresholds: config.thresholds)
    }

    public func process(_ pixelBuffer: CVPixelBuffer, now: TimeInterval) -> FrameSummary {
        let metrics = analyzer.analyze(gray: Self.downsampleGray(pixelBuffer))
        var summary = FrameSummary.empty
        summary.timestamp = now

        let needFull = metrics.motionEnergy > 0.02 || (now - lastFullAnalysis) >= 0.5
        guard needFull, let detections = try? detector.detect(in: pixelBuffer) else {
            summary.sceneEmptyFor = sceneEmptyDuration(now: now, anyPerson: false)
            return summary
        }
        lastFullAnalysis = now

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
        return summary
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
