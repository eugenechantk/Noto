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
    /// Creation timestamp from frontmatter `created:`, when present.
    public let createdAt: Date?

    public init(
        id: UUID,
        relativePath: String,
        title: String,
        folderPath: String,
        contentHash: String,
        plainText: String,
        sections: [SearchSection],
        createdAt: Date? = nil
    ) {
        self.id = id
        self.relativePath = relativePath
        self.title = title
        self.folderPath = folderPath
        self.contentHash = contentHash
        self.plainText = plainText
        self.sections = sections
        self.createdAt = createdAt
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
    /// Filesystem creation date — fallback when frontmatter has no `created:`.
    public let fileCreatedAt: Date?

    public init(document: SearchDocument, fileModifiedAt: Date, fileSize: Int, fileCreatedAt: Date? = nil) {
        self.document = document
        self.fileModifiedAt = fileModifiedAt
        self.fileSize = fileSize
        self.fileCreatedAt = fileCreatedAt
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
    public let createdAt: Date?

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
        updatedAt: Date?,
        createdAt: Date? = nil
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
        self.createdAt = createdAt
    }
}

/// Range constraints on a note's created / last-updated timestamps.
/// Bounds are inclusive. A note with an unknown created date fails any
/// created-bound check (rows self-heal to known values on the next refresh).
public struct SearchDateFilter: Sendable, Equatable {
    public var createdAfter: Date?
    public var createdBefore: Date?
    public var updatedAfter: Date?
    public var updatedBefore: Date?

    public init(
        createdAfter: Date? = nil,
        createdBefore: Date? = nil,
        updatedAfter: Date? = nil,
        updatedBefore: Date? = nil
    ) {
        self.createdAfter = createdAfter
        self.createdBefore = createdBefore
        self.updatedAfter = updatedAfter
        self.updatedBefore = updatedBefore
    }

    public var isActive: Bool {
        createdAfter != nil || createdBefore != nil || updatedAfter != nil || updatedBefore != nil
    }

    public func matches(created: Date?, updated: Date?) -> Bool {
        if createdAfter != nil || createdBefore != nil {
            guard let created else { return false }
            if let bound = createdAfter, created < bound { return false }
            if let bound = createdBefore, created > bound { return false }
        }
        if updatedAfter != nil || updatedBefore != nil {
            guard let updated else { return false }
            if let bound = updatedAfter, updated < bound { return false }
            if let bound = updatedBefore, updated > bound { return false }
        }
        return true
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
