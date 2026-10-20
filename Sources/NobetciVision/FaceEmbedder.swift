import CoreML
import CoreGraphics
import Foundation

/// Hizalanmış yüzü Core ML modeliyle 512-boyutlu, L2-normalize gömmeye çevirir.
/// Model `.mlpackage` olarak paketlenir ve ilk kullanımda `MLModel.compileModel`
/// ile çalışma anında derlenir (V10; Xcode/coremlcompiler gerekmez), Neural Engine'de koşar.
public final class FaceEmbedder {
    public static let inputSize = 160
    private let model: MLModel

    public init(model: MLModel) { self.model = model }

    /// `.mlpackage`'ı derler (sonucu önbelleğe alıp tekrar kullanılabilir) ve modeli yükler.
    public static func load(packageURL: URL, cacheDir: URL? = nil) async throws -> FaceEmbedder {
        let compiled: URL
        if let cacheDir, let existing = cachedCompiledModel(in: cacheDir) {
            compiled = existing
        } else {
            let fresh = try await MLModel.compileModel(at: packageURL)
            compiled = try persist(compiled: fresh, to: cacheDir) ?? fresh
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        return FaceEmbedder(model: try MLModel(contentsOf: compiled, configuration: config))
    }

    /// FaceNet normalizasyonu: [0,1] piksel → (p·255 − 127.5)/128.
    public static func normalize(_ pixel: Float) -> Float { (pixel * 255 - 127.5) / 128 }

    public func embed(_ image: CGImage) throws -> [Float] {
        let array = try Self.multiArray(from: image)
        let provider = try MLDictionaryFeatureProvider(dictionary: ["input": array])
        guard let out = try model.prediction(from: provider).featureValue(for: "embedding")?.multiArrayValue else {
            throw EmbedderError.noOutput
        }
        var v = [Float](repeating: 0, count: out.count)
        for i in 0..<out.count { v[i] = out[i].floatValue }
        let norm = v.map { $0 * $0 }.reduce(0, +).squareRoot()
        return norm > 0 ? v.map { $0 / norm } : v
    }

    static func multiArray(from image: CGImage) throws -> MLMultiArray {
        let size = inputSize
        let array = try MLMultiArray(shape: [1, 3, NSNumber(value: size), NSNumber(value: size)], dataType: .float32)
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: size * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw EmbedderError.contextFailed
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
        let plane = size * size
        for y in 0..<size {
            for x in 0..<size {
                let p = (y * size + x) * 4
                let idx = y * size + x
                ptr[0 * plane + idx] = normalize(Float(pixels[p]) / 255)       // R
                ptr[1 * plane + idx] = normalize(Float(pixels[p + 1]) / 255)   // G
                ptr[2 * plane + idx] = normalize(Float(pixels[p + 2]) / 255)   // B
            }
        }
        return array
    }

    private static func cachedCompiledModel(in dir: URL) -> URL? {
        let url = dir.appendingPathComponent("Model.mlmodelc")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func persist(compiled: URL, to dir: URL?) throws -> URL? {
        guard let dir else { return nil }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("Model.mlmodelc")
        if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
        try FileManager.default.copyItem(at: compiled, to: dest)
        return dest
    }
}

public enum EmbedderError: Error, Sendable { case noOutput, contextFailed }
