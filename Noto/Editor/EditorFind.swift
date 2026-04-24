import Foundation

enum EditorFindNavigationDirection: Equatable {
    case next
    case previous
}

struct EditorFindNavigationRequest: Equatable {
    let id: Int
    let direction: EditorFindNavigationDirection
}

struct EditorFindStatus: Equatable {
    var matchCount: Int = 0
    var selectedMatchIndex: Int?

    var displayText: String {
        guard matchCount > 0, let selectedMatchIndex else {
            return "0/0"
        }
        return "\(selectedMatchIndex + 1)/\(matchCount)"
    }
}

enum EditorFindMatcher {
    static func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func ranges(in text: String, query: String) -> [NSRange] {
        let query = normalizedQuery(query)
        guard !query.isEmpty else { return [] }

        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        var ranges: [NSRange] = []
        var searchLocation = 0
        while searchLocation < nsText.length {
            let searchRange = NSRange(
                location: searchLocation,
                length: nsText.length - searchLocation
            )
            let match = nsText.range(
                of: query,
                options: [.caseInsensitive],
                range: searchRange
            )
            guard match.location != NSNotFound, match.length > 0 else {
                break
            }

            ranges.append(match)
            searchLocation = match.location + match.length
        }

        return ranges
    }

    static func preferredIndex(for matches: [NSRange], selectionLocation: Int) -> Int? {
        guard !matches.isEmpty else { return nil }

        if let containingIndex = matches.firstIndex(where: { NSLocationInRange(selectionLocation, $0) }) {
            return containingIndex
        }

        if let followingIndex = matches.firstIndex(where: { $0.location >= selectionLocation }) {
            return followingIndex
        }

        return 0
    }

    static func navigatedIndex(
        from currentIndex: Int?,
        matchCount: Int,
        direction: EditorFindNavigationDirection
    ) -> Int? {
        guard matchCount > 0 else { return nil }
        guard let currentIndex else {
            return direction == .next ? 0 : matchCount - 1
        }

        switch direction {
        case .next:
            return (currentIndex + 1) % matchCount
        case .previous:
            return (currentIndex - 1 + matchCount) % matchCount
        }
    }
}

