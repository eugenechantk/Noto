import Foundation

public struct ReadwiseExportPage: Codable, Sendable {
    public let count: Int?
    public let nextPageCursor: String?
    public let results: [ReadwiseBook]

    public init(count: Int?, nextPageCursor: String?, results: [ReadwiseBook]) {
        self.count = count
        self.nextPageCursor = nextPageCursor
        self.results = results
    }

    enum CodingKeys: String, CodingKey {
        case count
        case nextPageCursor
        case results
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = try container.decodeIfPresent(Int.self, forKey: .count)
        results = try container.decode([ReadwiseBook].self, forKey: .results)

        if let cursor = try? container.decodeIfPresent(String.self, forKey: .nextPageCursor) {
            nextPageCursor = cursor
        } else if let cursor = try? container.decodeIfPresent(Int.self, forKey: .nextPageCursor) {
            nextPageCursor = String(cursor)
        } else {
            nextPageCursor = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(count, forKey: .count)
        try container.encodeIfPresent(nextPageCursor, forKey: .nextPageCursor)
        try container.encode(results, forKey: .results)
    }
}

public struct ReadwiseBook: Codable, Sendable {
    public let userBookID: Int
    public let isDeleted: Bool
    public let title: String?
    public let readableTitle: String?
    public let author: String?
    public let source: String?
    public let coverImageURL: String?
    public let uniqueURL: String?
    public let category: String?
    public let documentNote: String?
    public let summary: String?
    public let readwiseURL: String?
    public let sourceURL: String?
    public let externalID: String?
    public let asin: String?
    public var highlights: [ReadwiseHighlight]

    public init(
        userBookID: Int,
        isDeleted: Bool = false,
        title: String?,
        readableTitle: String? = nil,
        author: String? = nil,
        source: String? = nil,
        coverImageURL: String? = nil,
        uniqueURL: String? = nil,
        category: String? = nil,
        documentNote: String? = nil,
        summary: String? = nil,
        readwiseURL: String? = nil,
        sourceURL: String? = nil,
        externalID: String? = nil,
        asin: String? = nil,
        highlights: [ReadwiseHighlight] = []
    ) {
        self.userBookID = userBookID
        self.isDeleted = isDeleted
        self.title = title
        self.readableTitle = readableTitle
        self.author = author
        self.source = source
        self.coverImageURL = coverImageURL
        self.uniqueURL = uniqueURL
        self.category = category
        self.documentNote = documentNote
        self.summary = summary
        self.readwiseURL = readwiseURL
        self.sourceURL = sourceURL
        self.externalID = externalID
        self.asin = asin
        self.highlights = highlights
    }

    enum CodingKeys: String, CodingKey {
        case userBookID = "user_book_id"
        case isDeleted = "is_deleted"
        case title
        case readableTitle = "readable_title"
        case author
        case source
        case coverImageURL = "cover_image_url"
        case uniqueURL = "unique_url"
        case category
        case documentNote = "document_note"
        case summary
        case readwiseURL = "readwise_url"
        case sourceURL = "source_url"
        case externalID = "external_id"
        case asin
        case highlights
    }
}

public extension ReadwiseBook {
    var displayTitle: String {
        readableTitle.nonEmpty ?? title.nonEmpty ?? "Untitled Source"
    }

    var sourceKind: String {
        switch category?.lowercased() {
        case "articles": "article"
        case "books": "book"
        case "tweets": "tweet"
        case "podcasts": "podcast"
        default: category?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? source?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? "source"
        }
    }

    var canonicalKey: String {
        if source == "reader", let externalID = externalID.nonEmpty {
            return "reader:\(externalID)"
        }
        return "readwise-book:\(userBookID)"
    }

    var preferredSourceURL: String? {
        sourceURL.nonEmpty ?? uniqueURL.nonEmpty
    }

    var readerWebURL: String? {
        guard source == "reader", let externalID = externalID.nonEmpty else {
            return nil
        }
        return "https://read.readwise.io/read/\(externalID)"
    }

    var activeHighlights: [ReadwiseHighlight] {
        highlights
            .filter { !$0.isDeleted }
            .sorted { lhs, rhs in
                switch (lhs.location, rhs.location) {
                case let (left?, right?) where left != right:
                    left < right
                default:
                    lhs.id < rhs.id
                }
            }
    }
}

public struct ReadwiseHighlight: Codable, Sendable {
    public let id: Int
    public let isDeleted: Bool
    public let text: String
    public let note: String?
    public let location: Int?
    public let locationType: String?
    public let highlightedAt: String?
    public let updatedAt: String?
    public let url: String?
    public let readwiseURL: String?
    public let externalID: String?

    public init(
        id: Int,
        isDeleted: Bool = false,
        text: String,
        note: String? = nil,
        location: Int? = nil,
        locationType: String? = nil,
        highlightedAt: String? = nil,
        updatedAt: String? = nil,
        url: String? = nil,
        readwiseURL: String? = nil,
        externalID: String? = nil
    ) {
        self.id = id
        self.isDeleted = isDeleted
        self.text = text
        self.note = note
        self.location = location
        self.locationType = locationType
        self.highlightedAt = highlightedAt
        self.updatedAt = updatedAt
        self.url = url
        self.readwiseURL = readwiseURL
        self.externalID = externalID
    }

    enum CodingKeys: String, CodingKey {
        case id
        case isDeleted = "is_deleted"
        case text
        case note
        case location
        case locationType = "location_type"
        case highlightedAt = "highlighted_at"
        case updatedAt = "updated_at"
        case url
        case readwiseURL = "readwise_url"
        case externalID = "external_id"
    }
}

public extension JSONDecoder {
    static var readwise: JSONDecoder {
        JSONDecoder()
    }
}

public extension JSONEncoder {
    static var readwise: JSONEncoder {
        JSONEncoder()
    }
}

extension String? {
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
