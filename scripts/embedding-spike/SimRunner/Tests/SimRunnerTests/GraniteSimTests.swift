import CoreML
import XCTest

/// Test case index
/// 1. testModelCompilesLoadsAndMatchesReference — compiles GraniteEmbed_int8.mlpackage on the
///    iOS runtime, embeds 10 pre-tokenized EN/ZH/JA fixtures, asserts cosine >= 0.999 vs the
///    PyTorch fp32 reference, and reports per-inference latency.
final class GraniteSimTests: XCTestCase {

    struct Fixture: Decodable {
        let id: String
        let input_ids: [Int32]
        let attention_mask: [Int32]
        let ref_torch: [Float]
        let ref_mac_coreml_int8: [Float]
    }

    func testModelCompilesLoadsAndMatchesReference() throws {
        let bundle = Bundle.module
        // Xcode's resource pipeline compiles the .mlpackage to .mlmodelc at build time —
        // the same form it would ship in inside the real app bundle.
        let fixURL = try XCTUnwrap(bundle.url(forResource: "sim_fixtures", withExtension: "json"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: fixURL))

        let compileStart = Date()
        let compiledURL = try XCTUnwrap(bundle.url(forResource: "GraniteEmbed_int8", withExtension: "mlmodelc"))
        let compileSecs = Date().timeIntervalSince(compileStart)

        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine  // the pinning we plan to ship with
        let loadStart = Date()
        let model = try MLModel(contentsOf: compiledURL, configuration: config)
        let loadSecs = Date().timeIntervalSince(loadStart)

        var minCosTorch: Double = 1.0, minCosMac: Double = 1.0
        var latencies: [Double] = []

        for fixture in fixtures {
            let ids = try MLMultiArray(shape: [1, 512], dataType: .int32)
            let mask = try MLMultiArray(shape: [1, 512], dataType: .int32)
            for i in 0..<512 {
                ids[i] = NSNumber(value: fixture.input_ids[i])
                mask[i] = NSNumber(value: fixture.attention_mask[i])
            }
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids": MLFeatureValue(multiArray: ids),
                "attention_mask": MLFeatureValue(multiArray: mask),
            ])

            let t0 = Date()
            let output = try model.prediction(from: input)
            latencies.append(Date().timeIntervalSince(t0) * 1000)

            let emb = try XCTUnwrap(output.featureValue(for: "embedding")?.multiArrayValue)
            XCTAssertEqual(emb.count, 384, "unexpected embedding dimension")
            var vec = [Double](repeating: 0, count: 384)
            for i in 0..<384 { vec[i] = emb[i].doubleValue }

            minCosTorch = min(minCosTorch, cosine(vec, fixture.ref_torch.map(Double.init)))
            minCosMac = min(minCosMac, cosine(vec, fixture.ref_mac_coreml_int8.map(Double.init)))
        }

        latencies.sort()
        let median = latencies[latencies.count / 2]
        let report = "SIMSPIKE locate_s=\(String(format: "%.2f", compileSecs)) load_s=\(String(format: "%.2f", loadSecs)) " +
              "min_cos_torch=\(String(format: "%.6f", minCosTorch)) min_cos_mac=\(String(format: "%.6f", minCosMac)) " +
              "median_ms=\(String(format: "%.1f", median)) max_ms=\(String(format: "%.1f", latencies.last!))"
        print(report)
        // Simulator processes share the host filesystem — surface metrics to the host.
        try? report.write(toFile: "/tmp/noto-embed-spike/sim_result.txt", atomically: true, encoding: .utf8)

        XCTAssertGreaterThanOrEqual(minCosTorch, 0.999, "on-simulator embeddings diverge from PyTorch reference")
        XCTAssertGreaterThanOrEqual(minCosMac, 0.9995, "on-simulator embeddings diverge from Mac CoreML run")
    }

    private func cosine(_ a: [Double], _ b: [Double]) -> Double {
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        return dot / (na.squareRoot() * nb.squareRoot())
    }
}
