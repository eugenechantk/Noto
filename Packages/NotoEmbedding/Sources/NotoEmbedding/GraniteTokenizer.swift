//
//  GraniteTokenizer.swift
//  NotoEmbedding
//
//  Public tokenizer API for the `ibm-granite/granite-embedding-97m-multilingual-r2`
//  embedding model. Wraps the vendored swift-transformers BPE pipeline
//  (see VendoredTokenizers/) and reproduces the Hugging Face fast tokenizer
//  exactly: byte-level BPE with `ignore_merges`, Split + ByteLevel
//  pre-tokenization, and TemplateProcessing post-processing
//  (`<|startoftext|> $A <|return|>`).
//

import Foundation

/// Errors thrown while loading the Granite tokenizer.
public enum GraniteTokenizerError: Error, CustomStringConvertible {
    /// A required resource file was missing from the bundle.
    case missingResource(String)
    /// A special token required by the post-processor was not found in the vocabulary.
    case missingSpecialToken(String)

    public var description: String {
        switch self {
        case let .missingResource(name):
            "GraniteTokenizer: missing bundled resource \(name)"
        case let .missingSpecialToken(token):
            "GraniteTokenizer: special token \(token) not found in vocabulary"
        }
    }
}

/// Tokenizer matching the Hugging Face tokenizer of
/// `ibm-granite/granite-embedding-97m-multilingual-r2`.
///
/// `encode(_:)` returns the same `input_ids` as Python
/// `tokenizer(text)["input_ids"]`, including the special tokens
/// `<|startoftext|>` (CLS, 179934) and `<|return|>` (SEP, 179938) — no padding.
///
/// Parsing the ~24 MB `tokenizer.json` happens once in `init` (on the order of
/// a second); the resulting value is cheap to copy and use afterwards, and is
/// safe to share across concurrency domains.
public struct GraniteTokenizer: Sendable {
    private let tokenizer: PreTrainedTokenizer
    private let clsId: Int
    private let sepId: Int
    private let padId: Int

    /// Padding token id (`<|endoftext|>`), used to fill fixed-shape model inputs.
    public var padTokenID: Int { padId }

    /// Loads the tokenizer from explicit `tokenizer.json` / `tokenizer_config.json` file URLs.
    ///
    /// - Parameters:
    ///   - tokenizerJSONURL: Location of the HF `tokenizer.json` (vocab, merges, pipeline).
    ///   - tokenizerConfigURL: Location of the HF `tokenizer_config.json` (special tokens, class).
    /// - Throws: If either file cannot be read or parsed, or required special tokens are missing.
    public init(tokenizerJSONURL: URL, tokenizerConfigURL: URL) throws {
        let tokenizerData = try Config(jsonData: Data(contentsOf: tokenizerJSONURL))
        let tokenizerConfig = try Config(jsonData: Data(contentsOf: tokenizerConfigURL))
        tokenizer = try PreTrainedTokenizer(tokenizerConfig: tokenizerConfig, tokenizerData: tokenizerData)

        // CLS/SEP come from tokenizer_config (cls_token / sep_token); resolved to ids via the vocab.
        guard let clsToken = addedTokenAsString(tokenizerConfig.clsToken),
              let clsId = tokenizer.convertTokenToId(clsToken)
        else {
            throw GraniteTokenizerError.missingSpecialToken("cls_token")
        }
        guard let sepToken = addedTokenAsString(tokenizerConfig.sepToken),
              let sepId = tokenizer.convertTokenToId(sepToken)
        else {
            throw GraniteTokenizerError.missingSpecialToken("sep_token")
        }
        guard let padToken = addedTokenAsString(tokenizerConfig.padToken),
              let padId = tokenizer.convertTokenToId(padToken)
        else {
            throw GraniteTokenizerError.missingSpecialToken("pad_token")
        }
        self.clsId = clsId
        self.sepId = sepId
        self.padId = padId
    }

    /// Loads the tokenizer from the `tokenizer.json` + `tokenizer_config.json` bundled with this package.
    public static func bundled() throws -> GraniteTokenizer {
        guard let tokenizerJSONURL = Bundle.module.url(forResource: "tokenizer", withExtension: "json") else {
            throw GraniteTokenizerError.missingResource("tokenizer.json")
        }
        guard let tokenizerConfigURL = Bundle.module.url(forResource: "tokenizer_config", withExtension: "json") else {
            throw GraniteTokenizerError.missingResource("tokenizer_config.json")
        }
        return try GraniteTokenizer(tokenizerJSONURL: tokenizerJSONURL, tokenizerConfigURL: tokenizerConfigURL)
    }

    /// Encodes text to token ids, special tokens included, no padding.
    ///
    /// Equivalent to Python `tokenizer(text)["input_ids"]`:
    /// `[<|startoftext|>] + BPE(text) + [<|return|>]`.
    public func encode(_ text: String) -> [Int] {
        tokenizer.encode(text: text, addSpecialTokens: true)
    }

    /// Encodes text to token ids with HF `truncation=True, max_length=maxTokens` semantics.
    ///
    /// The result never exceeds `maxTokens` tokens *including* the two special tokens:
    /// the content is truncated to `maxTokens - 2`, then `<|startoftext|>` is prepended
    /// and `<|return|>` appended (SEP is appended *after* truncation, so the last token
    /// is always `<|return|>` when `maxTokens >= 2`).
    public func encode(_ text: String, maxTokens: Int) -> [Int] {
        guard maxTokens >= 2 else {
            // Degenerate budget: not enough room for content; return as many specials as fit.
            return Array([clsId, sepId].prefix(max(maxTokens, 0)))
        }
        var content = tokenizer.encode(text: text, addSpecialTokens: false)
        let budget = maxTokens - 2
        if content.count > budget {
            content = Array(content.prefix(budget))
        }
        return [clsId] + content + [sepId]
    }
}
