import Testing
import Foundation
@testable import NotoVault

@Suite("NotoRelativeDate.editedString")
struct RelativeDateTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("under a minute → just now")
    func justNow() {
        #expect(NotoRelativeDate.editedString(from: now.addingTimeInterval(-30), now: now) == "Edited just now")
    }

    @Test("minutes")
    func minutes() {
        #expect(NotoRelativeDate.editedString(from: now.addingTimeInterval(-5 * 60), now: now) == "Edited 5m ago")
    }

    @Test("hours")
    func hours() {
        #expect(NotoRelativeDate.editedString(from: now.addingTimeInterval(-3 * 3600), now: now) == "Edited 3h ago")
    }

    @Test("days")
    func days() {
        #expect(NotoRelativeDate.editedString(from: now.addingTimeInterval(-2 * 86400), now: now) == "Edited 2d ago")
    }

    @Test("weeks")
    func weeks() {
        #expect(NotoRelativeDate.editedString(from: now.addingTimeInterval(-3 * 7 * 86400), now: now) == "Edited 3w ago")
    }

    @Test("months")
    func months() {
        #expect(NotoRelativeDate.editedString(from: now.addingTimeInterval(-60 * 86400), now: now) == "Edited 2mo ago")
    }

    @Test("future/equal clamps to just now")
    func future() {
        #expect(NotoRelativeDate.editedString(from: now.addingTimeInterval(120), now: now) == "Edited just now")
    }

    @Test("compactString drops the Edited prefix")
    func compact() {
        #expect(NotoRelativeDate.compactString(from: now.addingTimeInterval(-2 * 3600), now: now) == "2h ago")
        #expect(NotoRelativeDate.compactString(from: now.addingTimeInterval(-30), now: now) == "just now")
        #expect(NotoRelativeDate.compactString(from: now.addingTimeInterval(-3 * 86400), now: now) == "3d ago")
    }
}
