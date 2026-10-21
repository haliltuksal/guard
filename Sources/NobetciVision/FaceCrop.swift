import CoreGraphics
import CoreImage
import CoreVideo

/// Yüz kesiti: tespit edilen 5 landmark'ı (piksel, y-aşağı) kanonik şablona oturtan
/// TEK dönüşüm. Kayıt (enrollment), çalışma anı (pipeline) ve değerlendirme aracı
/// bunu kullanır. Bunun iki ayrı uygulaması profil ile canlı yüz arasında geometrik
/// uyumsuzluk yaratmış, sahip tanınmaz olmuştu — bir daha ayrışmasın.
public enum FaceCrop {
    /// Kesit hattının sürümü. Ön işleme değişince (ör. pozlama normalleştirme eklenince)
    /// artar; eski sürümle kaydedilmiş profil artık birebir uyumlu değildir, kullanıcıdan
    /// yüz profilini yenilemesi istenir. Sessiz uyumsuzluk bir kez "tanımıyor" hatasına
    /// yol açmıştı; bir daha sessiz kalmasın.
    public static let pipelineVersion = 2

    /// CIImage (y-yukarı) uzayında uygulanacak bileşik dönüşüm:
    /// CI → piksel (çevir) → benzerlik (landmark→şablon, y-aşağı) → çıktı CI (çevir).
    public static func ciTransform(landmarks: [CGPoint], imageHeight: CGFloat, outputSize: CGFloat) -> CGAffineTransform {
        let template = FaceAligner.canonicalTemplate(size: outputSize)
        let similarity = FaceAligner.similarityTransform(from: landmarks, to: template)
        let flipIn = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: imageHeight)  // CI y-yukarı → piksel y-aşağı
        let flipOut = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: outputSize)  // şablon y-aşağı → CI y-yukarı
        return flipIn.concatenating(similarity).concatenating(flipOut)
    }

    /// Hizalanmış `outputSize`×`outputSize` yüz görüntüsü; 5 landmark yoksa nil.
    public static func aligned(pixelBuffer: CVPixelBuffer, landmarks: [CGPoint], context: CIContext,
                               outputSize: CGFloat = CGFloat(FaceEmbedder.inputSize)) -> CGImage? {
        guard landmarks.count == 5 else { return nil }
        let imageHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let transform = ciTransform(landmarks: landmarks, imageHeight: imageHeight, outputSize: outputSize)
        let image = CIImage(cvPixelBuffer: pixelBuffer).transformed(by: transform)
        guard let crop = context.createCGImage(image, from: CGRect(x: 0, y: 0, width: outputSize, height: outputSize))
        else { return nil }
        // Pozlama normalleştirme: karanlık oda / arkadan ışık yüzü koyu bırakıyor ve
        // gündüz kaydedilmiş profille eşleşmiyordu. Kayıt ve çalışma anı aynı hattan
        // geçtiği için profil ile canlı yüz tutarlı kalır.
        return ExposureNormalizer.normalized(crop) ?? crop
    }
}
