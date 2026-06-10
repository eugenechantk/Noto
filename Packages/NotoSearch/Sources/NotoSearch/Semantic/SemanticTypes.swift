import Foundation

/// Text-embedding provider injected by the app layer. NotoSearch never links the
/// embedding model directly so package tests stay fast and model-free.
public protocol TextEmbedding: Sendable {
    /// Identifies the model + revision. Stored with every vector; changing it
    /// invalidates the semantic index and triggers a full re-embed.
    var modelVersion: String { get }
    var dimensions: Int { get }
    /// Returns one L2-normalized vector per input text.
    func embed(_ texts: [String]) throws -> [[Float]]
}

/// One embeddable unit of a note: a whole small note, a heading section, or a
/// split part of an oversized section.
public struct SemanticChunk: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let noteID: UUID
    public let heading: String
    public let lineStart: Int
    public let lineEnd: Int
    /// What gets embedded: contextual header (`title > heading`) + body.
    public let embeddedText: String
    /// Body-only text used for display snippets.
    public let snippetText: String
    /// Hash of (model version + embedded text); the re-embed invalidation key.
    /// Image chunks hash (model + describer versions + image bytes) instead.
    public let contentHash: String
    public let kind: SemanticChunkKind
    /// For image chunks: the vault-relative path or remote URL of the image.
    public let imagePath: String?

    public init(
        id: UUID,
        noteID: UUID,
        heading: String,
        lineStart: Int,
        lineEnd: Int,
        embeddedText: String,
        snippetText: String,
        contentHash: String,
        kind: SemanticChunkKind = .text,
        imagePath: String? = nil
    ) {
        self.id = id
        self.noteID = noteID
        self.heading = heading
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.embeddedText = embeddedText
        self.snippetText = snippetText
        self.contentHash = contentHash
        self.kind = kind
        self.imagePath = imagePath
    }
}

public struct SemanticSearchHit: Sendable, Equatable {
    public let chunkID: UUID
    public let noteID: UUID
    public let relativePath: String
    public let noteTitle: String
    public let heading: String
    public let snippet: String
    public let lineStart: Int
    /// Cosine similarity in [-1, 1].
    public let score: Float
    public let kind: SemanticChunkKind
    public let imagePath: String?

    public init(
        chunkID: UUID,
        noteID: UUID,
        relativePath: String,
        noteTitle: String,
        heading: String,
        snippet: String,
        lineStart: Int,
        score: Float,
        kind: SemanticChunkKind = .text,
        imagePath: String? = nil
    ) {
        self.chunkID = chunkID
        self.noteID = noteID
        self.relativePath = relativePath
        self.noteTitle = noteTitle
        self.heading = heading
        self.snippet = snippet
        self.lineStart = lineStart
        self.score = score
        self.kind = kind
        self.imagePath = imagePath
    }
}

public struct SemanticIndexStats: Sendable, Equatable {
    public let noteCount: Int
    public let chunkCount: Int
    public let modelVersion: String?

    public init(noteCount: Int, chunkCount: Int, modelVersion: String?) {
        self.noteCount = noteCount
        self.chunkCount = chunkCount
        self.modelVersion = modelVersion
    }
}

public struct SemanticRefreshResult: Sendable, Equatable {
    public let scannedNotes: Int
    public let refreshedNotes: Int
    public let embeddedChunks: Int
    public let reusedChunks: Int
    public let deletedNotes: Int
    public let stats: SemanticIndexStats

    public init(
        scannedNotes: Int,
        refreshedNotes: Int,
        embeddedChunks: Int,
        reusedChunks: Int,
        deletedNotes: Int,
        stats: SemanticIndexStats
    ) {
        self.scannedNotes = scannedNotes
        self.refreshedNotes = refreshedNotes
        self.embeddedChunks = embeddedChunks
        self.reusedChunks = reusedChunks
        self.deletedNotes = deletedNotes
        self.stats = stats
    }

    public var didChangeIndex: Bool {
        refreshedNotes > 0 || deletedNotes > 0
    }
}
