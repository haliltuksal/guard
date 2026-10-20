import Testing
import CoreGraphics
@testable import NobetciVision

/// Kayıt ve çalışma anı AYNI hizalama dönüşümünü kullanmalı ve bu dönüşüm geometrik
/// olarak doğru olmalı: piksel (y-aşağı) landmark → şablon → çıktı CIImage (y-yukarı).
/// Çevirmeyi unutan bir uygulama (eski EnrollmentSession) bu testi geçemez.
@Test func composedTransformMapsPixelLandmarksOntoTemplateInCIOutputSpace() {
    let imageH: CGFloat = 720, size: CGFloat = 160
    let template = FaceAligner.canonicalTemplate(size: size)
    // Landmark'lar: şablonun 3× büyütülüp (200, 150) ötelenmiş hali, piksel (y-aşağı) uzayında.
    let landmarks = template.map { CGPoint(x: $0.x * 3 + 200, y: $0.y * 3 + 150) }

    let t = FaceCrop.ciTransform(landmarks: landmarks, imageHeight: imageH, outputSize: size)

    for (lm, tp) in zip(landmarks, template) {
        let ciPoint = CGPoint(x: lm.x, y: imageH - lm.y)           // aynı nokta CIImage (y-yukarı) uzayında
        let out = ciPoint.applying(t)
        let expected = CGPoint(x: tp.x, y: size - tp.y)            // şablon noktası çıktı CI uzayında
        #expect(abs(out.x - expected.x) < 1e-6 && abs(out.y - expected.y) < 1e-6)
    }
}

@Test func plainTransformWithoutFlipsIsWrong() {
    // Regresyon: çevirmesiz "düz" dönüşüm (eski kayıt kodu) landmark'ı şablona oturtamaz.
    let imageH: CGFloat = 720, size: CGFloat = 160
    let template = FaceAligner.canonicalTemplate(size: size)
    let landmarks = template.map { CGPoint(x: $0.x * 3 + 200, y: $0.y * 3 + 150) }
    let plain = FaceAligner.similarityTransform(from: landmarks, to: template)
    let ciPoint = CGPoint(x: landmarks[0].x, y: imageH - landmarks[0].y)
    let out = ciPoint.applying(plain)
    let expected = CGPoint(x: template[0].x, y: size - template[0].y)
    #expect(abs(out.y - expected.y) > 1)   // dikey eksende belirgin hata
}
