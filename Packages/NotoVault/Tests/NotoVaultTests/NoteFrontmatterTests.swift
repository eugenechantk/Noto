import Foundation
import Testing
@testable import NotoVault

@Suite("NoteFrontmatter — programmatic write stamping")
struct NoteFrontmatterTests {
    private let note = """
    ---
    id: a1b2c3d4-e5f6-7890-abcd-000000000002
    created: 2026-03-15T10:00:00Z
    modified: 2026-03-15T10:00:00Z
    ---
    # Shopping List

    - Fruits
    """

    @Test("stampingModified updates only the modified line, preserving id/created/body")
    func stampsModifiedOnly() {
        let date = ISO8601DateFormatter().date(from: "2026-06-25T12:00:00Z")!
        let out = NoteFrontmatter.stampingModified(note, to: date)
        #expect(out.contains("modified: 2026-06-25T12:00:00Z"))
        #expect(!out.contains("modified: 2026-03-15T10:00:00Z"))
        #expect(out.contains("id: a1b2c3d4-e5f6-7890-abcd-000000000002"))   // preserved
        #expect(out.contains("created: 2026-03-15T10:00:00Z"))             // preserved
        #expect(out.contains("# Shopping List\n\n- Fruits"))               // body preserved
    }

    @Test("stampingModified inserts a modified line when none exists")
    func insertsModifiedWhenMissing() {
        let md = "---\nid: a1b2c3d4-e5f6-7890-abcd-000000000002\ncreated: 2026-03-15T10:00:00Z\n---\nbody"
        let date = ISO8601DateFormatter().date(from: "2026-06-25T12:00:00Z")!
        let out = NoteFrontmatter.stampingModified(md, to: date)
        #expect(out.contains("modified: 2026-06-25T12:00:00Z"))
        #expect(out.contains("body"))
    }

    @Test("stampingModified is a no-op without frontmatter")
    func noopWithoutFrontmatter() {
        let md = "# Just a body\n- item"
        #expect(NoteFrontmatter.stampingModified(md, to: Date()) == md)
    }

    @Test("id(of:) reads the frontmatter UUID")
    func readsID() {
        #expect(NoteFrontmatter.id(of: note) == UUID(uuidString: "a1b2c3d4-e5f6-7890-abcd-000000000002"))
        #expect(NoteFrontmatter.id(of: "# no frontmatter") == nil)
    }
}

/// Generic key access used by any programmatic frontmatter write (the digest's
/// `snoozed_until` is the first caller).
///
/// | Test | Covers |
/// | --- | --- |
/// | `readsValue` | `value(for:)` finds a key, is case-insensitive, keeps colons in the value |
/// | `returnsNilForMissingKeyOrFrontmatter` | absent key and frontmatter-less markdown both read as `nil` |
/// | `setsNewKeyBeforeClosingFence` | a missing key is appended inside the block, body untouched |
/// | `rewritesExistingKeyInPlace` | an existing key is replaced, never duplicated |
/// | `settingIsNoopWithoutFrontmatter` | markdown with no `---` block is returned unchanged |
/// | `removesKey` | `removing(_:)` drops the line and leaves everything else |
@Suite("NoteFrontmatter — generic key read/write")
struct NoteFrontmatterKeyTests {
    private let note = """
    ---
    id: a1b2c3d4-e5f6-7890-abcd-000000000002
    created: 2026-03-15T10:00:00Z
    status: inbox
    ---
    # Shopping List

    - Fruits
    """

    /// A key's value is found regardless of case, and an ISO timestamp's inner
    /// colons survive the split.
    @Test("value(for:) reads a key case-insensitively and keeps colons in the value")
    func readsValue() {
        #expect(NoteFrontmatter.value(for: "status", in: note) == "inbox")
        #expect(NoteFrontmatter.value(for: "STATUS", in: note) == "inbox")
        #expect(NoteFrontmatter.value(for: "created", in: note) == "2026-03-15T10:00:00Z")
    }

    /// Absent keys and frontmatter-less documents are both `nil`, not empty string.
    @Test("value(for:) is nil for an absent key or absent frontmatter")
    func returnsNilForMissingKeyOrFrontmatter() {
        #expect(NoteFrontmatter.value(for: "snoozed_until", in: note) == nil)
        #expect(NoteFrontmatter.value(for: "status", in: "# no frontmatter\nbody") == nil)
    }

    /// A new key lands inside the fence, above the closing `---`, and the body is
    /// byte-for-byte unchanged.
    @Test("setting(_:to:) appends a missing key before the closing fence")
    func setsNewKeyBeforeClosingFence() {
        let out = NoteFrontmatter.setting("snoozed_until", to: "2026-09-08T12:00:00Z", in: note)
        #expect(out.contains("status: inbox\nsnoozed_until: 2026-09-08T12:00:00Z\n---"))
        #expect(out.hasSuffix("# Shopping List\n\n- Fruits"))
        #expect(NoteFrontmatter.value(for: "snoozed_until", in: out) == "2026-09-08T12:00:00Z")
    }

    /// Re-snoozing must overwrite, not stack duplicate keys.
    @Test("setting(_:to:) rewrites an existing key in place without duplicating it")
    func rewritesExistingKeyInPlace() {
        let once = NoteFrontmatter.setting("snoozed_until", to: "2026-09-08T12:00:00Z", in: note)
        let twice = NoteFrontmatter.setting("snoozed_until", to: "2026-09-15T12:00:00Z", in: once)
        #expect(NoteFrontmatter.value(for: "snoozed_until", in: twice) == "2026-09-15T12:00:00Z")
        #expect(twice.components(separatedBy: "snoozed_until:").count - 1 == 1)
        #expect(twice.contains("id: a1b2c3d4-e5f6-7890-abcd-000000000002"))
    }

    /// Without a `---` block there is nowhere to put the key; the input comes back
    /// untouched rather than gaining a malformed header.
    @Test("setting(_:to:) is a no-op without frontmatter")
    func settingIsNoopWithoutFrontmatter() {
        let md = "# Just a body\n- item"
        #expect(NoteFrontmatter.setting("snoozed_until", to: "x", in: md) == md)
    }

    /// Un-snoozing drops only that line.
    @Test("removing(_:) drops the key and leaves the rest intact")
    func removesKey() {
        let snoozed = NoteFrontmatter.setting("snoozed_until", to: "2026-09-08T12:00:00Z", in: note)
        let out = NoteFrontmatter.removing("snoozed_until", in: snoozed)
        #expect(out == note)
    }
}

/// Refreshing a note's write timestamp when the vault uses two different keys
/// for it (`updated:` from `VaultMarkdown.makeFrontmatter`, `modified:` from the
/// AI/agent paths and older notes).
///
/// | Test | Covers |
/// | --- | --- |
/// | `stampsUpdatedWhenThatIsTheKey` | notes written by the editor |
/// | `stampsModifiedWhenThatIsTheKey` | notes written by the main app / older vault |
/// | `stampsBothWhenBothArePresent` | mixed notes don't keep half a stale timestamp |
/// | `doesNotInventATimestampKey` | a note tracking neither stays that way |
/// | `preservesEveryOtherKeyAndTheBody` | only the timestamp lines move |
@Suite("NoteFrontmatter — stamping whichever timestamp key exists")
struct NoteFrontmatterExistingTimestampTests {
    private let date = ISO8601DateFormatter().date(from: "2026-09-01T13:00:00Z")!

    /// The convention `VaultMarkdown.makeFrontmatter` writes.
    @Test("stamps updated: when that is the note's key")
    func stampsUpdatedWhenThatIsTheKey() {
        let md = "---\nid: x\ncreated: 2026-01-01T00:00:00Z\nupdated: 2026-01-01T00:00:00Z\n---\n# A\n"
        let out = NoteFrontmatter.stampingExistingTimestamps(md, to: date)
        #expect(NoteFrontmatter.value(for: "updated", in: out) == "2026-09-01T13:00:00Z")
        #expect(NoteFrontmatter.value(for: "created", in: out) == "2026-01-01T00:00:00Z")
    }

    /// The convention the main Noto app and the seeded vault use. Missing this is
    /// what left `Meeting Notes.md` claiming it was last modified in March after
    /// the digest appended to it.
    @Test("stamps modified: when that is the note's key")
    func stampsModifiedWhenThatIsTheKey() {
        let md = "---\nid: x\ncreated: 2026-03-15T09:00:00Z\nmodified: 2026-03-15T09:00:00Z\n---\n# A\n"
        let out = NoteFrontmatter.stampingExistingTimestamps(md, to: date)
        #expect(NoteFrontmatter.value(for: "modified", in: out) == "2026-09-01T13:00:00Z")
        #expect(!out.contains("modified: 2026-03-15T09:00:00Z"))
    }

    /// A note carrying both must not come away with one fresh and one stale.
    @Test("stamps both keys when both are present")
    func stampsBothWhenBothArePresent() {
        let md = "---\nid: x\nupdated: 2026-01-01T00:00:00Z\nmodified: 2026-01-01T00:00:00Z\n---\nbody\n"
        let out = NoteFrontmatter.stampingExistingTimestamps(md, to: date)
        #expect(NoteFrontmatter.value(for: "updated", in: out) == "2026-09-01T13:00:00Z")
        #expect(NoteFrontmatter.value(for: "modified", in: out) == "2026-09-01T13:00:00Z")
    }

    /// Adding a timestamp key to a note that never had one is a change the user
    /// did not ask for; leave it alone.
    @Test("does not invent a timestamp key")
    func doesNotInventATimestampKey() {
        let md = "---\nid: x\ncreated: 2026-01-01T00:00:00Z\n---\n# A\n"
        #expect(NoteFrontmatter.stampingExistingTimestamps(md, to: date) == md)
        #expect(NoteFrontmatter.stampingExistingTimestamps("# no frontmatter", to: date) == "# no frontmatter")
    }

    /// Everything that is not a timestamp survives byte-for-byte.
    @Test("preserves every other key and the body")
    func preservesEveryOtherKeyAndTheBody() {
        let md = "---\nid: abc\ncreated: 2026-01-01T00:00:00Z\nmodified: 2026-01-01T00:00:00Z\ntags: [a, b]\n---\n# Title\n\n- one\n"
        let out = NoteFrontmatter.stampingExistingTimestamps(md, to: date)
        #expect(NoteFrontmatter.value(for: "id", in: out) == "abc")
        #expect(NoteFrontmatter.value(for: "tags", in: out) == "[a, b]")
        #expect(out.hasSuffix("# Title\n\n- one\n"))
    }
}
