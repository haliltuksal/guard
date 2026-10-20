import Foundation
import CoreImage
import CoreVideo
import NobetciVision

/// Kurulumda sahip yüzünden hedef sayıda gömme toplar (kamera açık kalır). Kare
/// geri çağırımı arka iş parçacığında çalıştığından toplama kilitle korunur.
final class EnrollmentSession: @unchecked Sendable {
    private let lock = NSLock()
    private var vectors: [[Float]] = []
    private var finished = false
    private let target: Int
    private let detector = FaceDetector()
    private let embedder: FaceEmbedder
    private let ciContext = CIContext()
    private var camera: CameraSource?

    private let onProgress: @Sendable (Int, Int) -> Void
    private let onComplete: @Sendable ([[Float]]) -> Void

    init(embedder: FaceEmbedder, target: Int = 50,
         onProgress: @escaping @Sendable (Int, Int) -> Void,
         onComplete: @escaping @Sendable ([[Float]]) -> Void) {
        self.embedder = embedder
        self.target = target
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func start() {
        let cam = CameraSource(onFrame: { [weak self] buffer, _ in self?.consume(buffer) },
                               onInterruption: {})
        try? cam.configure()
        cam.start()
        camera = cam
    }

    func stop() { camera?.stop(); camera = nil }

    private func consume(_ buffer: CVPixelBuffer) {
        lock.lock()
        let done = finished || vectors.count >= target
        lock.unlock()
        guard !done,
              let detections = try? detector.detect(in: buffer),
              let face = detections.faces.max(by: { $0.boundingBox.height < $1.boundingBox.height }),
              face.landmarks5.count == 5 else { return }

        let size = CGFloat(FaceEmbedder.inputSize)
        let transform = FaceAligner.similarityTransform(from: face.landmarks5, to: FaceAligner.canonicalTemplate(size: size))
        let ci = CIImage(cvPixelBuffer: buffer).transformed(by: transform)
        guard let cg = ciContext.createCGImage(ci, from: CGRect(x: 0, y: 0, width: size, height: size)),
              let vector = try? embedder.embed(cg) else { return }

        lock.lock()
        vectors.append(vector)
        let count = vectors.count
        let complete = count >= target && !finished
        if complete { finished = true }
        let snapshot = vectors
        lock.unlock()

        onProgress(count, target)
        if complete {
            // stopRunning() kamera delegate kuyruğundan çağrılırsa deadlock riski: ana kuyruğa at.
            DispatchQueue.main.async { [self] in self.stop() }
            onComplete(snapshot)
        }
    }
}
