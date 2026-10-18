import Foundation
import Testing
@testable import NotoVault

struct DailyNoteBrowsingTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        return value
    }

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
    }

    private func vault() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DailyBrowsing-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func lookingAtAnEmptyDayCreatesNothing() throws {
        let root = try vault()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = DailyNoteService(vaultRootURL: root)
        #expect(try service.open(date: date(15), createIfMissing: false, calendar: calendar) == nil)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Daily Notes").path))
    }

    @Test func explicitCreationUsesTheExistingFormatAndIdentity() throws {
        let root = try vault()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = DailyNoteService(vaultRootURL: root)
        let first = try #require(try service.open(date: date(17), createIfMissing: true, calendar: calendar))
        let second = try #require(try service.open(date: date(17), createIfMissing: true, calendar: calendar))
        let content = try String(contentsOf: first.fileURL, encoding: .utf8)
        #expect(first.fileURL.path.hasSuffix("Daily Notes/2026-10-17.md"))
        #expect(first.displayTitle == "17 Oct, 26 (Sat)")
        #expect(content.contains("# 17 Oct, 26 (Sat)\n" + DailyNoteTemplate.notoDefault.body))
        #expect(first.id == second.id)
        #expect(first.didCreate)
        #expect(!second.didCreate)
        #expect(!second.didApplyTemplate)
    }

    @Test func openingAnExistingDailyNoteNeverRewritesIt() throws {
        let root = try vault()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = DailyNoteService(vaultRootURL: root)
        let note = try #require(try service.open(date: date(16), createIfMissing: true, calendar: calendar))
        let customContent = "# A different title\n\nA full day, without reflection headings.\n"
        try customContent.write(to: note.fileURL, atomically: true, encoding: .utf8)
        _ = try service.open(date: date(16), createIfMissing: true, calendar: calendar)
        #expect(try String(contentsOf: note.fileURL, encoding: .utf8) == customContent)
    }

    @Test func dotsIgnoreTemplateAndWhitespaceButKeepRealWriting() throws {
        let root = try vault()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = DailyNoteService(vaultRootURL: root)
        let empty = try #require(try service.open(date: date(17), createIfMissing: true, calendar: calendar))
        let written = try #require(try service.open(date: date(16), createIfMissing: true, calendar: calendar))
        let emptyContent = try String(contentsOf: empty.fileURL, encoding: .utf8)
        #expect(!service.hasWriting(in: emptyContent, date: date(17), calendar: calendar))
        #expect(!service.hasWriting(in: emptyContent + "\n  \n", date: date(17), calendar: calendar))
        let writing = try String(contentsOf: written.fileURL, encoding: .utf8) + "\n- Walked by the harbour.\n"
        try writing.write(to: written.fileURL, atomically: true, encoding: .utf8)
        #expect(service.hasWriting(in: writing, date: date(16), calendar: calendar))
        #expect(service.writtenDays(inMonthContaining: date(17), calendar: calendar) == [calendar.startOfDay(for: date(16))])
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Daily Notes/2026-10-15.md").path))
    }

    @Test func captionAndNavigationUseCalendarDays() {
        #expect(DailyNoteDay.caption(for: date(17), now: date(17), calendar: calendar) == "Today")
        #expect(DailyNoteDay.caption(for: date(16), now: date(17), calendar: calendar) == "Yesterday · Friday")
        #expect(DailyNoteDay.caption(for: date(15), now: date(17), calendar: calendar) == "Thursday")
        var dstCalendar = Calendar(identifier: .gregorian)
        dstCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = dstCalendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let next = DailyNoteDay.offset(start, by: 1, calendar: dstCalendar)
        #expect(dstCalendar.component(.day, from: next) == 9)
        #expect(next.timeIntervalSince(start) == 23 * 60 * 60)
    }

    @Test func failedCreationDoesNotReturnAPhantomNote() throws {
        let root = try vault()
        defer { try? FileManager.default.removeItem(at: root) }
        let obstruction = root.appendingPathComponent("Daily Notes")
        try "not a directory".write(to: obstruction, atomically: true, encoding: .utf8)
        #expect(throws: DailyNoteBrowsingError.self) {
            _ = try DailyNoteService(vaultRootURL: root).open(date: date(17), createIfMissing: true, calendar: calendar)
        }
    }
}
