import CryptoKit
import Foundation

/// Where a quick capture lives in the vault: `inbox/<YYYY-MM-DD>-<sha8>.md`,
/// the same shape `gbrain capture` produces. Shared by the app's
/// `CaptureFilingService` (which writes the file) and the share extension
/// (which names that file in a media job before it exists), so the two can
/// never disagree about the path.
public enum CaptureNotePath {
    public static let inboxFolderName = "inbox"

    /// Trims outer whitespace and normalizes line endings so the hash is stable
    /// across editors.
    public static func normalizedBody(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func hash8(of normalizedBody: String) -> String {
        let digest = SHA256.hash(data: Data(normalizedBody.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    public static func dateStamp(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// `inbox/<YYYY-MM-DD>-<sha8>.md` for an already-normalized body.
    public static func relativePath(for normalizedBody: String, date: Date, calendar: Calendar) -> String {
        "\(inboxFolderName)/\(dateStamp(for: date, calendar: calendar))-\(hash8(of: normalizedBody)).md"
    }

    /// Same, from a raw body; nil for a blank body (which is never filed).
    public static func relativePath(forRawBody raw: String, date: Date, calendar: Calendar = .current) -> String? {
        let body = normalizedBody(raw)
        guard !body.isEmpty else { return nil }
        return relativePath(for: body, date: date, calendar: calendar)
    }

    /// `inbox/2026-09-23-1a2b3c4d.md` — what a job may name. Anything else is rejected.
    public static func isInboxCapturePath(_ path: String) -> Bool {
        path.range(of: #"^inbox/\d{4}-\d{2}-\d{2}-[0-9a-f]{8}\.md$"#, options: .regularExpression) != nil
    }
}
