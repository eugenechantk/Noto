import Foundation
import NotoDigest
import Testing
@testable import Noto2

/// The Digest tab's queue state machine, driven against a real temp vault.
///
/// The package suites prove what lands on disk; these prove what the *screen*
/// does — which card is in front, when the card pops, and what happens when an
/// action fails.
///
/// | Test | Covers |
/// | --- | --- |
/// | `loadsDueCapturesOldestFirst` | SC1 — front of the queue is the oldest due capture |
/// | `emptyStateOnlyAfterLoad` | SC8 — "inbox clear" never flashes before the first read |
/// | `snoozePopsTheCardAndDropsTheCount` | SC8 — successful action advances the queue |
/// | `snoozedCaptureIsGoneOnReload` | SC2 — the snooze survives a reload |
/// | `discardPopsTheCardAndDeletesTheFile` | SC5, SC8 |
/// | `createPopsTheCardAndWritesTheNote` | SC4, SC8 |
/// | `addToPopsTheCardAndAppends` | SC3, SC8 |
/// | `failedActionKeepsTheCardInFront` | SC6, SC8 — a failure never loses the capture |
/// | `actionsAreNoopsOnAnEmptyQueue` | SC8 — no crash once the inbox is clear |
/// | `filingRequestsSearchIndexUpdates` | SC8 — index hears about both the write and the removal |
@MainActor
struct DigestModelTests {
    // MARK: - Fixtures

    private func makeVault() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DigestModelTests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func writeCapture(
        in vaultURL: URL,
        named name: String,
        body: String,
        created: String = "2026-08-30T09:00:00Z"
    ) -> URL {
        let inbox = vaultURL.appendingPathComponent("inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let document = """
        ---
        id: \(UUID().uuidString)
        created: \(created)
        updated: \(created)
        type: note
        status: inbox
        ---

        \(body)

        """
        let url = inbox.appendingPathComponent(name)
        try? document.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// A model whose search-index hook records requests instead of touching the
    /// app's real FTS index.
    private func makeModel(vaultURL: URL, recorder: IndexRecorder? = nil) -> DigestModel {
        DigestModel(vaultURL: vaultURL, index: { request in await recorder?.record(request) })
    }

    actor IndexRecorder {
        private(set) var requests: [DigestIndexRequest] = []
        func record(_ request: DigestIndexRequest) { requests.append(request) }
        func settled() async -> [DigestIndexRequest] {
            // The model fires index work on a detached utility task; give it a
            // moment rather than asserting on a race.
            for _ in 0..<40 where requests.isEmpty {
                try? await Task.sleep(for: .milliseconds(25))
            }
            return requests
        }
    }

    // MARK: - Loading

    /// The digest works the backlog front-to-back.
    @Test func loadsDueCapturesOldestFirst() async {
        let vault = makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        writeCapture(in: vault, named: "b.md", body: "Newer", created: "2026-08-31T09:00:00Z")
        writeCapture(in: vault, named: "a.md", body: "Older", created: "2026-08-29T09:00:00Z")

        let model = makeModel(vaultURL: vault)
        await model.load()

        #expect(model.remaining == 2)
        #expect(model.current?.body == "Older")
        #expect(model.next?.body == "Newer")
    }

    /// Showing "Inbox clear" before the folder has been read would be a lie on
    /// every cold open of the tab.
    @Test func emptyStateOnlyAfterLoad() async {
        let vault = makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let model = makeModel(vaultURL: vault)
        #expect(!model.isClear)          // not loaded yet
        await model.load()
        #expect(model.isClear)           // loaded, and genuinely empty
    }

    // MARK: - Actions advance the queue

    /// A successful snooze pops the card.
    @Test func snoozePopsTheCardAndDropsTheCount() async {
        let vault = makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        writeCapture(in: vault, named: "a.md", body: "Later", created: "2026-08-29T09:00:00Z")
        writeCapture(in: vault, named: "b.md", body: "Next", created: "2026-08-30T09:00:00Z")

        let model = makeModel(vaultURL: vault)
        await model.load()
        let ok = await model.snoozeCurrent()

        #expect(ok)
        #expect(model.remaining == 1)
        #expect(model.current?.body == "Next")
        #expect(model.outcome?.glyph == "clock")
    }

    /// The snooze is persisted, so re-opening the tab does not resurface it.
    @Test func snoozedCaptureIsGoneOnReload() async {
        let vault = makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        writeCapture(in: vault, named: "a.md", body: "Later")

        let model = makeModel(vaultURL: vault)
        await model.load()
        _ = await model.snoozeCurrent()
        await model.load()

        #expect(model.isClear)
    }

    /// Discard removes the file from the vault.
    @Test func discardPopsTheCardAndDeletesTheFile() async {
        let vault = makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let url = writeCapture(in: vault, named: "a.md", body: "Junk")

        let model = makeModel(vaultURL: vault)
        await model.load()
        let ok = await model.discardCurrent()

        #expect(ok)
        #expect(model.isClear)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    /// Create writes the note and clears the capture.
    @Test func createPopsTheCardAndWritesTheNote() async {
        let vault = makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        writeCapture(in: vault, named: "a.md", body: "Call the dentist")

        let model = makeModel(vaultURL: vault)
        await model.load()
        let ok = await model.createNoteFromCurrent(title: "Dentist", inFolderAt: vault)

        #expect(ok)
        #expect(model.isClear)
        let written = try? String(contentsOf: vault.appendingPathComponent("Dentist.md"), encoding: .utf8)
        #expect(written?.contains("Call the dentist") == true)
        #expect(model.outcome?.text == "Created Dentist")
    }

    /// Add-to merges into the chosen note and clears the capture.
    @Test func addToPopsTheCardAndAppends() async {
        let vault = makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        writeCapture(in: vault, named: "a.md", body: "One more thing")
        let target = vault.appendingPathComponent("Alpha.md")
        try? "---\nid: t\nupdated: 2026-01-01T00:00:00Z\n---\n# Alpha\n\n- existing\n"
            .write(to: target, atomically: true, encoding: .utf8)

        let model = makeModel(vaultURL: vault)
        await model.load()
        let ok = await model.addCurrent(toNoteAt: target, titled: "Alpha")

        #expect(ok)
        #expect(model.isClear)
        let merged = try? String(contentsOf: target, encoding: .utf8)
        #expect(merged?.hasSuffix("- existing\n\nOne more thing\n") == true)
        #expect(model.outcome?.text == "Added to Alpha")
    }

    // MARK: - Failure keeps the capture

    /// The capture must still be on the card after a failed action, or the user
    /// has no way to retry — and the thought is gone from the queue but still on
    /// disk, which is the worst of both.
    @Test func failedActionKeepsTheCardInFront() async {
        let vault = makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        writeCapture(in: vault, named: "a.md", body: "Precious")

        let model = makeModel(vaultURL: vault)
        await model.load()
        let ghost = vault.appendingPathComponent("Gone.md")
        let ok = await model.addCurrent(toNoteAt: ghost, titled: "Gone")

        #expect(!ok)
        #expect(model.remaining == 1)
        #expect(model.current?.body == "Precious")
        #expect(model.errorMessage?.isEmpty == false)
        #expect(model.outcome == nil)
    }

    /// Once the inbox is clear, the buttons are disabled — but a queued gesture
    /// must not crash on an empty queue either.
    @Test func actionsAreNoopsOnAnEmptyQueue() async {
        let vault = makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let model = makeModel(vaultURL: vault)
        await model.load()

        #expect(await model.snoozeCurrent() == false)
        #expect(await model.discardCurrent() == false)
        #expect(await model.createNoteFromCurrent(title: "X", inFolderAt: vault) == false)
        #expect(model.errorMessage == nil)
    }

    // MARK: - Reload

    /// The Digest is the back half of Capture's loop: file a thought in one tab,
    /// switch to the other to process it. A one-shot load left "Inbox clear" on
    /// screen over a folder that had captures in it.
    @Test func refreshPicksUpCapturesWrittenAfterTheFirstLoad() async {
        let vault = makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let model = makeModel(vaultURL: vault)
        await model.load()
        #expect(model.isClear)

        writeCapture(in: vault, named: "late.md", body: "Captured a moment ago")
        await model.refresh()

        #expect(model.remaining == 1)
        #expect(model.current?.body == "Captured a moment ago")
        #expect(!model.isClear)
    }

    /// A reload while a file is in flight would swap the card out from under the
    /// action and pop the wrong entry.
    @Test func refreshIsSkippedWhileAnActionIsInFlight() async {
        let vault = makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        writeCapture(in: vault, named: "a.md", body: "Only one")

        let model = makeModel(vaultURL: vault)
        await model.load()

        // Kick off a file and a refresh together; the refresh must not resurrect
        // the capture the create is about to delete.
        async let filed = model.createNoteFromCurrent(title: "Filed", inFolderAt: vault)
        async let _: Void = model.refresh()
        _ = await filed

        #expect(model.isClear)
        #expect(!vault.appendingPathComponent("inbox/a.md").hasDirectoryPath)
        #expect(!FileManager.default.fileExists(atPath: vault.appendingPathComponent("inbox/a.md").path))
    }

    // MARK: - Undo

    /// Swipe-down deletes with no confirmation dialog, so Undo is the only
    /// recourse for a mis-swipe. It must put the file back exactly.
    @Test func undoRestoresADiscardedCapture() async {
        let vault = makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let url = writeCapture(in: vault, named: "a.md", body: "Nearly lost")
        let before = try? String(contentsOf: url, encoding: .utf8)

        let model = makeModel(vaultURL: vault)
        await model.load()
        _ = await model.discardCurrent()
        #expect(model.isClear)
        #expect(model.outcome?.isUndoable == true)

        let undone = await model.undoDiscard()
        #expect(undone)
        #expect(model.remaining == 1)
        #expect(model.current?.body == "Nearly lost")
        #expect((try? String(contentsOf: url, encoding: .utf8)) == before)
        #expect(model.outcome == nil)
    }

    /// Filing actions are not undoable — the capture's text lives in the
    /// destination note now, so there is nothing to put back.
    @Test func onlyDiscardIsMarkedUndoable() async {
        let vault = makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        writeCapture(in: vault, named: "a.md", body: "Body")

        let model = makeModel(vaultURL: vault)
        await model.load()
        _ = await model.createNoteFromCurrent(title: "Filed", inFolderAt: vault)

        #expect(model.outcome?.isUndoable == false)
        #expect(await model.undoDiscard() == false)
    }

    /// The undo window closes with its banner — an undo you can no longer see is
    /// not an undo, and holding the bytes forever would be a quiet memory leak.
    @Test func clearingTheBannerClosesTheUndoWindow() async {
        let vault = makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        writeCapture(in: vault, named: "a.md", body: "Gone")

        let model = makeModel(vaultURL: vault)
        await model.load()
        _ = await model.discardCurrent()

        let banner = model.outcome!
        model.clearOutcome(banner)

        #expect(model.outcome == nil)
        #expect(model.lastDiscarded == nil)
        #expect(await model.undoDiscard() == false)
    }

    // MARK: - Search index

    /// Noto 2 keeps its own index; a filed capture must become searchable in its
    /// new home and stop matching in its old one.
    @Test func filingRequestsSearchIndexUpdates() async {
        let vault = makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let captureURL = writeCapture(in: vault, named: "a.md", body: "Indexed thought")

        let recorder = IndexRecorder()
        let model = makeModel(vaultURL: vault, recorder: recorder)
        await model.load()
        _ = await model.createNoteFromCurrent(title: "Filed", inFolderAt: vault)

        let requests = await recorder.settled()
        #expect(requests.contains { !$0.isRemoval && $0.fileURL.lastPathComponent == "Filed.md" })
        #expect(requests.contains { $0.isRemoval && $0.fileURL == captureURL.standardizedFileURL })
        #expect(requests.allSatisfy { $0.vaultURL == vault })
    }
}

/// Which notes the "Add to" picker is allowed to offer.
///
/// | Test | Covers |
/// | --- | --- |
/// | `excludesInboxCapturesFromTheNotePicker` | SC3 — you can't file a capture into another capture, or into itself |
/// | `keepsNonInboxNotesAndCapsTheList` | SC3 — real notes survive the filter, and the list stays bounded |
@MainActor
struct DigestNotePickerTests {
    private func document(_ relativePath: String) -> PageMentionDocument {
        PageMentionDocument(
            id: UUID(),
            title: (relativePath as NSString).lastPathComponent,
            relativePath: relativePath,
            fileURL: URL(fileURLWithPath: "/vault/" + relativePath)
        )
    }

    /// The capture on the card lives in `inbox/`. If the picker offered it, you
    /// could append a note to itself — and offering *other* captures just files
    /// one unprocessed thought into another.
    @Test func excludesInboxCapturesFromTheNotePicker() {
        let candidates = DigestNotePicker.filingCandidates([
            document("inbox/2026-08-28-22222222.md"),
            document("Projects/Alpha.md"),
            document("INBOX/2026-08-29-33333333.md"),   // case-insensitive
            document("Meeting Notes.md"),
        ])

        #expect(candidates.map(\.relativePath) == ["Projects/Alpha.md", "Meeting Notes.md"])
    }

    /// A folder merely *named* something inbox-adjacent is not the inbox, and the
    /// list is capped so a large vault doesn't render thousands of rows.
    @Test func keepsNonInboxNotesAndCapsTheList() {
        let many = (0..<60).map { document("Notes/n\($0).md") }
        #expect(DigestNotePicker.filingCandidates(many).count == DigestNotePicker.visibleLimit)
        #expect(DigestNotePicker.filingCandidates([document("inboxes/Ideas.md")]).count == 1)
    }
}

/// The title the Create sheet pre-fills from a capture.
///
/// | Test | Covers |
/// | --- | --- |
/// | `dropsSentencePunctuationThatWouldLandInTheFilename` | no more `one-pager..md` |
/// | `stripsMarkdownHeadingAndListMarkers` | a captured heading or bullet isn't a title |
/// | `keepsQuestionMarksAndCapsLength` | `?`/`!` are title-worthy; long captures are truncated |
@MainActor
struct DigestSuggestedTitleTests {
    private func capture(_ body: String) -> DigestEntry {
        DigestEntry(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/vault/inbox/x.md"),
            relativePath: "inbox/x.md",
            body: body,
            capturedAt: Date()
        )
    }

    /// A capture is usually a sentence; keeping its full stop produced filenames
    /// like `draft the Q4 roadmap one-pager..md`.
    @Test func dropsSentencePunctuationThatWouldLandInTheFilename() {
        #expect(DigestFolderOption.suggestedTitle(from: capture("Draft the Q4 roadmap one-pager.")) == "Draft the Q4 roadmap one-pager")
        #expect(DigestFolderOption.suggestedTitle(from: capture("Email Sam,")) == "Email Sam")
        #expect(DigestFolderOption.suggestedTitle(from: capture("Q3 plan —")) == "Q3 plan")
    }

    /// Captures often start as a heading or a to-do bullet; the marker is syntax,
    /// not part of the title.
    @Test func stripsMarkdownHeadingAndListMarkers() {
        #expect(DigestFolderOption.suggestedTitle(from: capture("## Dentist appointment")) == "Dentist appointment")
        #expect(DigestFolderOption.suggestedTitle(from: capture("- [ ] Call the dentist")) == "Call the dentist")
        #expect(DigestFolderOption.suggestedTitle(from: capture("1. First thing")) == "First thing")
    }

    /// `?` and `!` carry meaning in a title, unlike a trailing full stop. Long
    /// captures truncate so the filename stays readable.
    @Test func keepsQuestionMarksAndCapsLength() {
        #expect(DigestFolderOption.suggestedTitle(from: capture("Ship the digest?")) == "Ship the digest?")
        let long = String(repeating: "word ", count: 40)
        #expect(DigestFolderOption.suggestedTitle(from: capture(long)).count <= 60)
    }
}
