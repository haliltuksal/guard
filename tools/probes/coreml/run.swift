import CoreML
import Foundation

// Probe: compile an .mlpackage at runtime (no Xcode / coremlcompiler) and run it on each compute unit.
let packageURL = URL(fileURLWithPath: "Probe.mlpackage")
let compiledURL = try await MLModel.compileModel(at: packageURL)
print("Compiled at runtime:", compiledURL.lastPathComponent)

let input = try MLMultiArray(shape: [1, 3, 112, 112], dataType: .float32)
for i in 0..<input.count { input[i] = NSNumber(value: Float.random(in: 0...1)) }
let features = try MLDictionaryFeatureProvider(dictionary: ["input": input])

for (name, units) in [("cpuOnly", MLComputeUnits.cpuOnly), ("cpuAndGPU", .cpuAndGPU), ("cpuAndNeuralEngine", .cpuAndNeuralEngine), ("all", .all)] {
    let configuration = MLModelConfiguration()
    configuration.computeUnits = units
    let model = try MLModel(contentsOf: compiledURL, configuration: configuration)
    _ = try model.prediction(from: features) // warm-up
    let start = Date()
    let runs = 50
    var output: MLMultiArray?
    for _ in 0..<runs { output = try model.prediction(from: features).featureValue(for: "embedding")?.multiArrayValue }
    let ms = Date().timeIntervalSince(start) / Double(runs) * 1000
    print(String(format: "%-20@ %.3f ms/inference, output shape %@", name as NSString, ms, output?.shape.description ?? "nil"))
}
