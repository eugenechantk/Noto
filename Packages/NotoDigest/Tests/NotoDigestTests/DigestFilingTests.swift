import Foundation
import Testing
@testable import NotoDigest
import NotoVault

/// The four digest actions, against real files in a temp vault.
///
/// | Test | Covers |
/// | --- | --- |
/// | `snoozeWritesStampAndHidesFromDigest` | SC2 — a week out, and gone from `dueEntries` |
/// | `snoozePreservesEveryOtherKeyAndTheBody` | SC2 — only `snoozed_until` changes |
/// | `resnoozeOverwritesRatherThanDuplicates` | SC2 — one key, not a stack |
/// | `snoozeFailsOnAFrontmatterlessCapture` | SC2 — a no-op write is reported, not swallowed |
/// | `appendMergesIntoTargetAndClearsInbox` | SC3 — capture lands in the note, inbox file gone |
/// | `appendRefreshesTheTargetUpdatedStamp` | SC3 — the target's `updated:` moves |
/// | `appendRereadsTheCaptureFromDisk` | SC3 — a stale in-memory entry doesn't file stale text |
/// | `appendRejectsAMissingTarget` | SC3 — deleted destination fails cleanly |
/// | `createWritesTitledNoteAndClearsInbox` | SC4 — `<folder>/<Title>.md` with heading + body |
/// | `createResolvesFilenameCollisions` | SC4 — second note becomes `Title(2).md` |
/// | `createIntoAMissingFolderMakesIt` | SC4 — destination folder is created on demand |
/// | `createRejectsABlankTitle` | SC4 — `invalidTitle`, nothing written, nothing deleted |
/// | `discardDeletesOnlyTheCapture` | SC5 — no other file is touched |
/// | `failedAppendLeavesTheCaptureInTheInbox` | SC6 — ordering guarantee on add-to |
/// | `failedCreateLeavesTheCaptureInTheInbox` | SC6 — ordering guarantee on create |
/// | `filingAnUnavailableCaptureFails` | SC6 — a dataless stub can't be filed into a note |
@Suite("DigestFiling — snooze, add-to, create, discard")
struct DigestFilingTests {
    private func filing(_ vault: TempVault, fileSystem: (any VaultFileSystem)? = nil) -> DigestFiling {
        DigestFiling(
            vaultURL: vault.rootURL,
            fileSystem: fileSystem ?? CoordinatedVaultFileSystem(),
            now: { TestDates.now },
            makeID: { UUID(uuidString: "a1b2c3d4-e5f6-7890-abcd-000000000099")! }
        )
    }

    private func firstEntry(_ vault: TempVault) -> DigestEntry {
        DigestInbox(vaultURL: vault.rootURL).allEntries().first!
    }

    // MARK: - Snooze (SC2)

    /// A week out from the injected clock, and out of the queue.
    @Test("snooze stamps a week out and removes the capture from the digest")
    func snoozeWritesStampAndHidesFromDigest() throws {
        let vault = TempVault()
        vault.writeCapture(named: "one.md", body: "Later")

        let wake = try filing(vault).snooze(firstEntry(vault))
        #expect(wake == TestDates.now.addingTimeInterval(7 * 24 * 60 * 60))

        let content = vault.read("inbox/one.md") ?? ""
        #expect(NoteFrontmatter.value(for: "snoozed_until", in: content) == "2026-09-08T12:00:00Z")
        #expect(DigestInbox(vaultURL: vault.rootURL).dueEntries(now: TestDates.now).isEmpty)
    }

    /// A snooze is a triage decision, not an edit — the thought and every other
    /// frontmatter key must come back untouched.
    @Test("snooze preserves every other frontmatter key and the body")
    func snoozePreservesEveryOtherKeyAndTheBody() throws {
        let vault = TempVault()
        let id = UUID()
        vault.writeCapture(named: "one.md", body: "Buy oat milk", id: id)
        let before = vault.read("inbox/one.md")!

        try filing(vault).snooze(firstEntry(vault))
        let after = vault.read("inbox/one.md")!

        #expect(NoteFrontmatter.value(for: "id", in: after) == id.uuidString)
        #expect(NoteFrontmatter.value(for: "created", in: after) == "2026-08-30T09:00:00Z")
        #expect(NoteFrontmatter.value(for: "status", in: after) == "inbox")   // gbrain still types it as a note
        #expect(NoteFrontmatter.value(for: "updated", in: after) == NoteFrontmatter.value(for: "updated", in: before))
        #expect(VaultMarkdown.stripFrontmatter(after).trimmingCharacters(in: .whitespacesAndNewlines) == "Buy oat milk")
    }

    /// Snoozing an already-snoozed capture pushes the date out; it does not stack
    /// a second key that the parser would then read ambiguously.
    @Test("re-snoozing overwrites the existing stamp instead of duplicating it")
    func resnoozeOverwritesRatherThanDuplicates() throws {
        let vault = TempVault()
        vault.writeCapture(named: "one.md", body: "Later", snoozedUntil: "2026-08-25T12:00:00Z")

        try filing(vault).snooze(firstEntry(vault))
        let content = vault.read("inbox/one.md")!
        #expect(content.components(separatedBy: "snoozed_until:").count - 1 == 1)
        #expect(NoteFrontmatter.value(for: "snoozed_until", in: content) == "2026-09-08T12:00:00Z")
    }

    /// With no frontmatter there is nowhere to record the snooze. Reporting
    /// success would leave the card reappearing forever with no explanation.
    @Test("snoozing a frontmatter-less capture reports failure rather than silently doing nothing")
    func snoozeFailsOnAFrontmatterlessCapture() {
        let vault = TempVault()
        vault.write("Raw thought\n", at: "inbox/raw.md")

        #expect(throws: DigestFiling.FilingError.writeFailed("inbox/raw.md")) {
            try filing(vault).snooze(firstEntry(vault))
        }
    }

    // MARK: - Add to an existing note (SC3)

    /// The canonical add-to: text lands at the end of the target, capture leaves
    /// the inbox.
    @Test("add-to appends to the target note and clears the capture from the inbox")
    func appendMergesIntoTargetAndClearsInbox() throws {
        let vault = TempVault()
        vault.writeCapture(named: "one.md", body: "Email Sam about Q3")
        let target = vault.write(
            "---\nid: t\ncreated: 2026-01-01T00:00:00Z\nupdated: 2026-01-01T00:00:00Z\n---\n# Project Alpha\n\n- existing\n",
            at: "Projects/Alpha.md"
        )

        let written = try filing(vault).append(firstEntry(vault), toNoteAt: target)
        #expect(written == target.standardizedFileURL)

        let merged = vault.read("Projects/Alpha.md")!
        #expect(merged.hasSuffix("- existing\n\nEmail Sam about Q3\n"))
        #expect(merged.contains("# Project Alpha"))
        #expect(!vault.exists("inbox/one.md"))
    }

    /// Filing into a note is a write to that note, so its timestamp moves.
    @Test("add-to refreshes the target note's updated stamp")
    func appendRefreshesTheTargetUpdatedStamp() throws {
        let vault = TempVault()
        vault.writeCapture(named: "one.md", body: "New line")
        let target = vault.write(
            "---\nid: t\ncreated: 2026-01-01T00:00:00Z\nupdated: 2026-01-01T00:00:00Z\n---\n# A\n",
            at: "A.md"
        )

        try filing(vault).append(firstEntry(vault), toNoteAt: target)
        #expect(NoteFrontmatter.value(for: "updated", in: vault.read("A.md")!) == "2026-09-01T12:00:00Z")
    }

    /// Notes written by the main Noto app track `modified:`, not `updated:`. Filing
    /// into one used to leave it advertising a months-old write time, because the
    /// stamping helper only knew the other key.
    @Test("add-to refreshes a modified: stamp on notes written by the main app")
    func appendRefreshesAModifiedStamp() throws {
        let vault = TempVault()
        vault.writeCapture(named: "one.md", body: "New line")
        let target = vault.write(
            "---\nid: t\ncreated: 2026-03-15T09:00:00Z\nmodified: 2026-03-15T09:00:00Z\n---\n# Meeting Notes\n",
            at: "Meeting Notes.md"
        )

        try filing(vault).append(firstEntry(vault), toNoteAt: target)
        let merged = vault.read("Meeting Notes.md")!
        #expect(NoteFrontmatter.value(for: "modified", in: merged) == "2026-09-01T12:00:00Z")
        #expect(NoteFrontmatter.value(for: "created", in: merged) == "2026-03-15T09:00:00Z")
        #expect(merged.hasSuffix("# Meeting Notes\n\nNew line\n"))
    }

    /// The digest can sit on screen while iCloud syncs an edit from another
    /// device; filing must use what is on disk now, not what was loaded earlier.
    @Test("add-to re-reads the capture from disk instead of trusting a stale entry")
    func appendRereadsTheCaptureFromDisk() throws {
        let vault = TempVault()
        vault.writeCapture(named: "one.md", body: "Old text")
        let stale = firstEntry(vault)
        vault.writeCapture(named: "one.md", body: "Edited on another device")

        let target = vault.write("---\nid: t\nupdated: 2026-01-01T00:00:00Z\n---\n# A\n", at: "A.md")
        try filing(vault).append(stale, toNoteAt: target)

        #expect(vault.read("A.md")!.contains("Edited on another device"))
        #expect(!vault.read("A.md")!.contains("Old text"))
    }

    /// Picked a note, then deleted it elsewhere before confirming.
    @Test("add-to rejects a target that no longer exists")
    func appendRejectsAMissingTarget() {
        let vault = TempVault()
        vault.writeCapture(named: "one.md", body: "Anything")
        let ghost = vault.rootURL.appendingPathComponent("Gone.md")

        #expect(throws: DigestFiling.FilingError.targetMissing("Gone.md")) {
            try filing(vault).append(firstEntry(vault), toNoteAt: ghost)
        }
        #expect(vault.exists("inbox/one.md"))
    }

    // MARK: - Create a new note (SC4)

    /// Title becomes both the filename and the H1; the capture becomes the body.
    @Test("create writes a titled note in the chosen folder and clears the inbox")
    func createWritesTitledNoteAndClearsInbox() throws {
        let vault = TempVault()
        vault.writeCapture(named: "one.md", body: "Call the dentist on Monday")

        let folder = vault.rootURL.appendingPathComponent("Tasks", isDirectory: true)
        let written = try filing(vault).createNote(from: firstEntry(vault), title: "Dentist", inFolderAt: folder)

        #expect(written.lastPathComponent == "Dentist.md")
        let note = vault.read("Tasks/Dentist.md")!
        #expect(note.contains("id: A1B2C3D4-E5F6-7890-ABCD-000000000099"))
        #expect(note.hasSuffix("# Dentist\n\nCall the dentist on Monday\n"))
        #expect(!vault.exists("inbox/one.md"))
    }

    /// Two captures filed under the same title must not overwrite each other.
    @Test("create resolves a filename collision instead of overwriting")
    func createResolvesFilenameCollisions() throws {
        let vault = TempVault()
        vault.writeCapture(named: "one.md", body: "First")
        vault.write("---\nid: t\n---\n# Dentist\n\nAlready here\n", at: "Dentist.md")

        let written = try filing(vault).createNote(from: firstEntry(vault), title: "Dentist", inFolderAt: vault.rootURL)
        #expect(written.lastPathComponent == "Dentist(2).md")
        #expect(vault.read("Dentist.md")!.contains("Already here"))   // untouched
        #expect(vault.read("Dentist(2).md")!.contains("First"))
    }

    /// Filing into a folder that doesn't exist yet creates it.
    @Test("create makes the destination folder when it is missing")
    func createIntoAMissingFolderMakesIt() throws {
        let vault = TempVault()
        vault.writeCapture(named: "one.md", body: "Body")

        let folder = vault.rootURL.appendingPathComponent("Brand New", isDirectory: true)
        _ = try filing(vault).createNote(from: firstEntry(vault), title: "Note", inFolderAt: folder)
        #expect(vault.exists("Brand New/Note.md"))
    }

    /// A blank title has no filename; nothing is written and the capture stays put.
    @Test("create rejects a blank title without writing or deleting anything")
    func createRejectsABlankTitle() {
        let vault = TempVault()
        vault.writeCapture(named: "one.md", body: "Body")

        #expect(throws: DigestFiling.FilingError.invalidTitle) {
            try filing(vault).createNote(from: firstEntry(vault), title: "   ", inFolderAt: vault.rootURL)
        }
        #expect(vault.exists("inbox/one.md"))
    }

    // MARK: - Discard (SC5)

    /// Discard is a delete and nothing more.
    @Test("discard deletes the capture and touches nothing else")
    func discardDeletesOnlyTheCapture() throws {
        let vault = TempVault()
        vault.writeCapture(named: "one.md", body: "Junk")
        vault.writeCapture(named: "two.md", body: "Keep", created: "2026-08-31T09:00:00Z")
        vault.write("---\nid: t\n---\n# A\n", at: "A.md")

        let inbox = DigestInbox(vaultURL: vault.rootURL)
        try filing(vault).discard(inbox.allEntries().first { $0.body == "Junk" }!)

        #expect(!vault.exists("inbox/one.md"))
        #expect(vault.exists("inbox/two.md"))
        #expect(vault.read("A.md") == "---\nid: t\n---\n# A\n")
    }

    /// Swipe-down deletes with no confirmation dialog, so the returned document is
    /// the only thing standing between a stray gesture and a lost thought.
    @Test("discard returns the file's exact original bytes")
    func discardReturnsTheOriginalDocument() throws {
        let vault = TempVault()
        vault.writeCapture(named: "one.md", body: "Nearly lost")
        let before = vault.read("inbox/one.md")!

        let discarded = try filing(vault).discard(firstEntry(vault))
        #expect(discarded.document == before)
        #expect(!vault.exists("inbox/one.md"))
    }

    /// Undo puts the capture back byte-for-byte, frontmatter and all.
    @Test("restore writes a discarded capture back unchanged")
    func restorePutsTheCaptureBack() throws {
        let vault = TempVault()
        vault.writeCapture(named: "one.md", body: "Nearly lost")
        let before = vault.read("inbox/one.md")!

        let filer = filing(vault)
        let discarded = try filer.discard(firstEntry(vault))
        try filer.restore(discarded)

        #expect(vault.read("inbox/one.md") == before)
        #expect(DigestInbox(vaultURL: vault.rootURL).dueEntries(now: TestDates.now).count == 1)
    }

    /// Restoring a capture whose body was never readable would replace a real
    /// thought with a blank file — worse than the delete it is undoing.
    @Test("restore refuses an empty document")
    func restoreRefusesAnEmptyDocument() {
        let vault = TempVault()
        let entry = DigestEntry(
            id: UUID(),
            fileURL: vault.inboxURL.appendingPathComponent("ghost.md"),
            relativePath: "inbox/ghost.md",
            body: "",
            capturedAt: TestDates.now,
            isAvailable: false
        )
        #expect(throws: DigestFiling.FilingError.unreadable("inbox/ghost.md")) {
            try filing(vault).restore(.init(entry: entry, document: ""))
        }
        #expect(!vault.exists("inbox/ghost.md"))
    }

    /// Undo has to work even when it was the last capture and the folder was
    /// cleaned up behind it.
    @Test("restore recreates the inbox folder when it is gone")
    func restoreRecreatesTheInboxFolder() throws {
        let vault = TempVault()
        vault.writeCapture(named: "one.md", body: "Last one")

        let filer = filing(vault)
        let discarded = try filer.discard(firstEntry(vault))
        try? FileManager.default.removeItem(at: vault.inboxURL)
        #expect(!vault.exists("inbox"))

        try filer.restore(discarded)
        #expect(vault.exists("inbox/one.md"))
    }

    // MARK: - Write-failure ordering (SC6)

    /// The whole point of writing before deleting: a failed append costs a retry,
    /// never the capture.
    @Test("a failed add-to leaves the capture in the inbox")
    func failedAppendLeavesTheCaptureInTheInbox() {
        let vault = TempVault()
        vault.writeCapture(named: "one.md", body: "Precious")
        let target = vault.write("---\nid: t\nupdated: 2026-01-01T00:00:00Z\n---\n# Blocked\n", at: "Blocked.md")

        let filer = filing(vault, fileSystem: WriteBlockingFileSystem(blockedSubstring: "Blocked"))
        #expect(throws: DigestFiling.FilingError.writeFailed("Blocked.md")) {
            try filer.append(firstEntry(vault), toNoteAt: target)
        }
        #expect(vault.exists("inbox/one.md"))
        #expect(vault.read("Blocked.md")!.contains("# Blocked"))
        #expect(!vault.read("Blocked.md")!.contains("Precious"))
    }

    /// Same guarantee on the create path.
    @Test("a failed create leaves the capture in the inbox")
    func failedCreateLeavesTheCaptureInTheInbox() {
        let vault = TempVault()
        vault.writeCapture(named: "one.md", body: "Precious")

        let filer = filing(vault, fileSystem: WriteBlockingFileSystem(blockedSubstring: "Blocked"))
        #expect(throws: DigestFiling.FilingError.writeFailed("Blocked.md")) {
            try filer.createNote(from: firstEntry(vault), title: "Blocked", inFolderAt: vault.rootURL)
        }
        #expect(vault.exists("inbox/one.md"))
        #expect(!vault.exists("Blocked.md"))
    }

    /// A capture whose body is still in iCloud has nothing to file; refusing beats
    /// writing an empty paragraph into a real note.
    @Test("filing an unavailable capture fails instead of writing an empty body")
    func filingAnUnavailableCaptureFails() {
        let vault = TempVault()
        vault.writeCapture(named: "evicted.md", body: "Somewhere in iCloud")
        let target = vault.write("---\nid: t\nupdated: 2026-01-01T00:00:00Z\n---\n# A\n", at: "A.md")

        let entry = DigestInbox(vaultURL: vault.rootURL, fileSystem: UnreadableFileSystem()).allEntries().first!
        #expect(entry.isAvailable == false)
        #expect(throws: DigestFiling.FilingError.unreadable("inbox/evicted.md")) {
            try filing(vault).append(entry, toNoteAt: target)
        }
        #expect(vault.exists("inbox/evicted.md"))
    }
}
