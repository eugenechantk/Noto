import Foundation

public struct TagRegistry: Codable, Sendable, Equatable {
    private var definitionsByName: [TagName: TagDefinition]

    public init(definitions: [TagDefinition] = []) {
        var map: [TagName: TagDefinition] = [:]
        definitions.forEach { definition in
            map[definition.name] = definition
        }
        self.definitionsByName = map
    }

    public init() {
        self.definitionsByName = [:]
    }

    public func definition(for name: TagName) -> TagDefinition? {
        definitionsByName[name]
    }

    public func allDefinitions() -> [TagDefinition] {
        definitionsByName.values.sorted { lhs, rhs in
            lhs.name < rhs.name
        }
    }

    public mutating func upsert(_ definition: TagDefinition) {
        definitionsByName[definition.name] = definition
    }

    public mutating func remove(_ name: TagName) {
        definitionsByName.removeValue(forKey: name)
    }

    public mutating func ensure(_ name: TagName, now: Date) -> TagDefinition {
        if let existing = definitionsByName[name] {
            return existing
        }

        let definition = TagDefinition(name: name, template: "", createdAt: now, modifiedAt: now)
        definitionsByName[name] = definition
        return definition
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let definitions = try container.decodeIfPresent([TagDefinition].self, forKey: .tags) ?? []
        var map: [TagName: TagDefinition] = [:]
        definitions.forEach { definition in
            map[definition.name] = definition
        }
        self.definitionsByName = map
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .version)
        try container.encode(allDefinitions(), forKey: .tags)
    }
}
