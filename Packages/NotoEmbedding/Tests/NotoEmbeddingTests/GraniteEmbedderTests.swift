import Foundation
import Testing
@testable import NotoEmbedding

/// Test case index
/// 1. goldenVectorsMatchPythonReference — Swift tokenize→CoreML pipeline matches the Mac
///    coremltools int8 run (cos ≥ 0.9995) and the PyTorch fp32 reference (cos ≥ 0.999)
///    on 8 EN/ZH/JA/mixed fixtures (SC7)
/// 2. embeddingsAreNormalizedAndDeterministic — unit norm; identical text → identical vector (SC7)
/// 3. longTextTruncatesWithoutError — multi-thousand-token input embeds fine (SC7)
/// 4. constantsMatchModelContract — 384 dims, version string stability (SC7)
@Suite(.serialized)
struct GraniteEmbedderTests {
    private struct GoldenCase: Decodable {
        let id: String
        let text: String
        let ref_torch: [Float]
        let ref_mac_int8: [Float]
    }

    /// Model load (+ mlpackage compile under `swift test`) is expensive; share one instance.
    private static let shared: GraniteEmbedder = {
        do {
            return try GraniteEmbedder.bundled()
        } catch {
            fatalError("GraniteEmbedder.bundled() failed: \(error)")
        }
    }()

    private func cosine(_ a: [Float], _ b: [Float]) -> Double {
        var dot = 0.0, na = 0.0, nb = 0.0
        for index in 0..<min(a.count, b.count) {
            dot += Double(a[index]) * Double(b[index])
            na += Double(a[index]) * Double(a[index])
            nb += Double(b[index]) * Double(b[index])
        }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    @Test func goldenVectorsMatchPythonReference() throws {
        let url = try #require(Bundle.module.url(forResource: "embed_golden", withExtension: "json"))
        let cases = try JSONDecoder().decode([GoldenCase].self, from: Data(contentsOf: url))
        #expect(cases.count == 8)

        let vectors = try Self.shared.embed(cases.map(\.text))
        for (vector, goldenCase) in zip(vectors, cases) {
            let cosMac = cosine(vector, goldenCase.ref_mac_int8)
            let cosTorch = cosine(vector, goldenCase.ref_torch)
            #expect(cosMac >= 0.9995, "case \(goldenCase.id): cos vs Mac int8 run = \(cosMac)")
            #expect(cosTorch >= 0.999, "case \(goldenCase.id): cos vs torch fp32 ref = \(cosTorch)")
        }
    }

    @Test func embeddingsAreNormalizedAndDeterministic() throws {
        let text = "Notes about the quarterly budget review meeting."
        let first = try Self.shared.embed([text])[0]
        let second = try Self.shared.embed([text])[0]
        #expect(first == second)

        let norm = first.reduce(Double(0)) { $0 + Double($1) * Double($1) }.squareRoot()
        #expect(abs(norm - 1) < 0.01)
    }

    @Test func longTextTruncatesWithoutError() throws {
        let long = Array(repeating: "The quick brown fox jumps over the lazy dog.", count: 400)
            .joined(separator: " ")
        let vector = try Self.shared.embed([long])[0]
        #expect(vector.count == GraniteEmbedder.dimensions)
    }

    @Test func constantsMatchModelContract() {
        #expect(GraniteEmbedder.dimensions == 384)
        #expect(GraniteEmbedder.maxTokens == 512)
        #expect(GraniteEmbedder.modelVersion == "granite-embedding-97m-multilingual-r2-int8")
    }
}
