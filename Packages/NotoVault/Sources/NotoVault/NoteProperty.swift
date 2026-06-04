import Foundation

/// Editable kinds for a note's frontmatter property, inferred from the key name
/// and value shape. `folder` is handled separately (it's derived from the file
/// location, not a frontmatter field).
public enum NotePropertyKind: String, Sendable, Equatable, CaseIterable {
    case text
    case date
    case tags
    case url
}

/// Classifies frontmatter (key, value) pairs into editable kinds and converts
/// tag values to/from their string representation. Pure logic — no UI.
public enum NotePropertyClassifier {
    private static let dateKeys: Set<String> = ["created", "modified", "updated", "published", "date"]

    public static func kind(key: String, value: String) -> NotePropertyKind {
        let k = key.lowercased()
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if k == "tags" || k == "keywords" || isList(v) { return .tags }
        if isURL(v) { return .url }
        if dateKeys.contains(k) || k.contains("date") || isDate(v) { return .date }
        return .text
    }

    public static func isURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    static func isList(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") { return true }
        return trimmed.hasPrefix("- ") || trimmed.contains("\n-")
    }

    public static func isDate(_ value: String) -> Bool {
        date(from: value) != nil
    }

    /// Parses a frontmatter date value (ISO8601 with time, or plain `yyyy-MM-dd`).
    public static func date(from value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        guard !trimmed.isEmpty else { return nil }
        if let iso = isoFormatter.date(from: trimmed) { return iso }
        if let day = dayFormatter.date(from: trimmed) { return day }
        return nil
    }

    /// Serializes a picked date back to a frontmatter string. Date-only values
    /// (no time component originally) round-trip as `yyyy-MM-dd`; others as ISO8601.
    public static func dateString(from date: Date, dateOnly: Bool) -> String {
        dateOnly ? dayFormatter.string(from: date) : isoFormatter.string(from: date)
    }

    /// Splits a tags value (inline `[a, b]` or YAML block list `- a`) into members.
    public static func parseTags(_ value: String) -> [String] {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            trimmed = String(trimmed.dropFirst().dropLast())
        }
        return trimmed
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { item -> String in
                var element = item.trimmingCharacters(in: .whitespaces)
                if element.hasPrefix("- ") { element = String(element.dropFirst(2)) }
                else if element.hasPrefix("-") { element = String(element.dropFirst()) }
                return element.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            }
            .filter { !$0.isEmpty }
    }

    /// Serializes tag members back to an inline YAML flow list (`[a, b, c]`).
    public static func serializeTags(_ tags: [String]) -> String {
        let cleaned = tags
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return "[" + cleaned.joined(separator: ", ") + "]"
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
