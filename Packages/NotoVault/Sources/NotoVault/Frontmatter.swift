import Foundation

/// Parses and serializes YAML frontmatter in markdown files.
/// Supports a minimal subset: id, created, modified.
enum Frontmatter {

    struct Metadata {
        let id: UUID
        let createdAt: Date
        let modifiedAt: Date
    }

    /// Parses frontmatter from a markdown string.
    /// Returns the metadata and the body (content after frontmatter).
    static func parse(_ markdown: String) -> (metadata: Metadata?, body: String) {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else {
            return (nil, markdown)
        }

        // Find closing ---
        let lines = markdown.components(separatedBy: "\n")
        guard let firstDashIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return (nil, markdown)
        }

        let remaining = lines.dropFirst(firstDashIndex + 1)
        guard let closingDashIndex = remaining.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return (nil, markdown)
        }

        let frontmatterLines = lines[(firstDashIndex + 1)..<closingDashIndex]
        let bodyLines = lines[(closingDashIndex + 1)...]
        let body = bodyLines.joined(separator: "\n")

        // Parse simple key: value pairs
        var dict: [String: String] = [:]
        for line in frontmatterLines {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            dict[key] = value
        }

        guard let idString = dict["id"], let id = UUID(uuidString: idString) else {
            return (nil, markdown)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let createdAt = dict["created"].flatMap { formatter.date(from: $0) } ?? Date()
        let modifiedAt = dict["modified"].flatMap { formatter.date(from: $0) } ?? Date()

        let metadata = Metadata(id: id, createdAt: createdAt, modifiedAt: modifiedAt)

        // Strip leading newline from body if present
        let trimmedBody: String
        if body.hasPrefix("\n") {
            trimmedBody = String(body.dropFirst())
        } else {
            trimmedBody = body
        }

        return (metadata, trimmedBody)
    }

    /// Serializes a NoteFile into a markdown string with frontmatter.
    static func serialize(_ note: NoteFile) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var result = "---\n"
        result += "id: \(note.id.uuidString)\n"
        result += "created: \(formatter.string(from: note.createdAt))\n"
        result += "modified: \(formatter.string(from: note.modifiedAt))\n"
        result += "---\n"
        result += note.content
        return result
    }
}
