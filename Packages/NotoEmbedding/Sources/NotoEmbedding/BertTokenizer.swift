//
//  BertTokenizer.swift
//  NotoEmbedding
//
//  Full BERT tokenization pipeline: basic tokenization (lowercase, split on
//  whitespace/punctuation) followed by WordPiece subword splitting.
//  Produces input_ids and attention_mask arrays for CoreML inference.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.noto", category: "BertTokenizer")

public struct BertTokenizerOutput {
    public let inputIds: [Int32]
    public let attentionMask: [Int32]
}

public struct BertTokenizer {

    private let vocab: [String: Int]
    private let wordPiece: WordPieceTokenizer

    private let clsTokenId: Int
    private let sepTokenId: Int
    private let padTokenId: Int

    public let maxSequenceLength: Int

    /// Loads vocabulary from a vocab.txt file (one token per line, ID = line number).
    public init(vocabURL: URL, maxSequenceLength: Int = 512) throws {
        let content = try String(contentsOf: vocabURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        var vocab: [String: Int] = [:]
        for (index, line) in lines.enumerated() {
            let token = line.trimmingCharacters(in: .whitespaces)
            if !token.isEmpty {
                vocab[token] = index
            }
        }

        self.vocab = vocab
        self.wordPiece = WordPieceTokenizer(vocab: vocab)
        self.clsTokenId = vocab["[CLS]"] ?? 101
        self.sepTokenId = vocab["[SEP]"] ?? 102
        self.padTokenId = vocab["[PAD]"] ?? 0
        self.maxSequenceLength = maxSequenceLength

        logger.info("BertTokenizer loaded \(vocab.count) vocabulary entries")
    }

    /// Tokenizes text into input_ids and attention_mask for the BERT model.
    public func tokenize(_ text: String) -> BertTokenizerOutput {
        let words = basicTokenize(text)

        var tokenIds: [Int] = [clsTokenId]
        let maxTokens = maxSequenceLength - 2 // reserve space for [CLS] and [SEP]

        for word in words {
            let subTokens = wordPiece.tokenize(word: word)
            if tokenIds.count - 1 + subTokens.count > maxTokens {
                // would exceed max length — add what fits
                let remaining = maxTokens - (tokenIds.count - 1)
                tokenIds.append(contentsOf: subTokens.prefix(remaining))
                break
            }
            tokenIds.append(contentsOf: subTokens)
        }

        tokenIds.append(sepTokenId)

        let realTokenCount = tokenIds.count
        let paddingCount = maxSequenceLength - realTokenCount

        let inputIds = tokenIds.map { Int32($0) } + Array(repeating: Int32(padTokenId), count: paddingCount)
        let attentionMask = Array(repeating: Int32(1), count: realTokenCount) + Array(repeating: Int32(0), count: paddingCount)

        return BertTokenizerOutput(inputIds: inputIds, attentionMask: attentionMask)
    }

    // MARK: - Basic Tokenization

    /// Lowercases, strips accents, and splits on whitespace and punctuation.
    private func basicTokenize(_ text: String) -> [String] {
        let lowered = text.lowercased()
        let cleaned = stripAccents(lowered)
        return splitOnPunctuation(cleaned)
    }

    /// Replaces accented characters with their base form.
    private func stripAccents(_ text: String) -> String {
        // Decompose into canonical form, then strip combining marks
        let decomposed = text.decomposedStringWithCanonicalMapping
        return String(decomposed.unicodeScalars.filter {
            CharacterSet.nonBaseCharacters.contains($0) == false
        })
    }

    /// Splits text on whitespace and punctuation, keeping punctuation as separate tokens.
    private func splitOnPunctuation(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        for char in text {
            if char.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else if isPunctuation(char) {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                tokens.append(String(char))
            } else {
                current.append(char)
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    /// Returns true if the character is a punctuation character (BERT definition).
    private func isPunctuation(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        let cp = scalar.value

        // ASCII punctuation ranges
        if (cp >= 33 && cp <= 47) || (cp >= 58 && cp <= 64) ||
            (cp >= 91 && cp <= 96) || (cp >= 123 && cp <= 126) {
            return true
        }

        // Unicode general category P (punctuation)
        return CharacterSet.punctuationCharacters.contains(scalar)
    }
}
