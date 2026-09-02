import Foundation

public struct TagRegistryStore {
    public init() {}

    public func load(from url: URL) throws -> TagRegistry {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return TagRegistry()
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            return TagRegistry()
        }

        let text = String(data: data, encoding: .utf8) ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return TagRegistry()
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TagRegistry.self, from: data)
    }

    public func save(_ registry: TagRegistry, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(registry)
        try data.write(to: url, options: [.atomic])
    }
}
