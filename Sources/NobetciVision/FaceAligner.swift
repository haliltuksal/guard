import CoreGraphics
import Foundation

/// Yüz hizalama: tespit edilen 5 nokta (iki göz, burun, iki ağız köşesi) kanonik
/// şablona benzerlik dönüşümüyle oturtulur, sonra görüntü modelin beklediği boyuta
/// örneklenir. Dönüşüm 2B Procrustes kapalı formu (ölçek + dönme + öteleme).
public enum FaceAligner {
    /// ArcFace 112×112 referans 5 noktası; istenen boyuta ölçeklenir.
    private static let base112: [CGPoint] = [
        CGPoint(x: 38.2946, y: 51.6963),  // sol göz
        CGPoint(x: 73.5318, y: 51.5014),  // sağ göz
        CGPoint(x: 56.0252, y: 71.7366),  // burun
        CGPoint(x: 41.5493, y: 92.3655),  // sol ağız köşesi
        CGPoint(x: 70.7299, y: 92.2041),  // sağ ağız köşesi
    ]

    public static func canonicalTemplate(size: CGFloat) -> [CGPoint] {
        let k = size / 112.0
        return base112.map { CGPoint(x: $0.x * k, y: $0.y * k) }
    }

    /// `from` noktalarını `to` noktalarına en küçük kareler anlamında eşleyen
    /// benzerlik dönüşümü (üniform ölçek + dönme + öteleme). Nokta sayıları eşit olmalı.
    public static func similarityTransform(from src: [CGPoint], to dst: [CGPoint]) -> CGAffineTransform {
        precondition(src.count == dst.count && !src.isEmpty)
        let n = CGFloat(src.count)
        let meanS = src.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x / n, y: $0.y + $1.y / n) }
        let meanD = dst.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x / n, y: $0.y + $1.y / n) }

        var sxx: CGFloat = 0  // Σ(x²+y²) merkezlenmiş kaynak
        var sa: CGFloat = 0   // Σ(x·X + y·Y)
        var sb: CGFloat = 0   // Σ(x·Y − y·X)
        for i in src.indices {
            let x = src[i].x - meanS.x, y = src[i].y - meanS.y
            let X = dst[i].x - meanD.x, Y = dst[i].y - meanD.y
            sxx += x * x + y * y
            sa += x * X + y * Y
            sb += x * Y - y * X
        }
        let a = sa / sxx          // scale·cosθ
        let b = sb / sxx          // scale·sinθ
        let tx = meanD.x - (a * meanS.x - b * meanS.y)
        let ty = meanD.y - (b * meanS.x + a * meanS.y)
        // CGAffineTransform: X = a·x + c·y + tx, Y = b·x + d·y + ty  → c = −b, d = a.
        return CGAffineTransform(a: a, b: b, c: -b, d: a, tx: tx, ty: ty)
    }
}
