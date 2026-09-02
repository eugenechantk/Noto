import Foundation

public struct TagName: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init?(_ input: String) {
        let normalized = Self.normalize(input)
        guard !normalized.isEmpty else { return nil }
        self.rawValue = normalized
    }

    public static func normalize(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutLeadingHash = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed

        let collapseWhitespaceOrUnderscore = withoutLeadingHash
            .lowercased()
            .replacingOccurrences(of: #"[\s_]+"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9-]"#, with: "", options: .regularExpression)

        let collapseDashes = collapseWhitespaceOrUnderscore
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)

        return collapseDashes.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    public var description: String {
        rawValue
    }

    public static func < (lhs: TagName, rhs: TagName) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let normalized = TagName(value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid tag name: \(value)"
            )
        }
        self = normalized
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
