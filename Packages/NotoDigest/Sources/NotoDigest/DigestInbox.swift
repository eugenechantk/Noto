import Foundation
import NotoVault

/// Reads the `inbox/` folder of a vault into digest entries.
///
/// Flat by design: `CaptureFilingService` writes `inbox/<date>-<sha8>.md` with no
/// sub-folders, so this does not recurse. Anything that is not a top-level `.md`
/// file is ignored.
public struct DigestInbox: Sendable {
    public static let folderName = "inbox"

    public let vaultURL: URL
    private let fileSystem: any VaultFileSystem

    public init(vaultURL: URL, fileSystem: any VaultFileSystem = CoordinatedVaultFileSystem()) {
        self.vaultURL = vaultURL.standardizedFileURL
        self.fileSystem = fileSystem
    }

    public var folderURL: URL {
        vaultURL.appendingPathComponent(Self.folderName, isDirectory: true)
    }

    /// Every capture in `inbox/`, oldest first, including snoozed ones.
    public func allEntries() -> [DigestEntry] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }

        return urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap(entry(at:))
            .sorted { lhs, rhs in
                if lhs.capturedAt != rhs.capturedAt { return lhs.capturedAt < rhs.capturedAt }
                return lhs.relativePath < rhs.relativePath
            }
    }

    /// The captures the digest should present at `now`: everything except those
    /// snoozed into the future.
    public func dueEntries(now: Date = Date()) -> [DigestEntry] {
        allEntries().filter { $0.isDue(at: now) }
    }

    /// Re-reads a single capture from disk — used after an action to confirm the
    /// file's new state, and to pick up an iCloud download that has landed.
    public func entry(at fileURL: URL) -> DigestEntry? {
        let standardized = fileURL.standardizedFileURL
        guard fileSystem.fileExists(at: standardized) else { return nil }

        let relativePath = Self.folderName + "/" + standardized.lastPathComponent
        let modifiedDate = (try? standardized.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date.distantPast

        guard let content = fileSystem.readString(from: standardized) else {
            // Dataless iCloud stub: surface it as unavailable and ask for the
            // download rather than pretending the inbox is emptier than it is.
            fileSystem.startDownloading(at: standardized)
            return DigestEntry(
                id: Self.derivedID(for: standardized),
                fileURL: standardized,
                relativePath: relativePath,
                body: "",
                capturedAt: modifiedDate,
                snoozedUntil: nil,
                isAvailable: false
            )
        }

        return DigestEntry(
            id: NoteFrontmatter.id(of: content) ?? Self.derivedID(for: standardized),
            fileURL: standardized,
            relativePath: relativePath,
            body: VaultMarkdown.stripFrontmatter(content).trimmingCharacters(in: .whitespacesAndNewlines),
            capturedAt: Self.capturedDate(from: content) ?? modifiedDate,
            snoozedUntil: Self.snoozeDate(from: content),
            isAvailable: true
        )
    }

    // MARK: - Parsing

    /// The `snoozed_until` stamp, or `nil` when absent or unparseable. Unparseable
    /// deliberately means *due*: a typo in the vault must not hide a capture forever.
    static func snoozeDate(from content: String) -> Date? {
        guard let raw = NoteFrontmatter.value(for: DigestFiling.snoozeKey, in: content) else { return nil }
        return parseTimestamp(raw)
    }

    static func capturedDate(from content: String) -> Date? {
        guard let raw = NoteFrontmatter.value(for: "created", in: content) else { return nil }
        return parseTimestamp(raw)
    }

    /// Accepts both the plain and fractional-seconds ISO-8601 forms, plus a bare
    /// `YYYY-MM-DD` (what a hand-edited snooze is most likely to look like).
    static func parseTimestamp(_ raw: String) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: value) { return date }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let dayOnly = DateFormatter()
        dayOnly.calendar = Calendar(identifier: .gregorian)
        dayOnly.locale = Locale(identifier: "en_US_POSIX")
        dayOnly.timeZone = TimeZone(secondsFromGMT: 0)
        dayOnly.dateFormat = "yyyy-MM-dd"
        return dayOnly.date(from: value)
    }

    /// A stable UUID for a capture whose frontmatter has no `id:` — derived from
    /// the filename so the same file keeps the same identity across reloads.
    static func derivedID(for fileURL: URL) -> UUID {
        var bytes = Array(Data(fileURL.lastPathComponent.utf8).prefix(16))
        while bytes.count < 16 { bytes.append(0) }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
