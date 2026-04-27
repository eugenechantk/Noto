import Foundation

public enum SearchResultKind: Sendable, Equatable {
    case note
    case section
}

public enum SearchScope: Sendable, Equatable, Hashable {
    case title
    case titleAndContent
}

public struct SearchDocument: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let relativePath: String
    public let title: String
    public let folderPath: String
    public let contentHash: String
    public let plainText: String
    public let sections: [SearchSection]

    public init(
        id: UUID,
        relativePath: String,
        title: String,
        folderPath: String,
        contentHash: String,
        plainText: String,
        sections: [SearchSection]
    ) {
        self.id = id
        self.relativePath = relativePath
        self.title = title
        self.folderPath = folderPath
        self.contentHash = contentHash
        self.plainText = plainText
        self.sections = sections
    }
}

public struct SearchSection: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let noteID: UUID
    public let heading: String
    public let level: Int?
    public let lineStart: Int
    public let lineEnd: Int
    public let sectionIndex: Int
    public let contentHash: String
    public let plainText: String

    public init(
        id: UUID,
        noteID: UUID,
        heading: String,
        level: Int?,
        lineStart: Int,
        lineEnd: Int,
        sectionIndex: Int,
        contentHash: String,
        plainText: String
    ) {
        self.id = id
        self.noteID = noteID
        self.heading = heading
        self.level = level
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.sectionIndex = sectionIndex
        self.contentHash = contentHash
        self.plainText = plainText
    }
}

public struct SearchIndexStats: Sendable, Equatable {
    public let noteCount: Int
    public let sectionCount: Int

    public init(noteCount: Int, sectionCount: Int) {
        self.noteCount = noteCount
        self.sectionCount = sectionCount
    }
}

public struct SearchIndexedDocument: Sendable, Equatable {
    public let document: SearchDocument
    public let fileModifiedAt: Date
    public let fileSize: Int

    public init(document: SearchDocument, fileModifiedAt: Date, fileSize: Int) {
        self.document = document
        self.fileModifiedAt = fileModifiedAt
        self.fileSize = fileSize
    }
}

public struct SearchIndexRefreshResult: Sendable, Equatable {
    public let scanned: Int
    public let upserted: Int
    public let deleted: Int
    public let stats: SearchIndexStats

    public init(scanned: Int, upserted: Int, deleted: Int, stats: SearchIndexStats) {
        self.scanned = scanned
        self.upserted = upserted
        self.deleted = deleted
        self.stats = stats
    }
}

public struct SearchResult: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let kind: SearchResultKind
    public let noteID: UUID
    public let fileURL: URL
    public let title: String
    public let breadcrumb: String
    public let snippet: String
    public let lineStart: Int?
    public let score: Double
    public let updatedAt: Date?

    public init(
        id: UUID,
        kind: SearchResultKind,
        noteID: UUID,
        fileURL: URL,
        title: String,
        breadcrumb: String,
        snippet: String,
        lineStart: Int?,
        score: Double,
        updatedAt: Date?
    ) {
        self.id = id
        self.kind = kind
        self.noteID = noteID
        self.fileURL = fileURL
        self.title = title
        self.breadcrumb = breadcrumb
        self.snippet = snippet
        self.lineStart = lineStart
        self.score = score
        self.updatedAt = updatedAt
    }
}

public enum SearchResultDisplayPolicy {
    public static func hidingNoteMatchesCoveredBySections(_ results: [SearchResult]) -> [SearchResult] {
        let noteIDsWithSectionMatches = Set(results.filter { $0.kind == .section }.map(\.noteID))
        guard !noteIDsWithSectionMatches.isEmpty else { return results }
        return results.filter { result in
            !(result.kind == .note && noteIDsWithSectionMatches.contains(result.noteID))
        }
    }
}
