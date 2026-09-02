import Foundation

public enum TagTemplateApplier {
    public static func apply(template: String, forTag tag: TagName, to content: String) -> String {
        guard !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return content
        }

        guard !isApplied(template: template, forTag: tag, in: content) else {
            return content
        }

        let marker = marker(for: tag)
        let sanitizedContent = content.replacingOccurrences(of: #"\n+$"#, with: "", options: .regularExpression)
        let separator = sanitizedContent.isEmpty ? "" : "\n\n"
        let normalizedTemplate = template.trimmingCharacters(in: .newlines)

        return "\(sanitizedContent)\(separator)\(marker)\n\(normalizedTemplate)\n"
    }

    public static func isApplied(template: String, forTag tag: TagName, in content: String) -> Bool {
        content.contains(marker(for: tag))
    }

    private static func marker(for tag: TagName) -> String {
        "<!-- noto:tag-template:\(tag.rawValue) -->"
    }
}
