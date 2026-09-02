import Foundation

public struct TagDefinition: Codable, Sendable, Equatable, Identifiable {
    public let name: TagName
    public var template: String
    public var createdAt: Date
    public var modifiedAt: Date

    public init(name: TagName, template: String = "", createdAt: Date = .now, modifiedAt: Date = .now) {
        self.name = name
        self.template = template
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    public var id: TagName { name }

    private enum CodingKeys: String, CodingKey {
        case name
        case template
        case createdAt
        case modifiedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let rawName = try container.decode(String.self, forKey: .name)
        guard let tagName = TagName(rawName) else {
            throw DecodingError.dataCorruptedError(forKey: .name, in: container, debugDescription: "Invalid tag name: \(rawName)")
        }

        self.name = tagName
        self.template = try container.decodeIfPresent(String.self, forKey: .template) ?? ""
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
    }
}
