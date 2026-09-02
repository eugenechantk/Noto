import Foundation
import SwiftUI

/// Emphasizes the query's terms inside a snippet (weight + colour, never a
/// highlight box). Pure, so the tokenization and match ranges are testable.
enum SnippetEmphasis {
    /// Query words worth emphasizing: 2+ characters, deduplicated, longest first
    /// so overlapping tokens ("note", "notes") resolve to the longer match.
    static func tokens(from query: String) -> [String] {
        let words = query
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 2 }
        var seen = Set<String>()
        return words.filter { seen.insert($0).inserted }.sorted { $0.count > $1.count }
    }

    /// Light stems so "surfaces" emphasizes "surface" and vice-versa: the token
    /// itself plus every applicable trailing s/es/ed/ing strip (never below 3 chars).
    static func stems(for token: String) -> [String] {
        var out = [token]
        for suffix in ["s", "es", "ed", "ing"] where token.hasSuffix(suffix) && token.count - suffix.count >= 3 {
            let stem = String(token.dropLast(suffix.count))
            if !out.contains(stem) { out.append(stem) }
        }
        return out
    }

    /// Whole-word ranges in `text` that match any token: the word equals a
    /// token/stem, or starts with a stem, or is a prefix (≥4 chars) of a token.
    /// Case- and diacritic-insensitive, non-overlapping, in order.
    static func matchRanges(in text: String, tokens: [String]) -> [Range<String.Index>] {
        guard !tokens.isEmpty, !text.isEmpty else { return [] }
        let stemmed = tokens.flatMap(stems(for:))
        var ranges: [Range<String.Index>] = []
        var wordStart: String.Index?
        var index = text.startIndex
        func flush(_ end: String.Index) {
            guard let start = wordStart else { return }
            wordStart = nil
            let word = text[start..<end].folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
            let hit = stemmed.contains { stem in
                word == stem || word.hasPrefix(stem) || (word.count >= 4 && stem.hasPrefix(word))
            }
            if hit { ranges.append(start..<end) }
        }
        while index < text.endIndex {
            let ch = text[index]
            if ch.isLetter || ch.isNumber {
                if wordStart == nil { wordStart = index }
            } else {
                flush(index)
            }
            index = text.index(after: index)
        }
        flush(text.endIndex)
        return ranges
    }

    /// Plain segments interleaved with emphasized ones — what the view renders.
    struct Segment: Equatable {
        let text: String
        let emphasized: Bool
    }

    static func segments(of text: String, query: String) -> [Segment] {
        let ranges = matchRanges(in: text, tokens: tokens(from: query))
        guard !ranges.isEmpty else { return [Segment(text: text, emphasized: false)] }
        var out: [Segment] = []
        var cursor = text.startIndex
        for range in ranges {
            if cursor < range.lowerBound {
                out.append(Segment(text: String(text[cursor..<range.lowerBound]), emphasized: false))
            }
            out.append(Segment(text: String(text[range]), emphasized: true))
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            out.append(Segment(text: String(text[cursor...]), emphasized: false))
        }
        return out
    }

    static func attributed(_ text: String, query: String, base: Color, emphasis: Color) -> AttributedString {
        var result = AttributedString()
        for segment in segments(of: text, query: query) {
            var piece = AttributedString(segment.text)
            if segment.emphasized {
                piece.font = .subheadline.weight(.semibold)
                piece.foregroundColor = emphasis
            } else {
                piece.font = .subheadline
                piece.foregroundColor = base
            }
            result.append(piece)
        }
        return result
    }
}
