import Foundation

/// One capture waiting in `inbox/`, as the Digest screen sees it.
///
/// The body is frontmatter-stripped and trimmed — the digest card shows the
/// thought, not the YAML. `snoozedUntil` is the parsed `snoozed_until` key; a
/// missing or unparseable value reads as `nil`, which means *due now* (a capture
/// must never disappear because its frontmatter was malformed).
public struct DigestEntry: Identifiable, Equatable, Sendable {
    /// The frontmatter `id:`, or a UUID derived from the path when the file has
    /// none — a capture with broken frontmatter still needs a stable identity to
    /// drive SwiftUI's card stack.
    public let id: UUID
    public let fileURL: URL
    /// Vault-relative, e.g. `inbox/2026-08-30-a1b2c3d4.md`.
    public let relativePath: String
    /// The capture text with frontmatter stripped and outer whitespace trimmed.
    /// Empty when `isAvailable` is false.
    public let body: String
    /// The frontmatter `created:` stamp, falling back to the file's modification
    /// date. Feeds `queuedAt`, which drives ordering.
    public let capturedAt: Date
    public let snoozedUntil: Date?
    /// False when the file exists but could not be read — on an iCloud vault a
    /// note can be evicted to a dataless stub. Such an entry is shown as
    /// downloading rather than silently dropped, because dropping it would make
    /// the inbox look emptier than it is.
    public let isAvailable: Bool

    public init(
        id: UUID,
        fileURL: URL,
        relativePath: String,
        body: String,
        capturedAt: Date,
        snoozedUntil: Date? = nil,
        isAvailable: Bool = true
    ) {
        self.id = id
        self.fileURL = fileURL
        self.relativePath = relativePath
        self.body = body
        self.capturedAt = capturedAt
        self.snoozedUntil = snoozedUntil
        self.isAvailable = isAvailable
    }

    /// When this capture (re)entered the digest: the snooze wake time for a
    /// snoozed capture, otherwise when it was captured. Drives newest-first
    /// ordering, so a capture returning from a snooze slots in among fresh
    /// captures as if it had just arrived at its wake time.
    public var queuedAt: Date {
        snoozedUntil ?? capturedAt
    }

    /// True when this capture should appear in the digest at `date`.
    public func isDue(at date: Date) -> Bool {
        guard let snoozedUntil else { return true }
        return snoozedUntil <= date
    }

    /// First non-empty line of the body, for a one-line card summary.
    public var summary: String {
        body.split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            ?? ""
    }
}
