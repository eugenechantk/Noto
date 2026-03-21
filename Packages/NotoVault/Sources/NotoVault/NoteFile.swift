import Foundation

/// A note stored as a markdown file on disk.
/// Title is derived from the first line of content.
public struct NoteFile: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var content: String
    public let createdAt: Date
    public var modifiedAt: Date

    public init(id: UUID = UUID(), content: String = "", createdAt: Date = Date(), modifiedAt: Date = Date()) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// Title derived from the first non-empty line of content, or "Untitled" if empty.
    public var title: String {
        let firstLine = content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        guard let line = firstLine, !line.isEmpty else { return "Untitled" }
        // Strip leading markdown heading markers
        var stripped = line
        while stripped.hasPrefix("#") {
            stripped = String(stripped.dropFirst())
        }
        stripped = stripped.trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? "Untitled" : stripped
    }
}
