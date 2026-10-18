import Foundation
import Testing
@testable import Noto2

/// Test case index — the redesign's tab bar (T1, T2). Icons only; `title` is the accessibility label.
/// 1. tabBarOrderIsCaptureTodayInboxLibraryThenSearch — five tabs, Search last as the search-role tab
/// 2. tabsUseTheRedesignNames — accessibility names: Digest is Inbox, Browse is Library
/// 3. everyCurrentRawValueStillResolves — saved routes and debug keys keep working
/// 4. retiredMediaValueOpensLibrary — the removed Media tab lands in Library, never fails
/// 5. unknownValueResolvesToNil — junk does not pick a tab
struct Noto2TabTests {
    @Test func tabBarOrderIsCaptureTodayInboxLibraryThenSearch() {
        #expect(Noto2Tab.tabBarOrder == [.capture, .today, .digest, .browse, .search])
        #expect(Noto2Tab.tabBarOrder.filter(\.isSearchRole) == [.search])
    }

    @Test func tabsUseTheRedesignNames() {
        #expect(Noto2Tab.tabBarOrder.map(\.title) == ["Capture", "Today", "Inbox", "Library", "Search"])
    }

    @Test func everyCurrentRawValueStillResolves() {
        for raw in ["capture", "today", "digest", "search", "browse"] {
            #expect(Noto2Tab.resolving(raw)?.rawValue == raw)
        }
    }

    @Test func retiredMediaValueOpensLibrary() {
        #expect(Noto2Tab.resolving("media") == .browse)
    }

    @Test func unknownValueResolvesToNil() {
        #expect(Noto2Tab.resolving("calendar") == nil)
        #expect(Noto2Tab.resolving("") == nil)
    }
}
