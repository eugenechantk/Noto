//
//  GraniteEmbedder.swift
//  NotoEmbedding
//
//  CoreML inference for the granite-embedding-97m-multilingual-r2 model
//  (int8-quantized, converted via scripts/embedding-spike/convert.py).
//  Tokenize → fixed 1×512 int32 inputs → one L2-normalized 384-d vector
//  (CLS pooling + normalization run inside the converted graph).
//

import CoreML
import Foundation

public enum GraniteEmbedderError: Error, CustomStringConvertible {
    case missingModelResource
    case unexpectedOutput(String)

    public var description: String {
        switch self {
        case .missingModelResource:
            "GraniteEmbedder: GraniteEmbed_int8 model not found in bundle"
        case let .unexpectedOutput(detail):
            "GraniteEmbedder: unexpected model output — \(detail)"
        }
    }
}

/// Text-embedding inference. Thread-safe (`MLModel` predictions are reentrant);
/// hold one instance and share it — loading costs ~100 MB of weights.
public final class GraniteEmbedder: @unchecked Sendable {
    /// Stored with every persisted vector; bump only with a coordinated index rebuild.
    public static let modelVersion = "granite-embedding-97m-multilingual-r2-int8"
    public static let dimensions = 384
    public static let maxTokens = 512

    private let model: MLModel
    private let tokenizer: GraniteTokenizer

    /// - Parameter modelURL: A compiled `.mlmodelc` directory, or a raw
    ///   `.mlpackage` (compiled on the fly — the `swift test` path; Xcode app
    ///   builds pre-compile bundle resources).
    public init(modelURL: URL, tokenizer: GraniteTokenizer) throws {
        let configuration = MLModelConfiguration()
        // Pinned: the GPU compute path mis-handles compressed weights
        // (hard crash for some int8 models, 3x slowdown for this one, observed
        // on macOS 26.5). CPU+ANE is correct and fast everywhere.
        configuration.computeUnits = .cpuAndNeuralEngine

        let compiledURL: URL
        if modelURL.pathExtension == "mlmodelc" {
            compiledURL = modelURL
        } else {
            compiledURL = try MLModel.compileModel(at: modelURL)
        }
        self.model = try MLModel(contentsOf: compiledURL, configuration: configuration)
        self.tokenizer = tokenizer
    }

    /// Loads the model + tokenizer bundled with this package.
    public static func bundled() throws -> GraniteEmbedder {
        let tokenizer = try GraniteTokenizer.bundled()
        if let compiled = Bundle.module.url(forResource: "GraniteEmbed_int8", withExtension: "mlmodelc") {
            return try GraniteEmbedder(modelURL: compiled, tokenizer: tokenizer)
        }
        guard let raw = Bundle.module.url(forResource: "GraniteEmbed_int8", withExtension: "mlpackage") else {
            throw GraniteEmbedderError.missingModelResource
        }
        return try GraniteEmbedder(modelURL: raw, tokenizer: tokenizer)
    }

    /// One L2-normalized 384-d vector per text. Inputs longer than 512 tokens
    /// are truncated by the tokenizer (HF semantics, SEP kept last). Multiple
    /// texts run as one Core ML batch prediction, which pipelines the ANE far
    /// better than per-text calls during bulk indexing.
    public func embed(_ texts: [String]) throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        // Pool the whole batch: feature buffers and prediction outputs are
        // autoreleased and otherwise pile up across a long indexing sweep.
        return try autoreleasepool {
            let inputs = try texts.map { try featureProvider(for: $0) }
            let batch = try model.predictions(fromBatch: MLArrayBatchProvider(array: inputs))

            var vectors: [[Float]] = []
            vectors.reserveCapacity(texts.count)
            for index in 0..<batch.count {
                vectors.append(try vector(from: batch.features(at: index)))
            }
            guard vectors.count == texts.count else {
                throw GraniteEmbedderError.unexpectedOutput("batch returned \(vectors.count) of \(texts.count)")
            }
            return vectors
        }
    }

    private func featureProvider(for text: String) throws -> MLDictionaryFeatureProvider {
        let tokenIDs = tokenizer.encode(text, maxTokens: Self.maxTokens)
        let realCount = tokenIDs.count
        let padID = Int32(tokenizer.padTokenID)

        let ids = try MLMultiArray(shape: [1, NSNumber(value: Self.maxTokens)], dataType: .int32)
        let mask = try MLMultiArray(shape: [1, NSNumber(value: Self.maxTokens)], dataType: .int32)
        // Direct buffer writes: the NSNumber subscript boxes 1,024 autoreleased
        // objects per chunk, which is real memory pressure across a 10k-chunk
        // sweep (bug 018).
        ids.withUnsafeMutableBufferPointer(ofType: Int32.self) { buffer, _ in
            for index in 0..<Self.maxTokens {
                buffer[index] = index < realCount ? Int32(tokenIDs[index]) : padID
            }
        }
        mask.withUnsafeMutableBufferPointer(ofType: Int32.self) { buffer, _ in
            for index in 0..<Self.maxTokens {
                buffer[index] = index < realCount ? 1 : 0
            }
        }
        return try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: ids),
            "attention_mask": MLFeatureValue(multiArray: mask),
        ])
    }

    private func vector(from output: MLFeatureProvider) throws -> [Float] {
        guard let embedding = output.featureValue(for: "embedding")?.multiArrayValue else {
            throw GraniteEmbedderError.unexpectedOutput("no 'embedding' feature")
        }
        guard embedding.count == Self.dimensions else {
            throw GraniteEmbedderError.unexpectedOutput("dims \(embedding.count) != \(Self.dimensions)")
        }
        var vector = [Float](repeating: 0, count: Self.dimensions)
        if embedding.dataType == .float32 {
            embedding.withUnsafeBufferPointer(ofType: Float.self) { buffer in
                for index in 0..<Self.dimensions {
                    vector[index] = buffer[index]
                }
            }
        } else {
            // Defensive: tolerate fp16/double outputs (runtime-dependent)
            // instead of tripping the typed-buffer precondition mid-sweep.
            for index in 0..<Self.dimensions {
                vector[index] = embedding[index].floatValue
            }
        }
        return vector
    }
}
