import CoreGraphics
import Foundation

/// Yüz kesitini gömmeden önce aynı aydınlığa çeker.
///
/// Kök neden (cihazda, 2026-10-21 17:16): karanlık odada, arkada parlak monitör varken
/// kamera pozlaması yüzü koyu bırakıyor. Gündüz kaydedilmiş profille karşılaştırılan bu
/// koyu kesit eşiği geçemiyor; sahip tanınmıyor, "kadrajdaki yabancı" sayılıyordu.
///
/// Çözüm, kesitin luma ortalamasını ve kontrastını sabit bir hedefe çekmek. `FaceCrop`
/// tek hat olduğu için kayıt, çalışma anı ve değerlendirme aynı işlemden geçer — profil
/// ile canlı yüz arasında yeni bir uyumsuzluk doğmaz.
public enum ExposureNormalizer {
    public static let targetMean: Float = 0.45
    public static let targetStd: Float = 0.22
    /// Düz/karanlık kesitte kazancı sınırla: yoksa gürültü yüz gibi görünecek kadar büyür.
    public static let maxGain: Float = 4.0
    public static let minStd: Float = 0.02

    public static func luma(r: UInt8, g: UInt8, b: UInt8) -> Float {
        (0.2126 * Float(r) + 0.7152 * Float(g) + 0.0722 * Float(b)) / 255
    }

    /// RGBA8 dizisini yerinde normalleştirir; alfa korunur.
    public static func normalize(rgba: inout [UInt8]) {
        let pixels = rgba.count / 4
        guard pixels > 0 else { return }

        var sum: Float = 0, sumSq: Float = 0
        for i in stride(from: 0, to: pixels * 4, by: 4) {
            let y = luma(r: rgba[i], g: rgba[i + 1], b: rgba[i + 2])
            sum += y
            sumSq += y * y
        }
        let mean = sum / Float(pixels)
        let variance = max(0, sumSq / Float(pixels) - mean * mean)
        let std = max(variance.squareRoot(), minStd)
        let gain = min(targetStd / std, maxGain)
        let offset = targetMean - mean * gain

        for i in stride(from: 0, to: pixels * 4, by: 4) {
            for c in 0..<3 {
                let v = Float(rgba[i + c]) / 255
                let out = v * gain + offset
                rgba[i + c] = UInt8(max(0, min(255, (out * 255).rounded())))
            }
        }
    }

    /// Kesiti normalleştirilmiş bir kopyayla döndürür; dönüştürülemezse nil.
    public static func normalized(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = rgba.withUnsafeMutableBytes({ buffer -> CGContext? in
            guard let base = buffer.baseAddress else { return nil }
            return CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                             bytesPerRow: width * 4, space: space, bitmapInfo: info)
        }) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        normalize(rgba: &rgba)

        guard let out = rgba.withUnsafeMutableBytes({ buffer -> CGContext? in
            guard let base = buffer.baseAddress else { return nil }
            return CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                             bytesPerRow: width * 4, space: space, bitmapInfo: info)
        })?.makeImage() else { return nil }
        return out
    }
}
