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
}
