import Foundation
import Testing
@testable import Noto

#if os(iOS)
import UIKit
#endif

@Suite("Editor Find")
struct EditorFindTests {
    @Test("Empty and whitespace-only queries produce no matches")
    func emptyQueriesProduceNoMatches() {
        #expect(EditorFindMatcher.ranges(in: "Alpha beta", query: "").isEmpty)
        #expect(EditorFindMatcher.ranges(in: "Alpha beta", query: "   \n").isEmpty)
    }

    @Test("Search matches are case-insensitive")
    func searchMatchesAreCaseInsensitive() {
        let ranges = EditorFindMatcher.ranges(in: "Alpha alpha ALPHA", query: "alpha")

        #expect(ranges == [
            NSRange(location: 0, length: 5),
            NSRange(location: 6, length: 5),
            NSRange(location: 12, length: 5),
        ])
    }

    @Test("Search uses literal non-overlapping substring matches")
    func searchUsesLiteralNonOverlappingMatches() {
        let ranges = EditorFindMatcher.ranges(in: "bananana", query: "ana")

        #expect(ranges == [
            NSRange(location: 1, length: 3),
            NSRange(location: 5, length: 3),
        ])
    }

    @Test("Search uses UTF-16 ranges compatible with TextKit")
    func searchUsesUTF16Ranges() {
        let ranges = EditorFindMatcher.ranges(in: "Hi 🟡 Alpha", query: "alpha")

        #expect(ranges == [NSRange(location: 6, length: 5)])
    }

    @Test("Preferred index starts at current or following match and wraps to first")
    func preferredIndexStartsAtCurrentOrFollowingMatch() {
        let matches = [
            NSRange(location: 2, length: 4),
            NSRange(location: 10, length: 4),
        ]

        #expect(EditorFindMatcher.preferredIndex(for: matches, selectionLocation: 3) == 0)
        #expect(EditorFindMatcher.preferredIndex(for: matches, selectionLocation: 7) == 1)
        #expect(EditorFindMatcher.preferredIndex(for: matches, selectionLocation: 20) == 0)
    }

    @Test("Navigation wraps through all matches")
    func navigationWrapsThroughMatches() {
        #expect(EditorFindMatcher.navigatedIndex(from: nil, matchCount: 3, direction: .next) == 0)
        #expect(EditorFindMatcher.navigatedIndex(from: nil, matchCount: 3, direction: .previous) == 2)
        #expect(EditorFindMatcher.navigatedIndex(from: 2, matchCount: 3, direction: .next) == 0)
        #expect(EditorFindMatcher.navigatedIndex(from: 0, matchCount: 3, direction: .previous) == 2)
    }

    #if os(iOS)
    @MainActor
    @Test("TextKit controller highlights matches and navigates between occurrences")
    func textKitControllerHighlightsAndNavigatesMatches() throws {
        let controller = TextKit2EditorViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.loadText("Alpha beta alpha")

        var latestStatus = EditorFindStatus()
        controller.updateFind(query: "alpha", navigationRequest: nil) { status in
            latestStatus = status
        }

        #expect(latestStatus == EditorFindStatus(matchCount: 2, selectedMatchIndex: 0))
        #expect(controller.textView.textStorage.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil)
        #expect(controller.textView.textStorage.attribute(.backgroundColor, at: 11, effectiveRange: nil) != nil)

        controller.updateFind(
            query: "alpha",
            navigationRequest: EditorFindNavigationRequest(id: 1, direction: .next)
        ) { status in
            latestStatus = status
        }

        #expect(latestStatus == EditorFindStatus(matchCount: 2, selectedMatchIndex: 1))
        #expect(controller.textView.selectedRange == NSRange(location: 11, length: 5))
    }
    #endif
}
