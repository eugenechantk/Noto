import CryptoKit
import Foundation
import NotoVault

/// Files a quick capture into the vault's `inbox/` folder as
/// `inbox/<YYYY-MM-DD>-<sha8>.md` — the same shape `gbrain capture` produces,
/// so the brain's cycle types it as a `note` (extractable, facts-eligible).
///
/// Pure filesystem logic, no UI. The caller schedules search indexing.
struct CaptureFilingService {
    struct Filed: Equatable {
        let fileURL: URL
        /// Vault-relative path, e.g. `inbox/2026-08-23-a1b2c3d4.md`.
        let relativePath: String
        let id: UUID
        /// False when an identical capture (same body, same day) already existed;
        /// the existing file is left untouched.
        let didCreate: Bool
    }

    enum FilingError: Error, Equatable {
        case emptyBody
        case writeFailed(String)
    }

    static let inboxFolderName = "inbox"
    static let pageType = "note"
    static let inboxStatus = "inbox"

    let vaultURL: URL
    var now: () -> Date = Date.init
    var makeID: () -> UUID = UUID.init
    var calendar: Calendar = .current
    /// Injected so tests can run without file coordination; defaults to the
    /// coordinated writer Noto uses for iCloud vaults.
    var writeString: (String, URL) -> Bool = { CoordinatedFileManager.writeString($0, to: $1) }
    var createDirectory: (URL) -> Bool = { CoordinatedFileManager.createDirectory(at: $0) }

    init(vaultURL: URL) {
        self.vaultURL = vaultURL
    }

    // MARK: - Pure pieces (unit-testable)

    /// Trims outer whitespace and normalizes line endings so the hash is stable
    /// across editors. The stored body keeps the trimmed text as-is.
    static func normalizedBody(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func hash8(of normalizedBody: String) -> String {
        let digest = SHA256.hash(data: Data(normalizedBody.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    static func dateStamp(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// `inbox/<YYYY-MM-DD>-<sha8>.md`
    static func relativePath(for normalizedBody: String, date: Date, calendar: Calendar) -> String {
        "\(inboxFolderName)/\(dateStamp(for: date, calendar: calendar))-\(hash8(of: normalizedBody)).md"
    }

    /// Frontmatter block followed by one blank line, so the body starts on its own paragraph.
    static func frontmatter(id: UUID, date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: date)
        return [
            "---",
            "id: \(id.uuidString)",
            "created: \(stamp)",
            "updated: \(stamp)",
            "type: \(pageType)",
            "status: \(inboxStatus)",
            "---",
            "",
            "",
        ].joined(separator: "\n")
    }

    static func document(body normalizedBody: String, id: UUID, date: Date) -> String {
        frontmatter(id: id, date: date) + normalizedBody + "\n"
    }

    // MARK: - Filing

    /// Where a body would be filed right now, without writing anything.
    func plannedURL(for rawBody: String) -> URL? {
        let body = Self.normalizedBody(rawBody)
        guard !body.isEmpty else { return nil }
        return vaultURL.appendingPathComponent(Self.relativePath(for: body, date: now(), calendar: calendar))
    }

    func file(_ rawBody: String) throws -> Filed {
        let body = Self.normalizedBody(rawBody)
        guard !body.isEmpty else { throw FilingError.emptyBody }

        let date = now()
        let relativePath = Self.relativePath(for: body, date: date, calendar: calendar)
        let fileURL = vaultURL.appendingPathComponent(relativePath)
        let folderURL = fileURL.deletingLastPathComponent()

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let existingID = CoordinatedFileManager.readString(from: fileURL)
                .flatMap(VaultMarkdown.idFromFrontmatter) ?? makeID()
            return Filed(fileURL: fileURL, relativePath: relativePath, id: existingID, didCreate: false)
        }

        if !FileManager.default.fileExists(atPath: folderURL.path) {
            guard createDirectory(folderURL) else {
                throw FilingError.writeFailed("could not create \(Self.inboxFolderName)/")
            }
        }

        let id = makeID()
        let content = Self.document(body: body, id: id, date: date)
        guard writeString(content, fileURL) else {
            throw FilingError.writeFailed("could not write \(relativePath)")
        }
        return Filed(fileURL: fileURL, relativePath: relativePath, id: id, didCreate: true)
    }
}
