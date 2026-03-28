import Foundation

// MARK: - Tool Definition

public struct ToolDefinition: Encodable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: ToolInputSchema

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }

    public init(name: String, description: String, inputSchema: ToolInputSchema) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

// MARK: - Tool Input Schema

public struct ToolInputSchema: Encodable, Sendable {
    public let type: String
    public let properties: [String: PropertySchema]?
    public let items: PropertySchema?
    public let required: [String]?

    public init(
        type: String,
        properties: [String: PropertySchema]? = nil,
        items: PropertySchema? = nil,
        required: [String]? = nil
    ) {
        self.type = type
        self.properties = properties
        self.items = items
        self.required = required
    }
}

// MARK: - Property Schema

/// Uses a class (reference type) to support recursive nesting (items, properties).
public final class PropertySchema: Encodable, Sendable {
    public let type: String
    public let description: String?
    public let items: PropertySchema?
    public let properties: [String: PropertySchema]?
    public let `enum`: [String]?

    enum CodingKeys: String, CodingKey {
        case type
        case description
        case items
        case properties
        case `enum`
    }

    public init(
        type: String,
        description: String? = nil,
        items: PropertySchema? = nil,
        properties: [String: PropertySchema]? = nil,
        enum enumValues: [String]? = nil
    ) {
        self.type = type
        self.description = description
        self.items = items
        self.properties = properties
        self.enum = enumValues
    }
}
