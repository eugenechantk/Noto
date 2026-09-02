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

    /// Refreshes whichever write-timestamp keys the note *already* has, to `date`.
    ///
    /// This vault carries two conventions: `VaultMarkdown.makeFrontmatter` (and so
    /// every note the editor creates) writes `updated:`, while the main Noto app's
    /// AI/agent paths and older notes write `modified:`. A programmatic write that
    /// only knows one of them silently leaves the other stale, which is how a note
    /// ends up claiming it was last touched in March.
    ///
    /// Both keys are stamped when both are present, and **no key is invented** —
    /// a note that tracks neither keeps tracking neither. Returns the input
    /// unchanged when there is no frontmatter.
    public static func stampingExistingTimestamps(_ markdown: String, to date: Date) -> String {
        guard let lines = frontmatterLines(of: markdown) else { return markdown }
        var all = lines.all
        let stamp = iso.string(from: date)
        var didStamp = false

        for index in lines.range {
            let key = all[index].split(separator: ":", maxSplits: 1).first
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            guard key == "updated" || key == "modified" else { continue }
            all[index] = "\(key!): \(stamp)"
            didStamp = true
        }
        return didStamp ? all.joined(separator: "\n") : markdown
    }

    /// The raw string value of `key` in the frontmatter, or `nil` when there is
    /// no frontmatter or no such key. Keys are matched case-insensitively; the
    /// value keeps its own case and inner colons (`snoozed_until: 2026-09-08T12:00:00Z`).
    public static func value(for key: String, in markdown: String) -> String? {
        guard let lines = frontmatterLines(of: markdown) else { return nil }
        let wanted = key.lowercased()
        for line in lines.body {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).lowercased() == wanted else { continue }
            return parts[1].trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Sets `key` to `value` in the frontmatter, preserving every other line and
    /// the body exactly. An existing key is rewritten in place (never duplicated);
    /// a missing one is appended just before the closing `---`. Markdown without
    /// frontmatter is returned unchanged — callers that need the key must write
    /// the frontmatter themselves.
    public static func setting(_ key: String, to value: String, in markdown: String) -> String {
        guard let lines = frontmatterLines(of: markdown) else { return markdown }
        var all = lines.all
        let wanted = key.lowercased()
        for index in lines.range {
            let existing = all[index].split(separator: ":", maxSplits: 1).first
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            if existing == wanted {
                all[index] = "\(key): \(value)"
                return all.joined(separator: "\n")
            }
        }
        all.insert("\(key): \(value)", at: lines.close)
        return all.joined(separator: "\n")
    }

    /// Removes `key` from the frontmatter if present, leaving everything else
    /// untouched.
    public static func removing(_ key: String, in markdown: String) -> String {
        guard let lines = frontmatterLines(of: markdown) else { return markdown }
        var all = lines.all
        let wanted = key.lowercased()
        for index in lines.range.reversed() {
            let existing = all[index].split(separator: ":", maxSplits: 1).first
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            if existing == wanted {
                all.remove(at: index)
            }
        }
        return all.joined(separator: "\n")
    }

    /// Splits `markdown` into its lines plus the index range of the frontmatter's
    /// interior, or `nil` when there is no well-formed `---` block at the top.
    private static func frontmatterLines(
        of markdown: String
    ) -> (all: [String], range: Range<Int>, close: Int, body: ArraySlice<String>)? {
        guard markdown.hasPrefix("---") else { return nil }
        let all = markdown.components(separatedBy: "\n")
        guard all.first?.trimmingCharacters(in: .whitespaces) == "---",
              let close = all.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return nil }
        let range = 1..<close
        return (all, range, close, all[range])
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
