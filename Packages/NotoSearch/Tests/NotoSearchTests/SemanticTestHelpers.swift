import Foundation
import NotoSearch

/// Deterministic embedder for semantic tests: pseudo-random L2-normalized
/// vectors derived from the text, plus thread-safe call accounting so tests
/// can assert exactly which chunks were (re-)embedded.
final class FakeEmbedder: TextEmbedding, @unchecked Sendable {
    let modelVersion: String
    let dimensions: Int
    private let lock = NSLock()
    private var _embeddedTexts: [String] = []

    init(modelVersion: String = "fake-v1", dimensions: Int = 8) {
        self.modelVersion = modelVersion
        self.dimensions = dimensions
    }

    var embeddedTexts: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _embeddedTexts
    }

    var embedCallTotal: Int { embeddedTexts.count }

    func embed(_ texts: [String]) throws -> [[Float]] {
        lock.lock()
        _embeddedTexts.append(contentsOf: texts)
        lock.unlock()
        return texts.map { Self.vector(for: $0, dimensions: dimensions) }
    }

    static func vector(for text: String, dimensions: Int) -> [Float] {
        var seed: UInt64 = 5381
        for byte in text.utf8 {
            seed = seed &* 127 &+ UInt64(byte)
        }
        var values: [Float] = []
        values.reserveCapacity(dimensions)
        for _ in 0..<dimensions {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit = Float(seed >> 40) / Float(1 << 24)
            values.append(unit * 2 - 1)
        }
        return normalized(values)
    }

    static func normalized(_ values: [Float]) -> [Float] {
        let norm = (values.reduce(Float(0)) { $0 + $1 * $1 }).squareRoot()
        guard norm > 0 else { return values }
        return values.map { $0 / norm }
    }
}

/// A SearchDocument with controllable sections, for chunker tests.
func makeDocument(
    id: UUID = UUID(),
    relativePath: String = "Test.md",
    title: String = "Test Note",
    sections: [(heading: String, level: Int?, text: String)],
    plainText: String? = nil
) -> SearchDocument {
    let builtSections = sections.enumerated().map { index, section in
        SearchSection(
            id: UUID(),
            noteID: id,
            heading: section.heading,
            level: section.level,
            lineStart: index * 10 + 1,
            lineEnd: index * 10 + 9,
            sectionIndex: index,
            contentHash: "hash-\(index)",
            plainText: section.text
        )
    }
    return SearchDocument(
        id: id,
        relativePath: relativePath,
        title: title,
        folderPath: (relativePath as NSString).deletingLastPathComponent,
        contentHash: "note-hash-\(title)",
        plainText: plainText ?? sections.map { "\($0.heading)\n\($0.text)" }.joined(separator: "\n"),
        sections: builtSections
    )
}

/// Repeats a sentence until the estimated token count exceeds `tokens`.
func longText(approximateTokens tokens: Int) -> String {
    let sentence = "The quarterly review covered revenue retention onboarding and roadmap items in detail."
    var text = sentence
    while SemanticChunker.estimatedTokens(text) <= tokens {
        text += "\n" + sentence
    }
    return text
}
