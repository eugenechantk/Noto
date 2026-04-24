import Foundation

public struct SaveDocumentRequest: Encodable, Sendable, Equatable {
    public let url: String
    public let title: String?
    public let author: String?
    public let tags: [String]?
    public let location: String?
    public let category: String?
    public let summary: String?
    public let notes: String?
    public let publishedDate: String?
    public let imageURL: String?

    public init(
        url: String,
        title: String? = nil,
        author: String? = nil,
        tags: [String]? = nil,
        location: String? = nil,
        category: String? = nil,
        summary: String? = nil,
        notes: String? = nil,
        publishedDate: String? = nil,
        imageURL: String? = nil
    ) {
        self.url = url
        self.title = title
        self.author = author
        self.tags = tags
        self.location = location
        self.category = category
        self.summary = summary
        self.notes = notes
        self.publishedDate = publishedDate
        self.imageURL = imageURL
    }

    enum CodingKeys: String, CodingKey {
        case url
        case title
        case author
        case tags
        case location
        case category
        case summary
        case notes
        case publishedDate = "published_date"
        case imageURL = "image_url"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(publishedDate, forKey: .publishedDate)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
    }
}

public struct SaveDocumentResponse: Decodable, Sendable, Equatable {
    public let id: String
    public let url: String

    public init(id: String, url: String) {
        self.id = id
        self.url = url
    }
}

public struct SaveOutcome: Sendable, Equatable {
    public enum Status: String, Sendable {
        case created
        case existing
    }

    public let status: Status
    public let response: SaveDocumentResponse

    public init(status: Status, response: SaveDocumentResponse) {
        self.status = status
        self.response = response
    }
}
