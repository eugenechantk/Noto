import Foundation

/// Each pushed note retains its own Find intent. Following a link inside a note
/// does not inherit the query that opened its parent.
struct SearchNavigation: Hashable {
    let destination: BrowseDestination
    let initialFindQuery: String?

    init(destination: BrowseDestination, query: String? = nil) {
        self.destination = destination
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        initialFindQuery = trimmed?.isEmpty == false ? trimmed : nil
    }
}
