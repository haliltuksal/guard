// nobetci-eval — tanılama ve değerlendirme aracı (dağıtılmaz).
//
//   nobetci-eval live [saniye]   Canlı ölçüm: kamera → tespit → FaceCrop → gömme.
//                                 Kayıtlı profile karşı skorlar + öz-benzerlik dağılımı.
//                                 Kök neden ve eşik kalibrasyonu için kanıt üretir.
//
// Kamera izni: komutu çalıştıran terminal uygulaması için macOS izin ister.

import AVFoundation
import CoreImage
import CryptoKit
import Foundation
import NobetciCore
import NobetciSystem
import NobetciVision

func cosine(_ a: [Float], _ b: [Float]) -> Float {
    var d: Float = 0, na: Float = 0, nb: Float = 0
    for i in a.indices { d += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
    return d / max(na.squareRoot() * nb.squareRoot(), 1e-9)
}

func stats(_ xs: [Float]) -> String {
    guard !xs.isEmpty else { return "(veri yok)" }
    let s = xs.sorted()
    func p(_ q: Double) -> Float { s[min(s.count - 1, Int(Double(s.count - 1) * q))] }
    let mean = s.reduce(0, +) / Float(s.count)
    return String(format: "n=%d  ort=%.3f  min=%.3f  p10=%.3f  medyan=%.3f  p90=%.3f  max=%.3f",
                  s.count, mean, s[0], p(0.10), p(0.5), p(0.90), s[s.count - 1])
}

func pairwise(_ vs: [[Float]]) -> [Float] {
    let v = Array(vs.prefix(80))
    var out: [Float] = []
    for i in 0..<v.count { for j in (i + 1)..<v.count { out.append(cosine(v[i], v[j])) } }
    return out
}

func percentile(_ xs: [Float], _ q: Double) -> Float {
    guard !xs.isEmpty else { return 0 }
    let s = xs.sorted()
    return s[min(s.count - 1, Int(Double(s.count - 1) * q))]
}

/// Gevşek kesit (MTCNN tarzı): yüz kutusu %25 kenar payıyla kare yapılıp 160'a ölçeklenir.
func looseCrop(_ buffer: CVPixelBuffer, bbox: CGRect, context: CIContext) -> CGImage? {
    let w = CGFloat(CVPixelBufferGetWidth(buffer)), h = CGFloat(CVPixelBufferGetHeight(buffer))
    var r = CGRect(x: bbox.minX * w, y: bbox.minY * h, width: bbox.width * w, height: bbox.height * h)
    let side = max(r.width, r.height) * 1.25
    r = CGRect(x: r.midX - side / 2, y: r.midY - side / 2, width: side, height: side)
        .intersection(CGRect(x: 0, y: 0, width: w, height: h))
    guard !r.isEmpty else { return nil }
    let size = CGFloat(FaceEmbedder.inputSize)
    let image = CIImage(cvPixelBuffer: buffer).cropped(to: r)
        .transformed(by: CGAffineTransform(translationX: -r.minX, y: -r.minY))
        .transformed(by: CGAffineTransform(scaleX: size / r.width, y: size / r.height))
    return context.createCGImage(image, from: CGRect(x: 0, y: 0, width: size, height: size))
}

/// Kare başına ölçüm; kamera kuyruğundan çağrılır, sonuçlar kilitle toplanır.
final class LiveProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let detector = FaceDetector()
    private let embedder: FaceEmbedder
    private let matcher: FaceMatcher?
    private let context = CIContext()
    private var analyzer = FrameAnalyzer()
    private let scene = SceneHealthLogic(cameraShiftEnabled: false)
    private let minFaceHeight = PipelineConfig.minFaceHeight(for: .medium)

    private var blink = BlinkDetector()
    private(set) var blinks = 0
    private(set) var ears: [Float] = []
    private(set) var frames = 0, facesSeen = 0, fiveLandmarks = 0, alignOK = 0, coveredFrames = 0
    private(set) var qualities: [Float] = []
    private(set) var brightness: [Float] = []
    private(set) var texture: [Float] = []
    private(set) var facesPerFrame: [Int] = []          // tüm tespitler
    private(set) var bigFacesPerFrame: [Int] = []       // mesafe eşiğini geçenler (pipeline'ın işlediği)
    private(set) var maxProcessMs: Double = 0
    private(set) var vectorsAligned: [[Float]] = []
    private(set) var vectorsLoose: [[Float]] = []
    private(set) var scoresVsProfile: [Float] = []

    init(embedder: FaceEmbedder, matcher: FaceMatcher?) {
        self.embedder = embedder
        self.matcher = matcher
    }

    func handle(_ buffer: CVPixelBuffer) {
        let started = Date()
        defer {
            let ms = Date().timeIntervalSince(started) * 1000
            lock.withLock { maxProcessMs = max(maxProcessMs, ms) }
        }
        let metrics = lock.withLock { analyzer.analyze(gray: VisionPipeline.downsampleGray(buffer)) }
        let covered = scene.isCovered(brightness: Double(metrics.brightness), texture: Double(metrics.texture))
        lock.withLock {
            frames += 1
            brightness.append(metrics.brightness); texture.append(metrics.texture)
            if covered { coveredFrames += 1 }
        }
        guard let det = try? detector.detect(in: buffer) else { return }
        lock.withLock {
            facesPerFrame.append(det.faces.count)
            bigFacesPerFrame.append(det.faces.filter { $0.boundingBox.height >= minFaceHeight }.count)
        }
        guard let face = det.faces.max(by: { $0.boundingBox.height < $1.boundingBox.height }) else { return }
        let ear = (face.leftEyeAR + face.rightEyeAR) / 2
        lock.withLock {
            facesSeen += 1; qualities.append(face.quality); ears.append(ear)
            if blink.feed(ear: ear, now: SystemClock().now()) { blinks += 1 }   // D13: canlılık kontrolü kanıtı
        }
        guard face.landmarks5.count == 5 else { return }
        lock.withLock { fiveLandmarks += 1 }
        guard let aligned = FaceCrop.aligned(pixelBuffer: buffer, landmarks: face.landmarks5, context: context),
              let va = try? embedder.embed(aligned) else { return }
        let vl = looseCrop(buffer, bbox: face.boundingBox, context: context).flatMap { try? embedder.embed($0) }
        let score = matcher?.score(va)
        lock.withLock {
            alignOK += 1
            vectorsAligned.append(va)
            if let vl { vectorsLoose.append(vl) }
            if let score { scoresVsProfile.append(score) }
        }
    }
}

func loadStoredProfile() -> [[Float]]? {
    guard let keyData = KeychainStore().get(account: "dataKey") else { return nil }
    let store = SecureFileStore(directory: SecureFileStore.defaultDirectory(),
                                dataKey: SymmetricKey(data: keyData), settingsKey: SymmetricKey(size: .bits256))
    return try? store.readEncrypted([[Float]].self, from: "profile.bin")
}

func modelURL() -> URL? {
    let candidates = [
        URL(fileURLWithPath: "build/Model.mlpackage"),
        URL(fileURLWithPath: "/Applications/Nöbetçi.app/Contents/Resources/Model.mlpackage"),
    ]
    return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
}

let args = CommandLine.arguments
guard args.count >= 2, args[1] == "live" else {
    print("kullanım: nobetci-eval live [saniye]")
    exit(2)
}
let seconds = args.count >= 3 ? Double(args[2]) ?? 10 : 10

guard let url = modelURL() else { print("model bulunamadı (make model)"); exit(1) }
let embedder = try await FaceEmbedder.load(packageURL: url, cacheDir: nil)
let profile = loadStoredProfile()
let thresholds = Thresholds(accept: 0.70, sustain: 0.55, reject: 0.40)
let probe = LiveProbe(embedder: embedder, matcher: profile.map { FaceMatcher(profile: $0, thresholds: thresholds) })

print("Kayıtlı profil: \(profile.map { "\($0.count) vektör" } ?? "OKUNAMADI (Keychain erişimi reddedildi ya da yok)")")
print("\(Int(seconds)) sn boyunca kameraya bak; başını hafifçe çevir, normal otur…")

let camera = CameraSource(onFrame: { buffer, _ in probe.handle(buffer) }, onInterruption: {})
try camera.configure()
camera.start()
try await Task.sleep(for: .seconds(seconds))
camera.stop()

print("\n=== TESPİT ===")
print("kare: \(probe.frames)  yüz: \(probe.facesSeen)  5-landmark: \(probe.fiveLandmarks)  hizalama OK: \(probe.alignOK)")
print("kalite: \(stats(probe.qualities))")
print("göz kırpma algılandı: \(probe.blinks)   ← 10 sn'de 2–5 bekleniyor (D13 canlılık)   EAR: \(stats(probe.ears))")
func histogram(_ xs: [Int]) -> String {
    let c = xs.reduce(into: [Int: Int]()) { $0[$1, default: 0] += 1 }
    return c.keys.sorted().map { "\($0) yüz: \(c[$0]!) kare" }.joined(separator: "  ")
}
print("kare başı yüz (tüm):      \(histogram(probe.facesPerFrame))")
print("kare başı yüz (≥ mesafe): \(histogram(probe.bigFacesPerFrame))   ← 2+ ise ikinci yüz T1'i tetikler")
print("en uzun kare işleme: \(String(format: "%.0f", probe.maxProcessMs)) ms   ← >1000 ise watchdog şüphesi")

print("\n=== SAHNE (T6 örtülü/karanlık) ===")
print("parlaklık: \(stats(probe.brightness))")
print("doku:      \(stats(probe.texture))")
print("örtülü sayılan kare: \(probe.coveredFrames)/\(probe.frames)   ← 0 değilse sahip varken bile T6 kilidi gelir")

print("\n=== KAYITLI PROFİLE KARŞI SKOR (çalışma anındaki hat: FaceCrop) ===")
print(stats(probe.scoresVsProfile))
if !probe.scoresVsProfile.isEmpty {
    let s = probe.scoresVsProfile
    let owner = s.filter { $0 >= thresholds.accept }.count
    let uncertain = s.filter { $0 < thresholds.accept && $0 >= thresholds.reject }.count
    let stranger = s.filter { $0 < thresholds.reject }.count
    print("sınıflandırma @accept 0.70 / reject 0.40 → sahip: \(owner)  belirsiz: \(uncertain)  yabancı: \(stranger)")
}

print("\n=== ÖZ-BENZERLİK (aynı yüz, kareler arası kosinüs) ===")
let selfAligned = pairwise(probe.vectorsAligned)
print("FaceCrop (hizalı):   \(stats(selfAligned))")
print("Gevşek kesit (bbox): \(stats(pairwise(probe.vectorsLoose)))")

let p10 = percentile(selfAligned, 0.10)
print("\nÖneri: accept ≈ öz-benzerlik p10 − 0.05 → \(String(format: "%.2f", p10 - 0.05)); sustain ≈ accept − 0.10; reject ≈ accept − 0.25")
