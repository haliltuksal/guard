import Foundation

/// Küçültülmüş gri ölçekli kareden ucuz metrikler: hareket enerjisi (önceki kareye
/// göre), ortalama parlaklık ve doku (varyans). Uyarlanır analiz hızı ve sahne
/// sağlığı (T6 karanlık/örtülü) bunlardan beslenir. Saf; pikselleri çağıran verir.
public struct FrameMetrics: Equatable, Sendable {
    public var motionEnergy: Float
    public var brightness: Float
    public var texture: Float
}

public struct FrameAnalyzer {
    private var previous: [Float]?
    public init() {}

    public mutating func analyze(gray: [Float]) -> FrameMetrics {
        let n = gray.isEmpty ? 1 : Float(gray.count)
        let brightness = gray.reduce(0, +) / n
        var variance: Float = 0
        for v in gray { let d = v - brightness; variance += d * d }
        variance /= n

        var motion: Float = 0
        if let prev = previous, prev.count == gray.count {
            var acc: Float = 0
            for i in gray.indices { acc += abs(gray[i] - prev[i]) }
            motion = acc / n
        }
        previous = gray
        return FrameMetrics(motionEnergy: motion, brightness: brightness, texture: variance)
    }
}
