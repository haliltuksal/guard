// nobetci-eval — tanılama ve değerlendirme aracı (dağıtılmaz).
//
//   nobetci-eval live [saniye]   Canlı ölçüm: kamera → tespit → FaceCrop → gömme.
//                                 Kayıtlı profile karşı skorlar + öz-benzerlik dağılımı.
//                                 Kök neden ve eşik kalibrasyonu için kanıt üretir.
//
//   nobetci-eval snaps           Kaydedilmiş yanlış-alarm karelerini çözer ve ölçer:
//                                 yüz / gövde / kişi maskesi hangisi görüyor? Hatanın
//                                 kendi karesi üzerinde kanıt üretir (kamera gerekmez).
//
//   nobetci-eval presence [sn]   Varlık sürekliliği: sahip okunmadığı anlarda gövde ve
//                                 yüz izi hâlâ görülüyor mu? Yanlış "sahip yok" kararının
//                                 (telefona bakma, burun kaşıma) kanıtını üretir.
//
// Kamera izni: komutu çalıştıran terminal uygulaması için macOS izin ister.

import AVFoundation
import Vision
import CoreImage
import ImageIO
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
        let pitch: Float?           // landmarks isteğinden
        let rectPitch: Float?       // VNDetectFaceRectanglesRequest rev3'ten (pitch orada var mı?)
        let quality: Float?
        let foreshorten: Float?     // göz-ağız / gözler arası: aşağı bakınca küçülür
        let maskTotal: Float?       // yüz yokken: karedeki kişi oranı
        let maskRegion: Float?      // yüz yokken: sahibin bölgesindeki kişi oranı
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
    private var lastOwnerBox: CGRect = CGRect(x: 0.3, y: 0.2, width: 0.4, height: 0.5)
    private(set) var samples: [Sample] = []
    private var t0: TimeInterval?

    init(embedder: FaceEmbedder, matcher: FaceMatcher?) {
        self.embedder = embedder
        self.matcher = matcher
    }

    /// Rev3 dikdörtgen isteği: pitch yalnızca burada dolu olabilir (landmarks'ta nil gelebiliyor).
    private func rectanglePitch(in buffer: CVPixelBuffer) -> Float? {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        guard (try? handler.perform([request])) != nil,
              let biggest = (request.results ?? []).max(by: { $0.boundingBox.height < $1.boundingBox.height })
        else { return nil }
        return biggest.pitch?.floatValue
    }

    /// Dikey kısalma: göz ortası–ağız ortası uzaklığının gözler arası uzaklığa oranı.
    /// Yüz aşağı (ya da yukarı) döndükçe küçülür; pitch yoksa bunun yerine geçer.
    static func foreshorten(_ p: [CGPoint]) -> Float? {
        guard p.count == 5 else { return nil }
        let eyeMid = CGPoint(x: (p[0].x + p[1].x) / 2, y: (p[0].y + p[1].y) / 2)
        let mouthMid = CGPoint(x: (p[3].x + p[4].x) / 2, y: (p[3].y + p[4].y) / 2)
        let inter = hypot(p[1].x - p[0].x, p[1].y - p[0].y)
        guard inter > 1 else { return nil }
        return Float(hypot(mouthMid.x - eyeMid.x, mouthMid.y - eyeMid.y) / inter)
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
        let rectPitch = rectanglePitch(in: buffer)

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

        // Yüz yokken kişi maskesi (üretimdeki yolun aynısı).
        var maskTotal: Float?, maskRegion: Float?
        if det.faces.isEmpty, let mask = det.personMask {
            maskTotal = mask.total
            maskRegion = mask.coverage(in: PersonMask.ownerRegion(faceBox: lock.withLock { lastOwnerBox }))
        }

        lock.withLock {
            if let b = best, b >= 0.70, let i = bestIndex { ownerTrackID = ids[i] }
            if let i = bestIndex { lastOwnerBox = det.faces[i].boundingBox }
            let alive = ownerID != nil && ids.contains(ownerID!)
            if t0 == nil { t0 = now }
            // Poz/kalite: yüz varsa en büyük yüzünkini de kaydet (okunabilirlik kalibrasyonu).
            let face = bestFace ?? det.faces.max(by: { $0.boundingBox.height < $1.boundingBox.height })
            samples.append(Sample(t: now - (t0 ?? now), faces: det.faces.count,
                                  bodies: bodyCount, ownerScore: best, ownerTrackAlive: alive,
                                  yaw: face?.yaw, pitch: face?.pitch, rectPitch: rectPitch,
                                  quality: face?.quality,
                                  foreshorten: face.flatMap { Self.foreshorten($0.landmarks5) },
                                  maskTotal: maskTotal, maskRegion: maskRegion))
        }
    }
}

func reportPresence(_ samples: [PresenceProbe.Sample], thresholds: Thresholds) {
    guard samples.count > 1 else { print("örnek yok"); return }
    func pct(_ n: Int, _ d: Int) -> String { d == 0 ? "-" : String(format: "%%%.0f", 100.0 * Double(n) / Double(d)) }

    let sustain = thresholds.sustain, accept = thresholds.accept
    let aboveSustain = samples.filter { ($0.ownerScore ?? 0) >= sustain }
    let aboveAccept = samples.filter { ($0.ownerScore ?? 0) >= accept }
    let gapsSamples = samples.filter { ($0.ownerScore ?? 0) < sustain }
    let withBody = gapsSamples.filter { $0.bodies > 0 }
    let withTrack = gapsSamples.filter { $0.ownerTrackAlive }
    let withEither = gapsSamples.filter { $0.bodies > 0 || $0.ownerTrackAlive }
    let nothing = gapsSamples.filter { $0.bodies == 0 && $0.faces == 0 }

    print("\n=== VARLIK SÜREKLİLİĞİ ===")
    print("kare: \(samples.count)")
    print("skor ≥ kabul  (\(accept)):  \(aboveAccept.count) (\(pct(aboveAccept.count, samples.count)))   ← yeniden tanınma bunu ister")
    print("skor ≥ sürdürme (\(sustain)): \(aboveSustain.count) (\(pct(aboveSustain.count, samples.count)))   ← iz canlıyken bu yeter")
    print("sahip OKUNMAYAN kare: \(gapsSamples.count)")
    print("  · gövde görülüyor:  \(withBody.count) (\(pct(withBody.count, gapsSamples.count)))")
    print("  · yüz izi canlı:    \(withTrack.count) (\(pct(withTrack.count, gapsSamples.count)))   ← çapanın asıl dayanağı")
    print("  · ikisinden biri:   \(withEither.count) (\(pct(withEither.count, gapsSamples.count)))")
    print("  · hiçbir şey yok:   \(nothing.count) (\(pct(nothing.count, gapsSamples.count)))")

    // Kesintiler: iki eşik için ayrı ayrı (yeniden tanınma kabul eşiğini ister).
    struct Gap { var start: TimeInterval; var end: TimeInterval; var n = 0; var body = 0; var track = 0; var scores: [Float] = [] }
    func gaps(below threshold: Float) -> [Gap] {
        var out: [Gap] = []
        var current: Gap?
        for s in samples {
            if (s.ownerScore ?? 0) >= threshold {
                if let g = current { out.append(g); current = nil }
            } else {
                var g = current ?? Gap(start: s.t, end: s.t)
                g.end = s.t; g.n += 1
                if s.bodies > 0 { g.body += 1 }
                if s.ownerTrackAlive { g.track += 1 }
                if let sc = s.ownerScore { g.scores.append(sc) }
                current = g
            }
        }
        if let g = current { out.append(g) }
        return out
    }

    for (label, threshold) in [("sürdürme \(sustain)", sustain), ("kabul \(accept)", accept)] {
        let gs = gaps(below: threshold).sorted { ($0.end - $0.start) > ($1.end - $1.start) }
        let long = gs.filter { $0.end - $0.start >= 1.5 }
        print("\n--- \(label) altı kesintiler: \(gs.count) tane, 1,5 sn'yi aşan: \(long.count)")
        for g in gs.prefix(5) {
            let sc = g.scores.isEmpty ? "yüz yok" : String(format: "skor ort %.2f min %.2f", g.scores.reduce(0,+)/Float(g.scores.count), g.scores.min()!)
            print(String(format: "  %.1f sn (%d kare)  yüz izi %@  gövde %@  %@",
                         g.end - g.start, g.n, pct(g.track, g.n), pct(g.body, g.n), sc))
        }
        if let worst = long.max(by: { ($0.end - $0.start) < ($1.end - $1.start) }) {
            let covered = pct(worst.track + (worst.body > worst.track ? worst.body - worst.track : 0), worst.n)
            print(String(format: "  → en uzun yanlış-yokluk %.1f sn; çapa kapsaması %@  %@",
                         worst.end - worst.start, covered,
                         worst.track == worst.n ? "(ÇAPA TUTAR)" : "(ÇAPA DELİK VERİR)"))
        } else {
            print("  → 1,5 sn'yi aşan kesinti yok")
        }
    }

    // Poz: okunabilirlik eşiklerini veriden kalibre etmek için.
    func poseLine(_ name: String, _ set: [PresenceProbe.Sample]) {
        let yaw = set.compactMap(\.yaw), pitch = set.compactMap(\.pitch)
        let rect = set.compactMap(\.rectPitch), q = set.compactMap(\.quality), fs = set.compactMap(\.foreshorten)
        guard !q.isEmpty else { return }
        print("\n[\(name)]  n=\(q.count)")
        print("  yaw            \(stats(yaw))")
        print("  pitch(landmark)\(stats(pitch))")
        print("  pitch(rect r3) \(stats(rect))   ← hepsi 0/boşsa pitch bu makinede YOK")
        print("  kalite         \(stats(q))")
        print("  kısalma        \(stats(fs))   ← aşağı bakınca düşer; pitch yoksa bunu kullanırız")
    }
    print("\n=== POZ (okunabilirlik kalibrasyonu) ===")
    poseLine("tanınan kareler", aboveSustain)
    poseLine("tanınmayan kareler", gapsSamples)
    let unread = gapsSamples.filter { s in
        guard let y = s.yaw, let p = s.pitch, let q = s.quality else { return false }
        return !FaceReadability.isReadable(yaw: y, pitch: p, quality: q)
    }.count
    let withFace = gapsSamples.filter { $0.faces > 0 }.count
    // Kişi maskesi: yüz de gövde de yokken çapayı taşıyacak sinyal.
    let faceless = samples.filter { $0.faces == 0 }
    let masked = faceless.compactMap(\.maskRegion)
    if !masked.isEmpty {
        let carried = masked.filter { $0 >= 0.20 }.count
        print("\n=== KİŞİ MASKESİ (yüz bulunamayan kareler) ===")
        print("yüzsüz kare: \(faceless.count)   maske hesaplanan: \(masked.count)")
        print("sahibin bölgesinde kişi oranı: \(stats(masked))")
        print("kare genelinde:               \(stats(faceless.compactMap(\.maskTotal)))")
        print("0,20 eşiğini geçen (çapa taşınır): \(carried)/\(masked.count) (\(pct(carried, masked.count)))")
        print("  ← yüksek olması İYİ: yüz görünmezken bile 'sahip masada' denir")
    }

    print("\nmevcut eşiklerle \"okunamaz\" sayılan: \(unread)/\(withFace) yüzlü kesinti karesi (\(pct(unread, withFace)))")
}


// MARK: Kaydedilmiş karelerin ölçümü (yanlış alarmın kendi görüntüsü)

/// Kişi maskesi: yüz/gövde dedektörü yakın çekimde profil yüzü kaçırınca
/// "kadrajda insan var mı" sorusunu yöne bağlı olmadan yanıtlar.
func personCoverage(_ handler: VNImageRequestHandler) -> Float? {
    let request = VNGeneratePersonSegmentationRequest()
    request.qualityLevel = .fast
    request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    guard (try? handler.perform([request])) != nil,
          let mask = request.results?.first?.pixelBuffer else { return nil }
    CVPixelBufferLockBaseAddress(mask, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
    let w = CVPixelBufferGetWidth(mask), h = CVPixelBufferGetHeight(mask)
    let stride = CVPixelBufferGetBytesPerRow(mask)
    let p = base.assumingMemoryBound(to: UInt8.self)
    var on = 0
    for y in 0..<h { for x in 0..<w where p[y * stride + x] > 128 { on += 1 } }
    return Float(on) / Float(max(w * h, 1))
}

/// CGImage → CVPixelBuffer: ölçüm, üretimdeki hattın aynısını kullansın diye.
func pixelBuffer(from image: CGImage, context: CIContext) -> CVPixelBuffer? {
    var buffer: CVPixelBuffer?
    let attrs = [kCVPixelBufferCGImageCompatibilityKey: true,
                 kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
    guard CVPixelBufferCreate(nil, image.width, image.height, kCVPixelFormatType_32BGRA, attrs, &buffer) == kCVReturnSuccess,
          let buffer else { return nil }
    context.render(CIImage(cgImage: image), to: buffer)
    return buffer
}

func analyzeSnapshots(embedder: FaceEmbedder, matcher: FaceMatcher?) {
    let dir = SecureFileStore.defaultDirectory()
    guard let keyData = KeychainStore().get(account: "dataKey") else {
        print("Keychain'den veri anahtarı okunamadı."); return
    }
    let store = SecureFileStore(directory: dir, dataKey: SymmetricKey(data: keyData),
                                settingsKey: SymmetricKey(size: .bits256))
    let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        .filter { $0.hasPrefix("snap-") && $0.hasSuffix(".bin") }.sorted()
    guard !names.isEmpty else { print("kayıtlı kare yok"); return }

    let detector = FaceDetector()
    let context = CIContext()
    print("\n=== KAYDEDİLMİŞ YANLIŞ-ALARM KARELERİ (\(names.count) adet) ===")
    var noFace = 0, noFaceNoBody = 0, maskSaves = 0
    var maskValues: [Float] = []
    for name in names {
        guard let data = try? store.readEncrypted(Data.self, from: name),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let buffer = pixelBuffer(from: image, context: context) else {
            print("  \(name): çözülemedi"); continue
        }
        guard let det = try? detector.detect(in: buffer) else { print("  \(name): tespit başarısız"); continue }
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        let coverage = personCoverage(handler) ?? -1
        maskValues.append(coverage)

        let biggest = det.faces.max(by: { $0.boundingBox.height < $1.boundingBox.height })
        var scoreText = "-"
        if let face = biggest, face.landmarks5.count == 5,
           let aligned = FaceCrop.aligned(pixelBuffer: buffer, landmarks: face.landmarks5, context: context),
           let vector = try? embedder.embed(aligned), let m = matcher {
            scoreText = String(format: "%.2f", m.score(vector))
        }
        if det.faces.isEmpty { noFace += 1 }
        if det.faces.isEmpty && det.bodies.isEmpty {
            noFaceNoBody += 1
            if coverage > 0.15 { maskSaves += 1 }
        }
        let ms = Int(Double(name.dropFirst(5).prefix(13)) ?? 0) / 1000
        let time = DateFormatter()
        time.dateFormat = "HH:mm:ss"
        print(String(format: "  %@  yüz=%d gövde=%d  kişi maskesi=%5.1f%%  yaw=%@ kalite=%@ skor=%@",
                     time.string(from: Date(timeIntervalSince1970: TimeInterval(ms))),
                     det.faces.count, det.bodies.count, coverage * 100,
                     biggest.map { String(format: "%+.2f", $0.yaw) } ?? "   -",
                     biggest.map { String(format: "%.2f", $0.quality) } ?? "  -",
                     scoreText))
    }
    print("\nÖZET")
    print("  yüz bulunamayan:            \(noFace)/\(names.count)")
    print("  ne yüz ne gövde (sahne BOŞ sanıldı): \(noFaceNoBody)/\(names.count)")
    print("  bunların kişi maskesiyle kurtulanı:  \(maskSaves)/\(noFaceNoBody)   ← çözümün dayanağı")
    print("  kişi maskesi: \(stats(maskValues))")
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
guard args.count >= 2, ["live", "presence", "snaps"].contains(args[1]) else {
    print("kullanım: nobetci-eval live|presence|snaps [saniye]")
    exit(2)
}
let mode = args[1]
let seconds = args.count >= 3 ? Double(args[2]) ?? 10 : 10

guard let url = modelURL() else { print("model bulunamadı (make model)"); exit(1) }
let embedder = try await FaceEmbedder.load(packageURL: url, cacheDir: nil)
let profile = loadStoredProfile()
let thresholds = Thresholds(accept: 0.70, sustain: 0.55, reject: 0.40)
let faceMatcher = profile.map { FaceMatcher(profile: $0, thresholds: thresholds) }

if mode == "snaps" {
    analyzeSnapshots(embedder: embedder, matcher: faceMatcher)
    exit(0)
}

if mode == "presence" {
    let p = PresenceProbe(embedder: embedder, matcher: faceMatcher)
    print("Kayıtlı profil: \(profile.map { "\($0.count) vektör" } ?? "OKUNAMADI")")
    print("\(Int(seconds)) sn — ÖNEMLİ: sorunu birebir tekrarla.")
    print("  · Süren yarısında telefonunu ALIŞILDIĞI GİBİ TUT ve ona KESİNTİSİZ bak (10+ sn).")
    print("  · Arada burnunu kaşı, elini yüzüne götür, başını çevir.")
    print("  · Masadan KALKMA. Amaç: yanlış \"sahip yok\" anını kameraya yakalatmak.")
    let cam = CameraSource(onFrame: { buffer, _ in p.handle(buffer) }, onInterruption: {})
    try cam.configure()
    cam.start()
    try await Task.sleep(for: .seconds(seconds))
    cam.stop()
    reportPresence(p.samples, thresholds: thresholds)
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
