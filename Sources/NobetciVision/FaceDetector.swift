import Vision
import CoreGraphics
import CoreVideo
import Foundation

public struct DetectedFace: Sendable {
    public var boundingBox: CGRect            // normalize (0–1), Vision koordinatı
    public var landmarks5: [CGPoint]          // görüntü pikseli: solGöz, sağGöz, burun, solAğız, sağAğız
    public var leftEyeAR: Float
    public var rightEyeAR: Float
    public var quality: Float
    public var yaw: Float
    public var pitch: Float
}

public struct DetectedBody: Sendable {
    public var boundingBox: CGRect
}

public struct Detections: Sendable {
    public var faces: [DetectedFace]
    public var bodies: [DetectedBody]
}

/// Apple Vision sarmalayıcısı: yüz dikdörtgeni + noktalar + kalite ve üst gövde.
/// Çalışma anı davranışı cihazda doğrulanır; saf yardımcılar (5 nokta, EAR) test edilir.
public final class FaceDetector {
    public init() {}

    public func detect(in pixelBuffer: CVPixelBuffer) throws -> Detections {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        let w = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let h = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        let landmarks = VNDetectFaceLandmarksRequest()
        try handler.perform([landmarks])
        let faceObservations = landmarks.results ?? []

        // Gövde taraması yalnızca yüz yokken (T2 yüzsüz kişi). Yüz varken T1 zaten karar verir;
        // isteği atlamak kare başı süreyi düşürür → yabancıya tepki hızlanır, CPU azalır (D15).
        var detectedBodies: [DetectedBody] = []
        if faceObservations.isEmpty {
            let bodies = VNDetectHumanRectanglesRequest()
            if #available(macOS 12.0, *) { bodies.upperBodyOnly = true }
            try handler.perform([bodies])
            detectedBodies = (bodies.results ?? []).map { DetectedBody(boundingBox: $0.boundingBox) }
        }

        // Kaliteyi AYNI yüz gözlemleri üzerinde hesapla → sonuçlar 1:1 ve sıralı.
        // (Kutu-dizesiyle eşleştirme iki isteğin kutuları birebir örtüşmediği için ~0 veriyordu.)
        var qualities = [Float](repeating: 0, count: faceObservations.count)
        if !faceObservations.isEmpty {
            let quality = VNDetectFaceCaptureQualityRequest()
            quality.inputFaceObservations = faceObservations
            try handler.perform([quality])
            for (i, obs) in (quality.results ?? []).enumerated() where i < qualities.count {
                qualities[i] = obs.faceCaptureQuality ?? 0
            }
        }

        var faces: [DetectedFace] = []
        for (i, obs) in faceObservations.enumerated() {
            let five = Self.fivePoints(from: obs, imageWidth: w, imageHeight: h)
            let (lAR, rAR) = Self.eyeARs(from: obs)
            faces.append(DetectedFace(
                boundingBox: obs.boundingBox,
                landmarks5: five,
                leftEyeAR: lAR,
                rightEyeAR: rAR,
                quality: qualities[i],
                yaw: obs.yaw?.floatValue ?? 0,
                pitch: obs.pitch?.floatValue ?? 0))
        }
        return Detections(faces: faces, bodies: detectedBodies)
    }

    /// Vision normalize noktalarını (yüz kutusuna göre, y yukarı) görüntü pikseli (y aşağı) 5 noktaya çevirir.
    static func fivePoints(from obs: VNFaceObservation, imageWidth w: CGFloat, imageHeight h: CGFloat) -> [CGPoint] {
        guard let lm = obs.landmarks else { return [] }
        func centroid(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
            guard let pts = region?.normalizedPoints, !pts.isEmpty else { return nil }
            let sx = pts.reduce(0) { $0 + CGFloat($1.x) } / CGFloat(pts.count)
            let sy = pts.reduce(0) { $0 + CGFloat($1.y) } / CGFloat(pts.count)
            return toImage(CGPoint(x: sx, y: sy), box: obs.boundingBox, w: w, h: h)
        }
        func lipCorner(_ region: VNFaceLandmarkRegion2D?, leftmost: Bool) -> CGPoint? {
            guard let pts = region?.normalizedPoints, !pts.isEmpty else { return nil }
            let p = leftmost ? pts.min { $0.x < $1.x }! : pts.max { $0.x < $1.x }!
            return toImage(CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)), box: obs.boundingBox, w: w, h: h)
        }
        let points = [centroid(lm.leftEye), centroid(lm.rightEye), centroid(lm.nose),
                      lipCorner(lm.outerLips, leftmost: true), lipCorner(lm.outerLips, leftmost: false)]
        return points.compactMap { $0 }
    }

    /// Vision'ın yüz-kutusu-göreli (y yukarı) normalize noktasını görüntü pikseline (y aşağı) çevirir.
    static func toImage(_ p: CGPoint, box: CGRect, w: CGFloat, h: CGFloat) -> CGPoint {
        let nx = box.origin.x + p.x * box.width
        let ny = box.origin.y + p.y * box.height
        return CGPoint(x: nx * w, y: (1 - ny) * h)
    }

    static func eyeARs(from obs: VNFaceObservation) -> (Float, Float) {
        (eyeAR(obs.landmarks?.leftEye), eyeAR(obs.landmarks?.rightEye))
    }

    /// Göz açıklık oranı: dikey açıklık / yatay genişlik (göz kapalıyken düşer).
    static func eyeAR(_ region: VNFaceLandmarkRegion2D?) -> Float {
        guard let pts = region?.normalizedPoints, pts.count >= 4 else { return 1 }
        let xs = pts.map { $0.x }, ys = pts.map { $0.y }
        let width = CGFloat((xs.max()! - xs.min()!))
        let height = CGFloat((ys.max()! - ys.min()!))
        return width > 0 ? Float(height / width) : 1
    }
}
