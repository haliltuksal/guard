import CoreGraphics
import Foundation

/// Ardışık karelerde kutuları IoU ile eşleyerek kimlik (iz) sürdürür. Çekirdeğin
/// "sahip izi" ve "kişi izi" kavramları bunun üstüne kurulur.
public struct Track: Equatable, Sendable {
    public let id: Int
    public var box: CGRect
    public let firstSeen: TimeInterval
    public var lastSeen: TimeInterval
    public var frameCount: Int
}

public struct TrackManager {
    public static let iouThreshold: CGFloat = 0.3
    public static let expiry: TimeInterval = 1.0

    private var tracks: [Track] = []
    private var nextID = 0
    public init() {}

    public mutating func update(boxes: [CGRect], now: TimeInterval) -> [Track] {
        var matchedTrackIndices = Set<Int>()
        for box in boxes {
            // En iyi IoU'lu, henüz eşleşmemiş izi bul.
            var bestIndex: Int?
            var bestIoU = Self.iouThreshold
            for (i, t) in tracks.enumerated() where !matchedTrackIndices.contains(i) {
                let iou = Self.iou(t.box, box)
                if iou >= bestIoU { bestIoU = iou; bestIndex = i }
            }
            if let i = bestIndex {
                matchedTrackIndices.insert(i)
                tracks[i].box = box
                tracks[i].lastSeen = now
                tracks[i].frameCount += 1
            } else {
                tracks.append(Track(id: nextID, box: box, firstSeen: now, lastSeen: now, frameCount: 1))
                matchedTrackIndices.insert(tracks.count - 1)
                nextID += 1
            }
        }
        // Süresi dolmuş izleri at.
        tracks.removeAll { now - $0.lastSeen > Self.expiry }
        return tracks
    }

    static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        if inter.isNull || inter.isEmpty { return 0 }
        let interArea = inter.width * inter.height
        let union = a.width * a.height + b.width * b.height - interArea
        return union > 0 ? interArea / union : 0
    }
}
