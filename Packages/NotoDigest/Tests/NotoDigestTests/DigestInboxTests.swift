import Foundation
import Testing
@testable import NotoDigest

/// What the Digest tab shows, read from a real `inbox/` folder on disk.
///
/// | Test | Covers |
/// | --- | --- |
/// | `listsOnlyTopLevelMarkdown` | SC1 — non-`.md`, hidden, and nested files are ignored |
/// | `ordersOldestCaptureFirst` | SC1 — ordering is by frontmatter `created:` |
/// | `hidesCapturesSnoozedIntoTheFuture` | SC1 — future `snoozed_until` drops out of `dueEntries` |
/// | `showsCapturesWhoseSnoozeHasElapsed` | SC1 — a lapsed snooze returns to the digest |
/// | `allEntriesStillIncludesSnoozed` | SC1 — the snoozed ones are readable, just not due |
/// | `missingInboxFolderIsEmptyNotAnError` | SC1 — a vault that never captured anything |
/// | `treatsMalformedSnoozeAsDue` | SC7 — an unparseable stamp never hides a capture |
/// | `treatsMissingFrontmatterAsDue` | SC7 — a frontmatter-less file still lists, with a derived id |
/// | `parsesBothIsoFormsAndBareDates` | SC7 — fractional seconds and `YYYY-MM-DD` both parse |
/// | `stripsFrontmatterFromTheCardBody` | SC1 — the card shows the thought, not the YAML |
/// | `unreadableCaptureIsListedAsUnavailable` | SC7 — a dataless iCloud stub is surfaced, not dropped |
@Suite("DigestInbox — reading the inbox")
struct DigestInboxTests {
    /// Only top-level markdown counts: `CaptureFilingService` writes a flat
    /// `inbox/`, and an attachment or a stray folder must not become a card.
    @Test("lists only top-level .md files")
    func listsOnlyTopLevelMarkdown() {
        let vault = TempVault()
        vault.writeCapture(named: "2026-08-30-aaaaaaaa.md", body: "A thought")
        vault.write("not markdown", at: "inbox/notes.txt")
        vault.write("nested", at: "inbox/sub/deep.md")

        let entries = DigestInbox(vaultURL: vault.rootURL).allEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.relativePath == "inbox/2026-08-30-aaaaaaaa.md")
    }

    /// The digest works the backlog front-to-back, so the oldest thought surfaces
    /// first.
    @Test("orders oldest capture first")
    func ordersOldestCaptureFirst() {
        let vault = TempVault()
        vault.writeCapture(named: "2026-08-30-cccccccc.md", body: "Newest", created: "2026-08-30T09:00:00Z")
        vault.writeCapture(named: "2026-08-28-aaaaaaaa.md", body: "Oldest", created: "2026-08-28T09:00:00Z")
        vault.writeCapture(named: "2026-08-29-bbbbbbbb.md", body: "Middle", created: "2026-08-29T09:00:00Z")

        let bodies = DigestInbox(vaultURL: vault.rootURL).allEntries().map(\.body)
        #expect(bodies == ["Oldest", "Middle", "Newest"])
    }

    /// The point of snoozing.
    @Test("hides captures snoozed into the future")
    func hidesCapturesSnoozedIntoTheFuture() {
        let vault = TempVault()
        vault.writeCapture(named: "due.md", body: "Due now")
        vault.writeCapture(named: "later.md", body: "Not yet", snoozedUntil: "2026-09-08T12:00:00Z")

        let due = DigestInbox(vaultURL: vault.rootURL).dueEntries(now: TestDates.now)
        #expect(due.map(\.body) == ["Due now"])
    }

    /// A week later it comes back.
    @Test("shows captures whose snooze has elapsed")
    func showsCapturesWhoseSnoozeHasElapsed() {
        let vault = TempVault()
        vault.writeCapture(named: "lapsed.md", body: "Back again", snoozedUntil: "2026-08-25T12:00:00Z")

        let due = DigestInbox(vaultURL: vault.rootURL).dueEntries(now: TestDates.now)
        #expect(due.map(\.body) == ["Back again"])
    }

    /// Snoozed captures are hidden from the queue, not from the vault.
    @Test("allEntries still includes snoozed captures")
    func allEntriesStillIncludesSnoozed() {
        let vault = TempVault()
        vault.writeCapture(named: "later.md", body: "Not yet", snoozedUntil: "2026-09-08T12:00:00Z")

        let inbox = DigestInbox(vaultURL: vault.rootURL)
        #expect(inbox.allEntries().count == 1)
        #expect(inbox.dueEntries(now: TestDates.now).isEmpty)
        #expect(inbox.allEntries().first?.snoozedUntil == TestDates.iso("2026-09-08T12:00:00Z"))
    }

    /// A vault that has never been captured into has no `inbox/` at all.
    @Test("a missing inbox folder reads as empty, not an error")
    func missingInboxFolderIsEmptyNotAnError() {
        let vault = TempVault()
        #expect(DigestInbox(vaultURL: vault.rootURL).allEntries().isEmpty)
        #expect(DigestInbox(vaultURL: vault.rootURL).dueEntries(now: TestDates.now).isEmpty)
    }

    /// A typo in a hand-edited stamp must fail open. Failing closed would hide the
    /// capture forever with no way to find it from the app.
    @Test("an unparseable snoozed_until is treated as due")
    func treatsMalformedSnoozeAsDue() {
        let vault = TempVault()
        vault.writeCapture(named: "typo.md", body: "Still here", snoozedUntil: "next tuesday")

        let due = DigestInbox(vaultURL: vault.rootURL).dueEntries(now: TestDates.now)
        #expect(due.map(\.body) == ["Still here"])
        #expect(due.first?.snoozedUntil == nil)
    }

    /// A file dropped into `inbox/` by hand has no frontmatter; it still lists,
    /// with an id derived from its filename so the card stack has a stable key.
    @Test("a capture with no frontmatter lists as due with a derived id")
    func treatsMissingFrontmatterAsDue() {
        let vault = TempVault()
        vault.write("Just a raw thought\n", at: "inbox/raw.md")

        let entries = DigestInbox(vaultURL: vault.rootURL).dueEntries(now: TestDates.now)
        #expect(entries.count == 1)
        #expect(entries.first?.body == "Just a raw thought")
        #expect(entries.first?.id == DigestInbox.derivedID(for: vault.inboxURL.appendingPathComponent("raw.md")))
    }

    /// Timestamps in the wild come in several shapes; all of them must resolve.
    @Test("parses plain ISO, fractional-seconds ISO, and bare YYYY-MM-DD stamps")
    func parsesBothIsoFormsAndBareDates() {
        #expect(DigestInbox.parseTimestamp("2026-09-08T12:00:00Z") == TestDates.iso("2026-09-08T12:00:00Z"))
        #expect(DigestInbox.parseTimestamp("2026-09-08T12:00:00.123Z") != nil)
        #expect(DigestInbox.parseTimestamp("2026-09-08") != nil)
        #expect(DigestInbox.parseTimestamp("not a date") == nil)
        #expect(DigestInbox.parseTimestamp("") == nil)
    }

    /// The card shows the thought. YAML on the card would be a bug.
    @Test("the entry body has frontmatter stripped and whitespace trimmed")
    func stripsFrontmatterFromTheCardBody() {
        let vault = TempVault()
        vault.writeCapture(named: "one.md", body: "  Buy oat milk  ")

        let entry = DigestInbox(vaultURL: vault.rootURL).allEntries().first
        #expect(entry?.body == "Buy oat milk")
        #expect(entry?.body.contains("---") == false)
        #expect(entry?.summary == "Buy oat milk")
    }

    /// On an iCloud vault the body can be evicted. The capture still exists, so it
    /// still gets a card — flagged unavailable so the UI can say why.
    @Test("an unreadable capture is listed as unavailable rather than dropped")
    func unreadableCaptureIsListedAsUnavailable() {
        let vault = TempVault()
        vault.writeCapture(named: "evicted.md", body: "Somewhere in iCloud")

        let entries = DigestInbox(vaultURL: vault.rootURL, fileSystem: UnreadableFileSystem()).allEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.isAvailable == false)
        #expect(entries.first?.body == "")
        #expect(entries.first?.isDue(at: TestDates.now) == true)
    }
}
