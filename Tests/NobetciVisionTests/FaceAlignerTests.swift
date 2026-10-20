import Testing
import CoreGraphics
@testable import NobetciVision

private func apply(_ t: CGAffineTransform, _ p: CGPoint) -> CGPoint { p.applying(t) }

@Test func recoversKnownSimilarityTransform() {
    // Bilinen benzerlik dönüşümü: ölçek 2, 30° dönme, öteleme (10, -5).
    let scale = 2.0, theta = Double.pi / 6
    let a = scale * cos(theta), b = scale * sin(theta)
    let known = CGAffineTransform(a: a, b: b, c: -b, d: a, tx: 10, ty: -5)
    let src = [CGPoint(x: 30, y: 50), CGPoint(x: 73, y: 51),
               CGPoint(x: 56, y: 71), CGPoint(x: 41, y: 92), CGPoint(x: 70, y: 92)]
    let dst = src.map { apply(known, $0) }

    let recovered = FaceAligner.similarityTransform(from: src, to: dst)
    for p in src {
        let got = apply(recovered, p), want = apply(known, p)
        #expect(abs(got.x - want.x) < 1e-6 && abs(got.y - want.y) < 1e-6)
    }
}

@Test func templateHasFivePointsScaledToSize() {
    let t = FaceAligner.canonicalTemplate(size: 160)
    #expect(t.count == 5)
    #expect(t.allSatisfy { $0.x >= 0 && $0.x <= 160 && $0.y >= 0 && $0.y <= 160 })
}
