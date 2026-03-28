//
//  WordPieceTokenizer.swift
//  NotoEmbedding
//
//  WordPiece subword tokenization for BERT models.
//  Splits words into known vocabulary tokens or ##-prefixed subword pieces.
//

import Foundation

public struct WordPieceTokenizer {

    private let vocab: [String: Int]
    private let unkTokenId: Int
    private let maxInputCharsPerWord: Int

    /// Initializes with a vocabulary mapping token strings to IDs.
    public init(vocab: [String: Int], unkToken: String = "[UNK]", maxInputCharsPerWord: Int = 200) {
        self.vocab = vocab
        self.unkTokenId = vocab[unkToken] ?? 0
        self.maxInputCharsPerWord = maxInputCharsPerWord
    }

    /// Tokenizes a single word into subword token IDs.
    /// Returns `[unkTokenId]` if the word cannot be decomposed.
    public func tokenize(word: String) -> [Int] {
        if word.count > maxInputCharsPerWord {
            return [unkTokenId]
        }

        var tokens: [Int] = []
        var start = word.startIndex
        while start < word.endIndex {
            var end = word.endIndex
            var found = false

            while start < end {
                let substr: String
                if start == word.startIndex {
                    substr = String(word[start..<end])
                } else {
                    substr = "##" + String(word[start..<end])
                }

                if let tokenId = vocab[substr] {
                    tokens.append(tokenId)
                    start = end
                    found = true
                    break
                }

                end = word.index(before: end)
            }

            if !found {
                return [unkTokenId]
            }
        }
        return tokens
    }
}
