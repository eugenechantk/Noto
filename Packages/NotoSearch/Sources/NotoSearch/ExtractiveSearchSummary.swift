import Foundation

/// A note body used to build an offline, extractive search summary.
public struct ExtractiveSummarySource: Sendable, Equatable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// Builds a short, attributed highlight reel without a network request or a
/// generative model. Every rendered claim is copied from one of the sources.
public enum ExtractiveSearchSummary {
    public static func text(
        query: String,
        sources: [ExtractiveSummarySource],
        limit: Int = 4
    ) -> String {
        guard limit > 0 else { return "" }
        let terms = tokens(in: query)
        var candidates: [Candidate] = []

        for (sourceIndex, source) in sources.enumerated() {
            for (position, sentence) in sentences(in: source.body).enumerated() {
                let lower = sentence.lowercased()
                let bodyMatches = terms.reduce(into: 0) { count, term in
                    if lower.localizedStandardContains(term) { count += 1 }
                }
                let title = source.title.lowercased()
                let titleMatches = terms.reduce(into: 0) { count, term in
                    if title.localizedStandardContains(term) { count += 1 }
                }
                // Search result order is already relevance-ranked. Query-term
                // overlap sharpens that order; source/position are deterministic
                // tie-breakers and keep the no-overlap fallback useful.
                let score = Double(bodyMatches * 10 + titleMatches * 3)
                    + 2.0 / Double(sourceIndex + 1)
                    + 0.5 / Double(position + 1)
                candidates.append(Candidate(
                    sourceIndex: sourceIndex,
                    title: source.title.isEmpty ? "Untitled" : source.title,
                    sentence: sentence,
                    canonical: canonical(sentence),
                    score: score,
                    position: position
                ))
            }
        }

        let ranked = candidates.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.sourceIndex != $1.sourceIndex { return $0.sourceIndex < $1.sourceIndex }
            return $0.position < $1.position
        }

        var selected: [Candidate] = []
        var usedSources = Set<Int>()
        var usedSentences = Set<String>()

        // Prefer coverage across notes before taking a second sentence from one.
        for candidate in ranked where selected.count < limit {
            guard !usedSources.contains(candidate.sourceIndex),
                  usedSentences.insert(candidate.canonical).inserted else { continue }
            selected.append(candidate)
            usedSources.insert(candidate.sourceIndex)
        }
        if selected.count < limit {
            for candidate in ranked where selected.count < limit {
                guard usedSentences.insert(candidate.canonical).inserted else { continue }
                selected.append(candidate)
            }
        }

        return selected
            .map { "• \($0.sentence) — \($0.title)" }
            .joined(separator: "\n")
    }

    private struct Candidate {
        let sourceIndex: Int
        let title: String
        let sentence: String
        let canonical: String
        let score: Double
        let position: Int
    }

    private static func sentences(in body: String) -> [String] {
        body.components(separatedBy: .newlines).flatMap { rawLine -> [String] in
            // Markdown headings are navigation labels, not claims. Including a
            // top-level heading often produced a useless "Title — Title" row.
            if rawLine.trimmingCharacters(in: .whitespaces).hasPrefix("#") { return [] }
            let line = cleaned(rawLine)
            guard line.count >= 12 else { return [] }
            var result: [String] = []
            line.enumerateSubstrings(
                in: line.startIndex..<line.endIndex,
                options: [.bySentences, .localized]
            ) { substring, _, _, _ in
                guard let substring else { return }
                let sentence = substring.trimmingCharacters(in: .whitespacesAndNewlines)
                if sentence.count >= 12 { result.append(sentence) }
            }
            return result.isEmpty ? [line] : result
        }
    }

    private static func cleaned(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["- [ ] ", "- [x] ", "- [X] ", "* [ ] ", "* [x] ", "* [X] "]
            where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
        }
        while let first = value.first, "#>*-•".contains(first) {
            value.removeFirst()
            value = value.trimmingCharacters(in: .whitespaces)
        }
        if let dot = value.firstIndex(of: "."),
           value[..<dot].allSatisfy(\.isNumber),
           value.index(after: dot) < value.endIndex {
            value = String(value[value.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
        }
        return value
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func tokens(in text: String) -> [String] {
        var seen = Set<String>()
        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && seen.insert($0).inserted }
    }

    private static func canonical(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}
