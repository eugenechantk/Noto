import Foundation

/// Templates that pre-populate note content on creation.
enum NoteTemplate {
    case dailyNote

    /// The markdown body (excluding frontmatter and title heading) to insert.
    var body: String {
        switch self {
        case .dailyNote:
            return """
            ## What did I do today?

            ## What's on my mind today?

            ## How do I feel today? Why am I feeling this way?

            ## What will I do with this information?

            """
        }
    }

    /// The first heading from the template, used to detect if the template has already been applied.
    private var marker: String {
        switch self {
        case .dailyNote:
            return "## What did I do today?"
        }
    }

    /// Returns true if the content already contains this template's headings.
    func isApplied(in content: String) -> Bool {
        content.contains(marker)
    }

    /// Applies the template to existing content by inserting the body after the title heading.
    /// Returns nil if the template is already present.
    func applyRetroactively(to content: String) -> String? {
        guard !isApplied(in: content) else { return nil }

        // Insert template body after the first heading line (# Title)
        let body = MarkdownNote.stripFrontmatter(content)
        guard let firstNewline = body.firstIndex(of: "\n") else {
            // No newline after title — append template
            return content + "\n" + self.body
        }

        // Find the position of the first newline in the original content
        let titleEnd = content.distance(from: content.startIndex, to: content.endIndex)
            - content.distance(from: body.startIndex, to: body.endIndex)
            + content.distance(from: body.startIndex, to: firstNewline)

        let insertIdx = content.index(content.startIndex, offsetBy: titleEnd)
        var result = content
        result.insert(contentsOf: self.body, at: content.index(after: insertIdx))
        return result
    }
}
