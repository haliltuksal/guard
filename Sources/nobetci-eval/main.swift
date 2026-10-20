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

    private(set) var frames = 0, facesSeen = 0, fiveLandmarks = 0, alignOK = 0
    private(set) var qualities: [Float] = []
    private(set) var vectorsAligned: [[Float]] = []
    private(set) var vectorsLoose: [[Float]] = []
    private(set) var scoresVsProfile: [Float] = []

    init(embedder: FaceEmbedder, matcher: FaceMatcher?) {
        self.embedder = embedder
        self.matcher = matcher
    }

    func handle(_ buffer: CVPixelBuffer) {
        lock.withLock { frames += 1 }
        guard let det = try? detector.detect(in: buffer),
              let face = det.faces.max(by: { $0.boundingBox.height < $1.boundingBox.height }) else { return }
        lock.withLock { facesSeen += 1; qualities.append(face.quality) }
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
