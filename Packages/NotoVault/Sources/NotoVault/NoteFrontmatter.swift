import Foundation

/// Public frontmatter utilities for programmatic note writes. The `modified:`
/// timestamp is a property of *writing the file* — any programmatic edit (AI
/// suggestions, automations, future tools) stamps it here at the file-IO
/// boundary, independent of whether an editor is open.
public enum NoteFrontmatter {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Surgically set the `modified:` timestamp in a markdown file's YAML
    /// frontmatter to `date` (ISO-8601), preserving every other field and the
    /// body exactly. If there's no frontmatter, returns the input unchanged; if
    /// there's frontmatter without a `modified:` line, one is inserted.
    public static func stampingModified(_ markdown: String, to date: Date) -> String {
        guard markdown.hasPrefix("---") else { return markdown }
        var lines = markdown.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return markdown }

        let stamp = iso.string(from: date)
        for i in 1..<close {
            let key = lines[i].split(separator: ":", maxSplits: 1).first
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            if key == "modified" {
                lines[i] = "modified: \(stamp)"
                return lines.joined(separator: "\n")
            }
        }
        // Frontmatter present but no `modified:` line — insert one before the close.
        lines.insert("modified: \(stamp)", at: close)
        return lines.joined(separator: "\n")
    }

    /// The `id:` UUID from a markdown file's frontmatter, if present.
    public static func id(of markdown: String) -> UUID? {
        guard markdown.hasPrefix("---") else { return nil }
        let lines = markdown.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return nil }
        for i in 1..<close {
            let parts = lines[i].split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "id" else { continue }
            return UUID(uuidString: parts[1].trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}
