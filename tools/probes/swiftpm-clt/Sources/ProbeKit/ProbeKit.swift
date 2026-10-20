public func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    precondition(a.count == b.count)
    var dot: Float = 0, na: Float = 0, nb: Float = 0
    for i in a.indices {
        dot += a[i] * b[i]
        na += a[i] * a[i]
        nb += b[i] * b[i]
    }
    return dot / (na.squareRoot() * nb.squareRoot())
}
