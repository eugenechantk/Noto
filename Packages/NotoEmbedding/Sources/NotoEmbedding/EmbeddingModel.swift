//
//  EmbeddingModel.swift
//  NotoEmbedding
//
//  CoreML wrapper for bge-small-en-v1.5. Produces 384-dim normalized embeddings.
//  Uses WordPiece BertTokenizer for input preparation.
//

import CoreML
import Foundation
import os.log

private let logger = Logger(subsystem: "com.noto", category: "EmbeddingModel")

public final class EmbeddingModel {

    public static let dimensions = 384
    public static let modelVersion = "bge-small-en-v1.5"

    private let model: MLModel
    private let tokenizer: BertTokenizer

    /// Loads the CoreML model and vocabulary from the app bundle.
    public init() throws {
        // Load tokenizer vocabulary
        guard let vocabURL = Bundle.main.url(forResource: "vocab", withExtension: "txt") else {
            throw EmbeddingModelError.vocabNotFound
        }
        self.tokenizer = try BertTokenizer(vocabURL: vocabURL)

        // Load CoreML model
        guard let modelURL = Bundle.main.url(forResource: "bge-small-en-v1_5", withExtension: "mlmodelc") else {
            throw EmbeddingModelError.modelNotFound
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all // Neural Engine + GPU + CPU fallback
        self.model = try MLModel(contentsOf: modelURL, configuration: config)

        logger.info("EmbeddingModel loaded successfully")
    }

    /// Internal init for testing with pre-loaded components.
    public init(model: MLModel, tokenizer: BertTokenizer) {
        self.model = model
        self.tokenizer = tokenizer
    }

    /// Generates a 384-dimensional normalized embedding for a text string.
    public func embed(_ text: String) throws -> [Float] {
        let tokenizerOutput = tokenizer.tokenize(text)
        return try infer(inputIds: tokenizerOutput.inputIds, attentionMask: tokenizerOutput.attentionMask)
    }

    /// Batch embedding for multiple texts.
    public func embed(batch texts: [String]) throws -> [[Float]] {
        return try texts.map { try embed($0) }
    }

    // MARK: - Private

    private func infer(inputIds: [Int32], attentionMask: [Int32]) throws -> [Float] {
        let seqLen = tokenizer.maxSequenceLength

        let inputIdsArray = try MLMultiArray(shape: [1, NSNumber(value: seqLen)], dataType: .int32)
        let attentionMaskArray = try MLMultiArray(shape: [1, NSNumber(value: seqLen)], dataType: .int32)

        for i in 0..<seqLen {
            inputIdsArray[[0, NSNumber(value: i)] as [NSNumber]] = NSNumber(value: inputIds[i])
            attentionMaskArray[[0, NSNumber(value: i)] as [NSNumber]] = NSNumber(value: attentionMask[i])
        }

        let inputFeatures = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIdsArray),
            "attention_mask": MLFeatureValue(multiArray: attentionMaskArray),
        ])

        let output = try model.prediction(from: inputFeatures)

        guard let embeddingFeature = output.featureValue(for: "sentence_embedding"),
              let embeddingArray = embeddingFeature.multiArrayValue else {
            throw EmbeddingModelError.invalidOutput
        }

        var vector = [Float](repeating: 0, count: Self.dimensions)
        for i in 0..<Self.dimensions {
            vector[i] = embeddingArray[i].floatValue
        }

        return vector
    }
}

public enum EmbeddingModelError: Error, LocalizedError {
    case vocabNotFound
    case modelNotFound
    case invalidOutput

    public var errorDescription: String? {
        switch self {
        case .vocabNotFound: return "vocab.txt not found in bundle"
        case .modelNotFound: return "bge-small-en-v1_5.mlmodelc not found in bundle"
        case .invalidOutput: return "CoreML model output missing sentence_embedding"
        }
    }
}
