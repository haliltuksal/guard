import Testing
@testable import NobetciVision

@Test func facenetNormalizationMapsRange() {
    // (p·255 − 127.5)/128: siyah → ~−0.996, orta gri → ~0, beyaz → ~0.996
    #expect(abs(FaceEmbedder.normalize(0.0) - (-127.5 / 128)) < 1e-6)
    #expect(abs(FaceEmbedder.normalize(0.5) - ((0.5 * 255 - 127.5) / 128)) < 1e-6)
    #expect(FaceEmbedder.normalize(1.0) > 0.99 && FaceEmbedder.normalize(1.0) < 1.0)
}
