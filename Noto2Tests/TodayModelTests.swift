import Foundation
import NotoVault
import Testing
@testable import Noto2

@MainActor
struct TodayModelTests {
    private func fixture() throws -> (TodayModel, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TodayModel-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 12))!
        return (TodayModel(vaultController: VaultController(vaultURL: root, autoloadRoot: false), calendar: calendar, now: { today }), root)
    }

    @Test func openingCreatesTodayAndPreviousDayStaysEmpty() async throws {
        let (model, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.openIfNeeded()
        #expect(model.session?.hasLoaded == true)
        #expect(model.session?.note.fileURL.lastPathComponent == "2026-10-17.md")
        #expect(!model.canGoNext)
        await model.previousDay()
        #expect(model.session == nil)
        #expect(model.caption == "Yesterday · Friday")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Daily Notes/2026-10-16.md").path))
        await model.openIfNeeded() // A return from another tab preserves this day.
        #expect(model.session == nil)
        #expect(model.calendar.component(.day, from: model.selectedDate) == 16)
        await model.startSelectedDay()
        #expect(model.session?.note.fileURL.lastPathComponent == "2026-10-16.md")
        #expect(model.session?.isNew == true)
    }

    @Test func reselectReturnsToTodayAndChangesScrollRequest() async throws {
        let (model, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.openIfNeeded()
        await model.previousDay()
        let scrollID = model.scrollRestorationID
        await model.reselectTab()
        #expect(model.selectedDate == model.today)
        #expect(model.session?.note.fileURL.lastPathComponent == "2026-10-17.md")
        #expect(model.scrollRestorationID != scrollID)
        let todayScrollID = model.scrollRestorationID
        await model.reselectTab()
        #expect(model.scrollRestorationID != todayScrollID)
    }

    @Test func returningToEmptyPastDayLoadsNoteCreatedExternally() async throws {
        let (model, root) = try fixture()
        defer {
            model.session?.cancelBackgroundWork()
            try? FileManager.default.removeItem(at: root)
        }
        await model.openIfNeeded()
        await model.previousDay()
        let selectedDate = model.selectedDate
        let scrollRevision = model.scrollRevision
        let url = root.appendingPathComponent("Daily Notes/2026-10-16.md")

        await model.openIfNeeded()
        #expect(model.session == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))

        let id = UUID()
        let externalMarkdown = VaultMarkdown.makeFrontmatter(id: id, createdAt: selectedDate)
            + "# Written on another device\n\nAn externally created reflection.\n"
        try externalMarkdown.write(to: url, atomically: true, encoding: .utf8)

        await model.openIfNeeded()

        #expect(model.selectedDate == selectedDate)
        #expect(model.scrollRevision == scrollRevision)
        #expect(try String(contentsOf: url, encoding: .utf8) == externalMarkdown)
        let session = try #require(model.session)
        #expect(session.hasLoaded)
        #expect(session.note.id == id)
        #expect(session.note.fileURL == url)
        #expect(session.content == externalMarkdown)
        #expect(!session.isNew)
    }

    @Test func refreshDoesNotOpenDailyNotesBeforeFirstAppearance() async throws {
        let (model, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let selectedDate = model.selectedDate

        await model.refreshSelectedDay(changedURL: root.appendingPathComponent("Unrelated.md"))
        await model.refreshSelectedDay()

        #expect(!model.hasOpened)
        #expect(model.session == nil)
        #expect(model.selectedDate == selectedDate)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Daily Notes").path))
    }

    @Test func externalRefreshKeepsPastDayMissingUntilItsFileArrives() async throws {
        let (model, root) = try fixture()
        defer {
            model.session?.cancelBackgroundWork()
            try? FileManager.default.removeItem(at: root)
        }
        await model.openIfNeeded()
        await model.previousDay()
        let selectedDate = model.selectedDate
        let scrollRevision = model.scrollRevision
        let url = root.appendingPathComponent("Daily Notes/2026-10-16.md")

        await model.refreshSelectedDay(changedURL: url)
        await model.refreshSelectedDay()
        #expect(model.session == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))

        let externalMarkdown = VaultMarkdown.makeFrontmatter(id: UUID(), createdAt: selectedDate)
            + "# An existing daily note\n\nThis writing arrived from another device.\n"
        try externalMarkdown.write(to: url, atomically: true, encoding: .utf8)
        await model.refreshSelectedDay(changedURL: url)
        let session = try #require(model.session)
        #expect(session.hasLoaded)
        #expect(session.content == externalMarkdown)
        #expect(!session.isNew)
        #expect(model.selectedDate == selectedDate)
        #expect(model.scrollRevision == scrollRevision)
        #expect(try String(contentsOf: url, encoding: .utf8) == externalMarkdown)
    }

    @Test func refreshingAndReturningToLoadedDayPreservesSessionAndPendingDraft() async throws {
        let (model, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.openIfNeeded()
        let session = try #require(model.session)
        defer { session.cancelBackgroundWork() }
        let originalMarkdown = try String(contentsOf: session.note.fileURL, encoding: .utf8)
        let draft = session.content + "\nMy unsaved reflection.\n"
        session.content = draft
        session.handleEditorChange(draft)
        let selectedDate = model.selectedDate
        let scrollRevision = model.scrollRevision

        await model.refreshSelectedDay(changedURL: session.note.fileURL)
        await model.refreshSelectedDay()
        await model.openIfNeeded()

        #expect(model.session === session)
        #expect(model.selectedDate == selectedDate)
        #expect(model.scrollRevision == scrollRevision)
        #expect(session.content == draft)
        #expect(session.latestEditorText == draft)
        #expect(session.hasPendingLocalEdits)
        #expect(try String(contentsOf: session.note.fileURL, encoding: .utf8) == originalMarkdown)
    }

    @Test func switchingDayPersistsPendingWritingAndCalendarShowsItsDot() async throws {
        let (model, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.openIfNeeded()
        let session = try #require(model.session)
        let url = session.note.fileURL
        session.handleEditorChange(session.content + "\nA real reflection.\n")
        await model.previousDay()
        #expect(try String(contentsOf: url, encoding: .utf8).contains("A real reflection."))
        await model.refreshWrittenDays(inMonthContaining: model.today)
        #expect(model.writtenDays == [model.today])
    }

    @Test func returningAfterACancelledAppearanceStillOpensTheDay() async throws {
        let (model, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let opening = Task { await model.openIfNeeded() }
        opening.cancel()
        await opening.value
        await model.openIfNeeded()
        #expect(!model.isLoading)
        #expect(model.session?.hasLoaded == true)
    }

    @Test func futureNavigationIsRejected() async throws {
        let (model, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.openIfNeeded()
        await model.nextDay()
        await model.select(DailyNoteDay.offset(model.today, by: 1, calendar: model.calendar))
        #expect(model.selectedDate == model.today)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Daily Notes/2026-10-18.md").path))
    }
}
