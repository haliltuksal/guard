import Foundation

/// Sahip izinin o anki durumu. `recognizedFrameCount`, son ~1 sn içinde sahip
/// olarak eşleşen kare sayısı; `present`, izin hâlâ canlı olduğu.
public struct OwnerTrackState: Equatable, Sendable {
    public var recognizedFrameCount: Int
    public var present: Bool
    public init(recognizedFrameCount: Int, present: Bool) {
        self.recognizedFrameCount = recognizedFrameCount
        self.present = present
    }
}

/// Görüntü hattının her kare için ürettiği özet (spec §6). Çekirdek yalnızca bu
/// özeti görür; ham görüntüye hiç dokunmaz. Değerler sahibe göre normalleştirilmiştir:
/// `strangerFacePresent`/`bodyPresentBeyondThreshold` sahibin kendisini saymaz.
public struct FrameSummary: Equatable, Sendable {
    public var ownerTrack: OwnerTrackState?
    /// Sahibin kimlik çapası canlı mı: aynı iz görülmeye devam ediyor ya da sahne
    /// hiç boşalmadı. Yüz okunmasa bile "sahip masada" demektir (bkz `OwnerAnchor`).
    public var ownerAnchored: Bool
    public var strangerFacePresent: Bool
    public var uncertainFacePresent: Bool
    public var bodyPresentBeyondThreshold: Bool
    public var anyPersonPresent: Bool
    /// Son kırpmadan bu yana geçen saniye; hiç kırpma yoksa nil.
    public var blinkObservedWithin: TimeInterval?
    public var strictGestureSatisfied: Bool
    public var ownerQualityOK: Bool
    /// Sahnenin kesintisiz boş kaldığı süre (saniye).
    public var sceneEmptyFor: TimeInterval
    public var timestamp: TimeInterval

    public init(
        ownerTrack: OwnerTrackState? = nil,
        ownerAnchored: Bool = false,
        strangerFacePresent: Bool = false,
        uncertainFacePresent: Bool = false,
        bodyPresentBeyondThreshold: Bool = false,
        anyPersonPresent: Bool = false,
        blinkObservedWithin: TimeInterval? = nil,
        strictGestureSatisfied: Bool = false,
        ownerQualityOK: Bool = false,
        sceneEmptyFor: TimeInterval = .greatestFiniteMagnitude,
        timestamp: TimeInterval = 0
    ) {
        self.ownerTrack = ownerTrack
        self.ownerAnchored = ownerAnchored
        self.strangerFacePresent = strangerFacePresent
        self.uncertainFacePresent = uncertainFacePresent
        self.bodyPresentBeyondThreshold = bodyPresentBeyondThreshold
        self.anyPersonPresent = anyPersonPresent
        self.blinkObservedWithin = blinkObservedWithin
        self.strictGestureSatisfied = strictGestureSatisfied
        self.ownerQualityOK = ownerQualityOK
        self.sceneEmptyFor = sceneEmptyFor
        self.timestamp = timestamp
    }

    public static var empty: FrameSummary { FrameSummary() }
}
