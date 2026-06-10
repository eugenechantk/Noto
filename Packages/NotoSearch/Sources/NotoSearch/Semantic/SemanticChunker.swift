import Foundation

/// Splits a `SearchDocument` into embeddable chunks.
///
/// Strategy (see `.claude/brainstorm/semantic-search-plan.md`):
/// - A note whose whole body fits the token cap becomes ONE chunk.
/// - Otherwise one chunk per heading section; oversized sections are split
///   greedily by line.
/// - Every chunk's embedded text is prefixed with a contextual header
///   (`title > heading`) so short queries can land on body text that never
///   repeats the note's topic.
public struct SemanticChunker: Sendable {
    public let maxTokensPerChunk: Int
    public let minTokensPerChunk: Int
    public let modelVersion: String

    public init(modelVersion: String, maxTokensPerChunk: Int = 400, minTokensPerChunk: Int = 3) {
        self.modelVersion = modelVersion
        self.maxTokensPerChunk = maxTokensPerChunk
        self.minTokensPerChunk = minTokensPerChunk
    }

    public func chunks(for document: SearchDocument) -> [SemanticChunk] {
        let wholeBody = document.plainText
        let wholeTokens = Self.estimatedTokens(wholeBody)
        guard wholeTokens >= minTokensPerChunk else { return [] }

        if wholeTokens <= maxTokensPerChunk {
            let lineStart = document.sections.first?.lineStart ?? 1
            let lineEnd = document.sections.last?.lineEnd ?? lineStart
            return [
                chunk(
                    noteID: document.id,
                    seed: "whole:0",
                    header: document.title,
                    heading: document.title,
                    body: wholeBody,
                    lineStart: lineStart,
                    lineEnd: lineEnd
                ),
            ]
        }

        var result: [SemanticChunk] = []
        for section in document.sections {
            let body = section.plainText
            guard Self.estimatedTokens(body) >= minTokensPerChunk else { continue }
            let header = section.heading == document.title || section.heading.isEmpty
                ? document.title
                : "\(document.title) > \(section.heading)"

            let parts = splitIfNeeded(body)
            for (partIndex, part) in parts.enumerated() {
                result.append(
                    chunk(
                        noteID: document.id,
                        seed: "\(section.sectionIndex):\(partIndex)",
                        header: header,
                        heading: section.heading,
                        body: part,
                        lineStart: section.lineStart,
                        lineEnd: section.lineEnd
                    )
                )
            }
        }
        return result
    }

    private func chunk(
        noteID: UUID,
        seed: String,
        header: String,
        heading: String,
        body: String,
        lineStart: Int,
        lineEnd: Int
    ) -> SemanticChunk {
        let embeddedText = header.isEmpty ? body : "\(header)\n\(body)"
        return SemanticChunk(
            id: SearchUtilities.stableID(for: "\(noteID.uuidString):chunk:\(seed)"),
            noteID: noteID,
            heading: heading,
            lineStart: lineStart,
            lineEnd: lineEnd,
            embeddedText: embeddedText,
            snippetText: body,
            contentHash: SearchUtilities.contentHash("\(modelVersion)\n\(embeddedText)")
        )
    }

    /// Greedy line packing: lines are natural sentence/bullet boundaries in
    /// extracted plain text. No overlap — heading boundaries don't need it and
    /// forced splits in personal notes rarely cut mid-thought across lines.
    private func splitIfNeeded(_ body: String) -> [String] {
        guard Self.estimatedTokens(body) > maxTokensPerChunk else { return [body] }

        var parts: [String] = []
        var currentLines: [String] = []
        var currentTokens = 0

        for line in body.components(separatedBy: "\n") {
            let lineTokens = Self.estimatedTokens(line)
            if currentTokens > 0, currentTokens + lineTokens > maxTokensPerChunk {
                parts.append(currentLines.joined(separator: "\n"))
                currentLines = []
                currentTokens = 0
            }
            currentLines.append(line)
            currentTokens += lineTokens
        }
        if !currentLines.isEmpty {
            let tail = currentLines.joined(separator: "\n")
            if Self.estimatedTokens(tail) >= minTokensPerChunk || parts.isEmpty {
                parts.append(tail)
            } else if var last = parts.popLast() {
                last += "\n" + tail
                parts.append(last)
            }
        }
        return parts
    }

    /// Cheap token estimate good enough for chunk sizing. CJK scripts tokenize
    /// roughly one token per character; Latin-script words average ~4 chars
    /// per token. Exactness doesn't matter — the embedder truncates at its own
    /// hard limit; this only keeps chunks comfortably under it.
    public static func estimatedTokens(_ text: String) -> Int {
        var tokens = 0
        var currentWordLength = 0

        func flushWord() {
            if currentWordLength > 0 {
                tokens += max(1, (currentWordLength + 3) / 4)
                currentWordLength = 0
            }
        }

        for scalar in text.unicodeScalars {
            if Self.isCJK(scalar) {
                flushWord()
                tokens += 1
            } else if CharacterSet.alphanumerics.contains(scalar) {
                currentWordLength += 1
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                flushWord()
            } else {
                flushWord()
                tokens += 1
            }
        }
        flushWord()
        return tokens
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x2E80...0x9FFF,      // CJK radicals, Kangxi, CJK unified, Kana
             0x3400...0x4DBF,      // CJK extension A (inside above range, kept for clarity)
             0xAC00...0xD7AF,      // Hangul syllables
             0xF900...0xFAFF,      // CJK compatibility ideographs
             0x20000...0x2FA1F:    // CJK extensions B+
            return true
        default:
            return false
        }
    }
}
