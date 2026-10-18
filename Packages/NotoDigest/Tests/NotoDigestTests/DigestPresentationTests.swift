import Foundation
import Testing
@testable import NotoDigest

struct DigestPresentationTests {
    @Test func groupsSnoozedFirstAndSortsDueBeforeFuture() {
        let vault = TempVault()
        vault.writeCapture(named: "today.md", body: "Today", created: "2026-09-01T09:00:00Z")
        vault.writeCapture(named: "future.md", body: "Future", snoozedUntil: "2026-09-08T12:00:00Z")
        vault.writeCapture(named: "due.md", body: "Due", snoozedUntil: "2026-09-01T08:00:00Z")
        vault.writeCapture(named: "yesterday.md", body: "Yesterday", created: "2026-08-31T10:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let sections = DigestPresentation.sections(DigestInbox(vaultURL: vault.rootURL).allEntries(), now: TestDates.now, calendar: calendar)
        #expect(sections.map(\.kind) == [.snoozed, .today, .yesterday])
        #expect(sections[0].entries.map(\.summary) == ["Due", "Future"])
        #expect(DigestPresentation.ordered(sections.flatMap(\.entries), now: TestDates.now).filter { $0.isDue(at: TestDates.now) }.map(\.summary) == ["Due", "Today", "Yesterday"])
    }

    @Test func tallyCountsOnlyTodayAndUndoRemovesTheAction() {
        var tally = DigestDailyTally()
        let yesterday = TestDates.now.addingTimeInterval(-86_400)
        tally.record(.filed, at: yesterday)
        let event = tally.record(.snoozed, at: TestDates.now)
        tally.record(.discarded, at: TestDates.now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        #expect(tally.counts(at: TestDates.now, calendar: calendar) == .init(filed: 0, discarded: 1, snoozed: 1))
        tally.undo(event)
        #expect(tally.counts(at: TestDates.now, calendar: calendar).total == 1)
        #expect(tally.counts(at: TestDates.now.addingTimeInterval(86_400), calendar: calendar).total == 0)
    }

    @Test func snoozeUndoKeepsAnExternalBodyEdit() throws {
        let vault = TempVault()
        let url = vault.writeCapture(named: "a.md", body: "Original")
        let entry = try #require(DigestInbox(vaultURL: vault.rootURL).entry(at: url))
        let filing = DigestFiling(vaultURL: vault.rootURL, now: { TestDates.now })
        let receipt = try filing.snoozeWithUndo(entry)
        let document = try #require(vault.read("inbox/a.md"))
        vault.write(document.replacingOccurrences(of: "Original", with: "Edited elsewhere"), at: "inbox/a.md")
        try filing.undoSnooze(receipt)
        let restored = try #require(DigestInbox(vaultURL: vault.rootURL).entry(at: url))
        #expect(restored.snoozedUntil == nil)
        #expect(restored.body == "Edited elsewhere")
    }

    @Test func createUsesEditedTextWithoutHeadingAndKeepsCaptureOnFailure() throws {
        let vault = TempVault()
        let url = vault.writeCapture(named: "a.md", body: "Original")
        let entry = try #require(DigestInbox(vaultURL: vault.rootURL).entry(at: url))
        let filing = DigestFiling(vaultURL: vault.rootURL)
        let output = try filing.createNoteAsWritten(from: entry, inFolderAt: vault.rootURL, body: "Edited first line\n\n- detail")
        #expect(output.lastPathComponent == "Edited first line.md")
        #expect(vault.read("Edited first line.md")?.hasSuffix("Edited first line\n\n- detail\n") == true)
        #expect(!vault.exists("inbox/a.md"))
    }
}

struct DigestUndoTests {
    @Test func appendUndoRestoresBothOriginalFiles() throws {
        let vault = TempVault()
        let capture = vault.writeCapture(named: "a.md", body: "Capture")
        let target = vault.write("---\nid: destination\n---\nExisting\n", at: "Note.md")
        let entry = try #require(DigestInbox(vaultURL: vault.rootURL).entry(at: capture))
        let before = vault.read("Note.md")
        let captureBefore = vault.read("inbox/a.md")
        let filing = DigestFiling(vaultURL: vault.rootURL)
        let receipt = try filing.appendWithUndo(entry, toNoteAt: target)
        #expect(!vault.exists("inbox/a.md"))
        try filing.undo(receipt)
        #expect(vault.read("Note.md") == before)
        #expect(vault.read("inbox/a.md") == captureBefore)
    }

    @Test func appendUndoRefusesLaterEdits() throws {
        let vault = TempVault()
        let capture = vault.writeCapture(named: "a.md", body: "Capture")
        let target = vault.write("Existing\n", at: "Note.md")
        let entry = try #require(DigestInbox(vaultURL: vault.rootURL).entry(at: capture))
        let filing = DigestFiling(vaultURL: vault.rootURL)
        let receipt = try filing.appendWithUndo(entry, toNoteAt: target)
        vault.write("Later edit", at: "Note.md")
        #expect(throws: DigestFiling.FilingError.changedSinceFiling("Note.md")) { try filing.undo(receipt) }
        #expect(vault.read("Note.md") == "Later edit")
        #expect(!vault.exists("inbox/a.md"))
    }

    @Test func createUndoRemovesOnlyUnchangedCreatedNote() throws {
        let vault = TempVault()
        let capture = vault.writeCapture(named: "a.md", body: "Capture")
        let entry = try #require(DigestInbox(vaultURL: vault.rootURL).entry(at: capture))
        let filing = DigestFiling(vaultURL: vault.rootURL)
        let receipt = try filing.createWithUndo(entry, inFolderAt: vault.rootURL)
        try filing.undo(receipt)
        #expect(vault.exists("inbox/a.md"))
        #expect(!vault.exists("Capture.md"))
    }

    @Test func undoDoesNotOverwriteACaptureThatReappeared() throws {
        let vault = TempVault()
        let capture = vault.writeCapture(named: "a.md", body: "Capture")
        let target = vault.write("Existing\n", at: "Note.md")
        let entry = try #require(DigestInbox(vaultURL: vault.rootURL).entry(at: capture))
        let filing = DigestFiling(vaultURL: vault.rootURL)
        let receipt = try filing.appendWithUndo(entry, toNoteAt: target)
        vault.write("New capture at same path", at: "inbox/a.md")
        #expect(throws: DigestFiling.FilingError.changedSinceFiling("inbox/a.md")) { try filing.undo(receipt) }
        #expect(vault.read("inbox/a.md") == "New capture at same path")
        #expect(vault.read("Note.md")?.contains("Capture") == true)
    }

    @Test func folderCreationRejectsTraversalAndCollisions() throws {
        let vault = TempVault()
        #expect(throws: DigestFolderCreation.CreationError.invalidName) {
            try DigestFolderCreation.create(named: "../outside", in: vault.rootURL, vaultURL: vault.rootURL)
        }
        let created = try DigestFolderCreation.create(named: "Ideas", in: vault.rootURL, vaultURL: vault.rootURL)
        #expect(FileManager.default.fileExists(atPath: created.path))
        #expect(throws: DigestFolderCreation.CreationError.exists) {
            try DigestFolderCreation.create(named: "Ideas", in: vault.rootURL, vaultURL: vault.rootURL)
        }
    }
}
