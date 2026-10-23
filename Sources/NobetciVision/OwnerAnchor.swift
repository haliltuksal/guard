import CoreGraphics
import Foundation

/// Sahip kimliğinin **çapası**: kimlik kare kare tanımaya değil, kesintisiz ize dayanır.
///
/// Kök neden (cihazda ölçüldü, 2026-10-21): varlık yalnızca "bu karede yüz eşleşti mi"
/// sorusuna bağlıydı. Telefona bakmak, burun kaşımak, başı çevirmek yüzü bir-iki saniye
/// okunamaz yapar; eski mantık bunu "masadan kalktı" sayıp girdi gelince kilitliyor,
/// sahibin kendi yüzünü "yaklaşan yabancı" diye fotoğraflıyordu.
///
/// Çapa üç kademeyle yaşar:
/// 1. **Tanıma** — yüz eşleşti: çapa bu ize bağlanır (en güçlü kanıt).
/// 2. **İz** — aynı iz görülmeye devam ediyor, tanınmasa bile: sahip hâlâ orada.
/// 3. **Taşıma** — yüz hiç görünmüyor ama sahne boşalmadı: `carryLimit`'e kadar sürer.
///
/// Çapa yalnızca sahne gerçekten boşalınca, okunabilir bir yabancı yüz sahibin izine
/// oturunca ya da üst sınır dolunca düşer.
public struct OwnerAnchor: Sendable, Equatable {
    /// İz koptuktan sonra aynı yerde beliren yüzü sahibin devamı saymak için pencere
    /// (el yüzü kapatır, kafa bir an kadrajdan çıkar). Çapanın yüzsüz yaşama süresi de budur.
    public static let rebindWindow: TimeInterval = 1.5
    /// Yeniden bağlanma için en az kutu örtüşmesi (IoU). Kafa bu sürede biraz kayar.
    public static let rebindIoU: CGFloat = 0.2
    /// Yüz hiç görünmezken sahnenin dolu olmasıyla çapanın taşınabileceği üst sınır.
    /// Sonsuz değil: yüzünü hiç göstermeyen birinin sahipten sayılması sınırlı kalsın.
    public static let carryLimit: TimeInterval = 600
    /// Sahibin izinde okunabilir ve "kesin yabancı" skorlu yüz bu kadar sürerse çapa düşer.
    /// Gerçek koltuk değişimi sürer; duman, el ya da kupa tek tük kare üretir.
    public static let contradictionPersistence: TimeInterval = 1.5

    public private(set) var trackID: Int?
    public private(set) var box: CGRect = .zero
    /// Sahip izinin (tanınsın ya da tanınmasın) en son görüldüğü an.
    public private(set) var lastSeen: TimeInterval = -.greatestFiniteMagnitude
    /// Yüzün en son gerçekten tanındığı an — taşıma üst sınırı buradan sayılır.
    public private(set) var lastVerified: TimeInterval = -.greatestFiniteMagnitude
    /// Çelişkinin (sahip izinde okunabilir yabancı skor) başladığı an; yoksa nil.
    private var contradictionSince: TimeInterval?

    public init() {}

    public var isSet: Bool { trackID != nil }

    /// Çapa hâlâ geçerli mi? (son görülmeden bu yana `rebindWindow` geçmediyse)
    public func isAlive(now: TimeInterval) -> Bool {
        trackID != nil && now - lastSeen <= Self.rebindWindow
    }

    /// Sahip bu karede tanındı: çapayı bu ize bağla (en güçlü kanıt).
    public mutating func verify(trackID id: Int, box b: CGRect, now: TimeInterval) {
        contradictionSince = nil
        trackID = id
        box = b
        lastSeen = now
        lastVerified = now
    }

    /// Sahip izi bu karede de görüldü ama tanınmadı (kötü açı, örtünme): çapayı yaşat.
    public mutating func sustain(box b: CGRect, now: TimeInterval) {
        guard trackID != nil else { return }
        box = b
        lastSeen = now
    }

    /// Kopan izin ardından aynı yerde beliren yüz, sahibin devamı sayılabilir mi?
    public func canRebind(to candidate: CGRect, now: TimeInterval) -> Bool {
        guard trackID != nil, now - lastSeen <= Self.rebindWindow else { return false }
        return TrackManager.iou(box, candidate) >= Self.rebindIoU
    }

    /// Kadrajda tek yüz varken, kutu çok kaymış olsa da (masada bir şeye uzanmak, öne
    /// eğilmek) o yüz sahibin devamı sayılabilir: rakip aday yok ve sahne boşalmadı.
    /// Tanıma yerine geçmez — yalnızca varlığı sürdürür; okunabilir bir yabancı yüz
    /// yine de çapayı düşürür (bkz `VisionPipeline`).
    public func canAdoptSoleFace(faceCount: Int, now: TimeInterval) -> Bool {
        trackID != nil && faceCount == 1 && now - lastSeen <= Self.rebindWindow
    }

    /// Kopan izi yeni iz kimliğiyle devam ettir (tanıma şartı yok; konum sürekliliği kanıt).
    public mutating func rebind(trackID id: Int, box b: CGRect, now: TimeInterval) {
        guard trackID != nil else { return }
        self.trackID = id
        box = b
        lastSeen = now
    }

    /// Yüz hiç görünmüyor ama sahnede biri var: çapayı taşı. Üst sınır dolduysa düşür.
    @discardableResult
    public mutating func carry(now: TimeInterval) -> Bool {
        guard trackID != nil else { return false }
        guard now - lastVerified <= Self.carryLimit else { drop(); return false }
        lastSeen = now
        return true
    }

    /// Sahibin izinde okunabilir ama "kesin yabancı" skorlu bir kare görüldü. Çelişki
    /// `contradictionPersistence` boyunca sürdüyse `true` döner: çapa düşürülmeli.
    /// Sürmediyse çapayı yaşatır (tek kareyle karar verilmez).
    public mutating func noteContradiction(now: TimeInterval) -> Bool {
        let since = contradictionSince ?? now
        contradictionSince = since
        if now - since >= Self.contradictionPersistence { return true }
        lastSeen = now
        return false
    }

    /// Sahibin izi yeniden normal okundu (tanındı ya da okunamadı ama çelişmedi).
    public mutating func clearContradiction() {
        contradictionSince = nil
    }

    public mutating func drop() {
        contradictionSince = nil
        trackID = nil
        box = .zero
        lastSeen = -.greatestFiniteMagnitude
        lastVerified = -.greatestFiniteMagnitude
    }
}

/// Yüzün kimlik kararına elverişli olup olmadığı.
///
/// İlke: **okunamayan yüzden kimlik kararı çıkarılmaz.** Dik açıdan ya da bulanık
/// görülen bir yüz ne "sahip" ne "yabancı"dır; yalnızca okunamamıştır. Eski kod bu
/// ayrımı yapmadığı için sahibin telefona bakan yüzü "yabancı" sayılabiliyordu.
///
/// Eşikler cihazda ölçülerek doğrulanır: `swift run nobetci-eval presence 30`
/// çıktısındaki yaw/pitch/kalite dağılımı bu değerleri kalibre eder.
public enum FaceReadability {
    /// Radyan. ~40°: FaceNet/VGGFace2 bu açıdan sonra güvenilir ayırt edemez.
    public static let maxYaw: Float = 0.70
    /// Radyan. ~29°: telefona bakma tipik olarak bunun çok ötesinde.
    public static let maxPitch: Float = 0.50
    /// Vision yakalama kalitesi tabanı (gece webcam'de 0,30–0,55 ölçüldü).
    public static let minQuality: Float = 0.15

    public static func isReadable(yaw: Float, pitch: Float, quality: Float) -> Bool {
        abs(yaw) <= maxYaw && abs(pitch) <= maxPitch && quality >= minQuality
    }
}
