// nobetci-eval — tanılama ve değerlendirme aracı (dağıtılmaz).
//
//   nobetci-eval live [saniye]   Canlı ölçüm: kamera → tespit → FaceCrop → gömme.
//                                 Kayıtlı profile karşı skorlar + öz-benzerlik dağılımı.
//                                 Kök neden ve eşik kalibrasyonu için kanıt üretir.
//
//   nobetci-eval presence [sn]   Varlık sürekliliği: sahip okunmadığı anlarda gövde ve
//                                 yüz izi hâlâ görülüyor mu? Yanlış "sahip yok" kararının
//                                 (telefona bakma, burun kaşıma) kanıtını üretir.
//
// Kamera izni: komutu çalıştıran terminal uygulaması için macOS izin ister.

import AVFoundation
import Vision
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


// MARK: Varlık sürekliliği ölçümü (yanlış "sahip yok" kararı)

/// Her karede: yüz var mı, sahip eşleşti mi, yüz izi canlı mı, gövde görülüyor mu.
/// Gövde isteği burada HER karede çalışır (hatta yüz varken de) — üretimdeki hat
/// yüz varken gövdeyi atlar; ölçüm bu kısıtı kaldırıp kapsamayı görmek için.
final class PresenceProbe: @unchecked Sendable {
    struct Sample {
        let t: TimeInterval
        let faces: Int
        let bodies: Int
        let ownerScore: Float?      // en iyi skor (yüz varsa)
        let ownerTrackAlive: Bool   // sahibin yüz izi bu karede de eşleşti mi
        let yaw: Float?
        let pitch: Float?
        let quality: Float?
    }

    private let lock = NSLock()
    private let detector = FaceDetector()
    private let embedder: FaceEmbedder
    private let matcher: FaceMatcher?
    private let context = CIContext()
    private let minFaceHeight = PipelineConfig.minFaceHeight(for: .medium)
    private let minBodyHeight: CGFloat = 0.20
    private var tracker = TrackManager()
    private var ownerTrackID: Int?
    private(set) var samples: [Sample] = []
    private var t0: TimeInterval?

    init(embedder: FaceEmbedder, matcher: FaceMatcher?) {
        self.embedder = embedder
        self.matcher = matcher
    }

    private func bodies(in buffer: CVPixelBuffer) -> Int {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        let request = VNDetectHumanRectanglesRequest()
        if #available(macOS 12.0, *) { request.upperBodyOnly = true }
        guard (try? handler.perform([request])) != nil else { return 0 }
        return (request.results ?? []).filter { $0.boundingBox.height >= minBodyHeight }.count
    }

    func handle(_ buffer: CVPixelBuffer) {
        let now = SystemClock().now()
        guard let det = try? detector.detect(in: buffer) else { return }
        let bodyCount = bodies(in: buffer)

        lock.lock()
        let ids = tracker.updateAssigning(boxes: det.faces.map(\.boundingBox), now: now).ids
        let ownerID = ownerTrackID
        lock.unlock()

        var best: Float?
        var bestIndex: Int?
        var bestFace: DetectedFace?
        for (i, face) in det.faces.enumerated() where face.boundingBox.height >= minFaceHeight {
            guard face.landmarks5.count == 5,
                  let aligned = FaceCrop.aligned(pixelBuffer: buffer, landmarks: face.landmarks5, context: context),
                  let vector = try? embedder.embed(aligned),
                  let score = matcher?.score(vector) else { continue }
            if best == nil || score > best! { best = score; bestIndex = i; bestFace = face }
        }

        lock.withLock {
            if let b = best, b >= 0.70, let i = bestIndex { ownerTrackID = ids[i] }
            let alive = ownerID != nil && ids.contains(ownerID!)
            if t0 == nil { t0 = now }
            // Poz/kalite: yüz varsa en büyük yüzünkini de kaydet (okunabilirlik kalibrasyonu).
            let face = bestFace ?? det.faces.max(by: { $0.boundingBox.height < $1.boundingBox.height })
            samples.append(Sample(t: now - (t0 ?? now), faces: det.faces.count,
                                  bodies: bodyCount, ownerScore: best, ownerTrackAlive: alive,
                                  yaw: face?.yaw, pitch: face?.pitch, quality: face?.quality))
        }
    }
}

func reportPresence(_ samples: [PresenceProbe.Sample], sustain: Float) {
    guard samples.count > 1 else { print("örnek yok"); return }
    let matched = samples.filter { ($0.ownerScore ?? 0) >= sustain }
    let gapsSamples = samples.filter { ($0.ownerScore ?? 0) < sustain }
    let withBody = gapsSamples.filter { $0.bodies > 0 }
    let withTrack = gapsSamples.filter { $0.ownerTrackAlive }
    let withEither = gapsSamples.filter { $0.bodies > 0 || $0.ownerTrackAlive }
    let nothing = gapsSamples.filter { $0.bodies == 0 && $0.faces == 0 }

    func pct(_ n: Int, _ d: Int) -> String { d == 0 ? "-" : String(format: "%%%.0f", 100.0 * Double(n) / Double(d)) }

    print("\n=== VARLIK SÜREKLİLİĞİ ===")
    print("kare: \(samples.count)   sahip eşleşti (skor ≥ \(sustain)): \(matched.count) (\(pct(matched.count, samples.count)))")
    print("sahip OKUNMAYAN kare: \(gapsSamples.count)")
    print("  · gövde görülüyor:        \(withBody.count) (\(pct(withBody.count, gapsSamples.count)))")
    print("  · yüz izi canlı:          \(withTrack.count) (\(pct(withTrack.count, gapsSamples.count)))")
    print("  · ikisinden biri:         \(withEither.count) (\(pct(withEither.count, gapsSamples.count)))   ← çapa bu")
    print("  · hiçbir şey yok:         \(nothing.count) (\(pct(nothing.count, gapsSamples.count)))")

    // Kesintiler: sahip okunmayan ardışık diziler.
    struct Gap { var start: TimeInterval; var end: TimeInterval; var n = 0; var body = 0; var track = 0; var either = 0 }
    var gaps: [Gap] = []
    var current: Gap?
    for s in samples {
        if (s.ownerScore ?? 0) >= sustain {
            if let g = current { gaps.append(g); current = nil }
        } else {
            var g = current ?? Gap(start: s.t, end: s.t)
            g.end = s.t; g.n += 1
            if s.bodies > 0 { g.body += 1 }
            if s.ownerTrackAlive { g.track += 1 }
            if s.bodies > 0 || s.ownerTrackAlive { g.either += 1 }
            current = g
        }
    }
    if let g = current { gaps.append(g) }

    let long = gaps.filter { $0.end - $0.start >= 1.5 }
    print("\nkesinti sayısı: \(gaps.count)   1,5 sn'yi aşan: \(long.count)   ← mevcut kodda bunlar \"sahip yok\" demek")
    for g in gaps.sorted(by: { ($0.end - $0.start) > ($1.end - $1.start) }).prefix(6) {
        print(String(format: "  %.1f sn  (%d kare)  gövde %@  yüz izi %@  biri %@",
                     g.end - g.start, g.n, pct(g.body, g.n), pct(g.track, g.n), pct(g.either, g.n)))
    }
    // Okunabilirlik: sahip okunmayan karelerde yüz hangi açıdaydı?
    let gapYaw = gapsSamples.compactMap(\.yaw), gapPitch = gapsSamples.compactMap(\.pitch)
    let gapQ = gapsSamples.compactMap(\.quality)
    if !gapPitch.isEmpty {
        print("\n=== OKUNABİLİRLİK (sahip okunmayan karelerde) ===")
        print("yaw   (rad): \(stats(gapYaw))")
        print("pitch (rad): \(stats(gapPitch))")
        print("kalite:      \(stats(gapQ))")
        let unreadable = zip(zip(gapYaw, gapPitch), gapQ).filter { !FaceReadability.isReadable(yaw: $0.0.0, pitch: $0.0.1, quality: $0.1) }.count
        print("mevcut eşiklerle \"okunamaz\" sayılan: \(unreadable)/\(gapQ.count) (\(pct(unreadable, gapQ.count)))")
        print("  ← yüksek olması İYİ: okunamayan yüzden \"yabancı\" kararı çıkmaz")
    }

    if let worst = long.max(by: { ($0.end - $0.start) < ($1.end - $1.start) }) {
        print(String(format: "\nen uzun yanlış-yokluk: %.1f sn — bu süre boyunca çapa kapsaması %@",
                     worst.end - worst.start, pct(worst.either, worst.n)))
    } else {
        print("\n1,5 sn'yi aşan kesinti olmadı (bu turda yanlış kilit beklenmez).")
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
guard args.count >= 2, ["live", "presence"].contains(args[1]) else {
    print("kullanım: nobetci-eval live|presence [saniye]")
    exit(2)
}
let mode = args[1]
let seconds = args.count >= 3 ? Double(args[2]) ?? 10 : 10

guard let url = modelURL() else { print("model bulunamadı (make model)"); exit(1) }
let embedder = try await FaceEmbedder.load(packageURL: url, cacheDir: nil)
let profile = loadStoredProfile()
let thresholds = Thresholds(accept: 0.70, sustain: 0.55, reject: 0.40)
let faceMatcher = profile.map { FaceMatcher(profile: $0, thresholds: thresholds) }

if mode == "presence" {
    let p = PresenceProbe(embedder: embedder, matcher: faceMatcher)
    print("Kayıtlı profil: \(profile.map { "\($0.count) vektör" } ?? "OKUNAMADI")")
    print("\(Int(seconds)) sn: NORMAL otur ve arada telefonuna bak, burnunu kaşı, başını çevir —")
    print("yani uygulamanın yanlış kilitlediği hareketleri yap. Masadan KALKMA.")
    let cam = CameraSource(onFrame: { buffer, _ in p.handle(buffer) }, onInterruption: {})
    try cam.configure()
    cam.start()
    try await Task.sleep(for: .seconds(seconds))
    cam.stop()
    reportPresence(p.samples, sustain: thresholds.sustain)
    exit(0)
}

let probe = LiveProbe(embedder: embedder, matcher: faceMatcher)

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
