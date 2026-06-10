import Foundation

/// What the chunker distinguishes when persisting and surfacing chunks.
public enum SemanticChunkKind: String, Sendable {
    case text
    case image
}

/// On-device understanding of one image, ready to be embedded as text.
public struct ImageDescription: Sendable, Equatable {
    /// Recognized text, reading order, newline-joined. Empty when none found.
    public let ocrText: String
    /// Scene/object labels, most confident first. Empty when none cleared the bar.
    public let labels: [String]

    public init(ocrText: String, labels: [String]) {
        self.ocrText = ocrText
        self.labels = labels
    }

    public var isEmpty: Bool { ocrText.isEmpty && labels.isEmpty }
}

/// Turns image bytes into searchable text. The default implementation uses
/// Apple Vision (OCR + classification); tests inject fakes.
public protocol ImageDescribing: Sendable {
    /// Recorded with every image chunk; bumping it re-describes everything
    /// incrementally (same pattern as the embedding model version).
    var describerVersion: String { get }
    func describe(imageData: Data) throws -> ImageDescription
}

/// Fetches remote (`http(s)`) images, caching by URL so each image downloads
/// once. Returns nil when unavailable (offline, 404, not an image) — callers
/// skip quietly and search degrades to text-only for that image.
public protocol RemoteImageFetching: Sendable {
    func fetch(url: URL) -> Data?
}

/// One `![alt](target)` reference found in a note's raw markdown.
public struct MarkdownImageReference: Sendable, Equatable {
    public let altText: String
    /// Vault-relative path (percent-decoded) for local images, or the absolute
    /// URL string for remote ones.
    public let target: String
    public let isRemote: Bool
    /// 1-based line in the full file (frontmatter included), matching the
    /// line-number convention of `SearchSection`.
    public let line: Int

    public init(altText: String, target: String, isRemote: Bool, line: Int) {
        self.altText = altText
        self.target = target
        self.isRemote = isRemote
        self.line = line
    }
}

/// Extracts image references from markdown. Pure logic, line-accurate.
public enum MarkdownImageExtractor {
    // ![alt](target) — alt may be empty; target may carry an optional "title".
    private static let pattern = try? NSRegularExpression(
        pattern: #"!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#
    )

    public static func references(in markdown: String) -> [MarkdownImageReference] {
        guard let pattern else { return [] }
        var results: [MarkdownImageReference] = []

        for (index, line) in markdown.components(separatedBy: "\n").enumerated() {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            pattern.enumerateMatches(in: line, range: range) { match, _, _ in
                guard let match,
                      let altRange = Range(match.range(at: 1), in: line),
                      let targetRange = Range(match.range(at: 2), in: line) else { return }
                let rawTarget = String(line[targetRange])
                guard let reference = reference(
                    altText: String(line[altRange]),
                    rawTarget: rawTarget,
                    line: index + 1
                ) else { return }
                results.append(reference)
            }
        }
        return results
    }

    private static func reference(altText: String, rawTarget: String, line: Int) -> MarkdownImageReference? {
        let target = rawTarget.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return nil }

        let lowered = target.lowercased()
        if lowered.hasPrefix("data:") { return nil }
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            guard URL(string: target) != nil else { return nil }
            return MarkdownImageReference(altText: altText, target: target, isRemote: true, line: line)
        }
        // Vault-relative path; the editor writes percent-encoded components.
        let decoded = target.removingPercentEncoding ?? target
        guard !decoded.hasPrefix("/") else { return nil }
        return MarkdownImageReference(altText: altText, target: decoded, isRemote: false, line: line)
    }
}
