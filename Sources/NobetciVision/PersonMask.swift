import CoreGraphics
import Foundation

/// Kişi bölütleme maskesi (Vision `VNGeneratePersonSegmentationRequest`, `.fast`).
///
/// Neden var: yüz dedektörü profil, aşağı bakan ya da elle kapanan yüzü kaçırır; üst
/// gövde dedektörü ise yakın oturan kullanıcıda hiç tetiklenmez (cihazda ölçüldü:
/// tanınmayan 8 karenin 8'inde gövde yok). İkisi de susunca sahne "boş" sanılıyor ve
/// sahip masasında otururken kilit, yanlış fotoğraf ve "kamera kaydı" alarmı üretiliyordu.
/// Maske insanı yöne bakmadan görür.
///
/// Koordinatlar Vision düzenindedir: sol-alt başlangıçlı, 0…1 normalleştirilmiş.
public struct PersonMask: Sendable {
    public let values: [UInt8]
    public let width: Int
    public let height: Int
    /// Bu eşiğin üstündeki piksel "kişi" sayılır (maske 0…255 güven değeri verir).
    public static let pixelThreshold: UInt8 = 128

    public init(values: [UInt8], width: Int, height: Int) {
        self.values = values
        self.width = width
        self.height = height
    }

    /// Kare genelinde kişi piksellerinin oranı.
    public var total: Float { coverage(in: CGRect(x: 0, y: 0, width: 1, height: 1)) }

    /// Verilen normalleştirilmiş bölgede kişi piksellerinin oranı.
    public func coverage(in rect: CGRect) -> Float {
        guard width > 0, height > 0, !values.isEmpty else { return 0 }
        let clamped = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clamped.isNull, clamped.width > 0, clamped.height > 0 else { return 0 }

        let x0 = max(0, Int((clamped.minX * CGFloat(width)).rounded(.down)))
        let x1 = min(width, max(x0 + 1, Int((clamped.maxX * CGFloat(width)).rounded(.up))))
        // Vision y'si yukarı artar; satır dizisi yukarıdan aşağıya. Satırı çevir.
        let yTop = max(0, Int(((1 - clamped.maxY) * CGFloat(height)).rounded(.down)))
        let yBottom = min(height, max(yTop + 1, Int(((1 - clamped.minY) * CGFloat(height)).rounded(.up))))

        var on = 0, seen = 0
        for y in yTop..<yBottom {
            let row = y * width
            for x in x0..<x1 {
                seen += 1
                if values[row + x] > Self.pixelThreshold { on += 1 }
            }
        }
        return seen > 0 ? Float(on) / Float(seen) : 0
    }

    /// Sahibin son görüldüğü yüz kutusundan, gövdeyi de kapsayan bölge.
    ///
    /// Bölgeyle sınırlamak önemlidir: odadaki sandalyeye asılı bir mont ya da arkadan
    /// geçen biri maskeyi doldurabilir. Soru "kadrajda biri var mı" değil, **"sahibin
    /// bulunduğu yerde hâlâ biri var mı"**dır.
    public static func ownerRegion(faceBox: CGRect) -> CGRect {
        let width = min(1, faceBox.width * 2.2)                 // omuzlar yüzden geniş
        let x = min(max(0, faceBox.midX - width / 2), 1 - width)
        let top = min(1, faceBox.maxY + faceBox.height * 0.2)   // saç/baş üstü payı
        return CGRect(x: x, y: 0, width: width, height: top)    // gövde aşağıya iner
    }
}
