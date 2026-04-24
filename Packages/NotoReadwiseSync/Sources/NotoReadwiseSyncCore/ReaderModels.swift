import Foundation

public struct ReaderListPage: Codable, Sendable {
    public let count: Int?
    public let nextPageCursor: String?
    public let results: [ReaderDocument]

    enum CodingKeys: String, CodingKey {
        case count
        case nextPageCursor
        case results
    }

    public init(count: Int?, nextPageCursor: String?, results: [ReaderDocument]) {
        self.count = count
        self.nextPageCursor = nextPageCursor
        self.results = results
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = try container.decodeIfPresent(Int.self, forKey: .count)
        results = try container.decode([ReaderDocument].self, forKey: .results)

        if let cursor = try? container.decodeIfPresent(String.self, forKey: .nextPageCursor) {
            nextPageCursor = cursor
        } else if let cursor = try? container.decodeIfPresent(Int.self, forKey: .nextPageCursor) {
            nextPageCursor = String(cursor)
        } else {
            nextPageCursor = nil
        }
    }
}

public struct ReaderDocument: Codable, Sendable {
    public let id: String
    public let url: String?
    public let sourceURL: String?
    public let title: String?
    public let author: String?
    public let source: String?
    public let category: String?
    public let location: String?
    public let siteName: String?
    public let wordCount: Int?
    public let readingTime: String?
    public let createdAt: String?
    public let updatedAt: String?
    public let notes: String?
    public let publishedDate: String?
    public let summary: String?
    public let imageURL: String?
    public let parentID: String?
    public let savedAt: String?
    public let tags: [String]
    public let htmlContent: String?
    public let rawSourceURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case sourceURL = "source_url"
        case title
        case author
        case source
        case category
        case location
        case siteName = "site_name"
        case wordCount = "word_count"
        case readingTime = "reading_time"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case notes
        case publishedDate = "published_date"
        case summary
        case imageURL = "image_url"
        case parentID = "parent_id"
        case savedAt = "saved_at"
        case tags
        case htmlContent = "html_content"
        case rawSourceURL = "raw_source_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        siteName = try container.decodeIfPresent(String.self, forKey: .siteName)
        wordCount = try container.decodeIfPresent(Int.self, forKey: .wordCount)
        readingTime = try container.decodeIfPresent(String.self, forKey: .readingTime)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        publishedDate = try container.decodeIfPresent(String.self, forKey: .publishedDate)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        parentID = try container.decodeIfPresent(String.self, forKey: .parentID)
        savedAt = try container.decodeIfPresent(String.self, forKey: .savedAt)
        htmlContent = try container.decodeIfPresent(String.self, forKey: .htmlContent)
        rawSourceURL = try container.decodeIfPresent(String.self, forKey: .rawSourceURL)

        let decodedTags = try container.decodeIfPresent([String: ReaderTag].self, forKey: .tags) ?? [:]
        tags = Array(Set(decodedTags.values.compactMap { $0.name.nonEmpty })).sorted()
    }
}

private struct ReaderTag: Codable, Sendable {
    let name: String?
}

public extension ReaderDocument {
    var displayTitle: String {
        title.nonEmpty ?? "Untitled Reader Document"
    }

    var sourceKind: String {
        switch category?.lowercased() {
        case "tweet": "tweet"
        case "video": "video"
        case "pdf": "pdf"
        case "epub": "epub"
        case "rss": "rss"
        case "email": "email"
        default: category?.lowercased().nonEmpty ?? "article"
        }
    }

    var canonicalKey: String {
        "reader:\(id)"
    }

    var preferredSourceURL: String? {
        sourceURL.nonEmpty ?? url.nonEmpty
    }

    var readerWebURL: String {
        if let url = url.nonEmpty, url.contains("read.readwise.io") || url.contains("readwise.io/reader") {
            return url
        }
        return "https://read.readwise.io/read/\(id)"
    }

    var isTopLevelDocument: Bool {
        parentID.nonEmpty == nil
    }

    var contentMarkdown: String {
        HTMLToMarkdown.convert(htmlContent.nonEmpty ?? "")
    }

    func matchesAllTags(_ requestedTags: [String]) -> Bool {
        let normalizedRequestedTags = requestedTags.compactMap { Self.normalizedTag($0) }
        guard !normalizedRequestedTags.isEmpty else {
            return true
        }

        let documentTags = Set(tags.compactMap { Self.normalizedTag($0) })
        return normalizedRequestedTags.allSatisfy { documentTags.contains($0) }
    }

    private static func normalizedTag(_ tag: String) -> String? {
        let value = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.isEmpty ? nil : value
    }
}
