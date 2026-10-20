import Testing
@testable import ProbeKit

@Test func identicalVectorsHaveSimilarityOne() {
    #expect(abs(cosineSimilarity([0.3, 0.4], [0.3, 0.4]) - 1) < 1e-6)
}

@Test func orthogonalVectorsHaveSimilarityZero() {
    #expect(abs(cosineSimilarity([1, 0], [0, 1])) < 1e-6)
}
