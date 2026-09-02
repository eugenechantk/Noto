import Foundation
import NotoVault

/// A throwaway vault on disk. The digest's whole job is filesystem side effects,
/// so the suites drive real files through the real `CoordinatedVaultFileSystem`
/// and only stub the clock, the UUID source, and (for failure paths) the writer.
final class TempVault {
    let rootURL: URL

    init() {
        rootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("noto-digest-tests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    var inboxURL: URL { rootURL.appendingPathComponent("inbox", isDirectory: true) }

    /// Writes a capture the way `CaptureFilingService` does.
    @discardableResult
    func writeCapture(
        named name: String,
        body: String,
        id: UUID = UUID(),
        created: String = "2026-08-30T09:00:00Z",
        snoozedUntil: String? = nil
    ) -> URL {
        try? FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        var lines = [
            "---",
            "id: \(id.uuidString)",
            "created: \(created)",
            "updated: \(created)",
            "type: note",
            "status: inbox",
        ]
        if let snoozedUntil { lines.append("snoozed_until: \(snoozedUntil)") }
        lines.append(contentsOf: ["---", "", ""])
        let url = inboxURL.appendingPathComponent(name)
        try? (lines.joined(separator: "\n") + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Writes an arbitrary file relative to the vault root, creating parents.
    @discardableResult
    func write(_ contents: String, at relativePath: String) -> URL {
        let url = rootURL.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func read(_ relativePath: String) -> String? {
        try? String(contentsOf: rootURL.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(relativePath).path)
    }
}

/// Real filesystem, except writes to paths whose name contains `blockedSubstring`
/// fail. Models "the destination write didn't land" so the ordering guarantee —
/// inbox file survives a failed file — can be proven.
struct WriteBlockingFileSystem: VaultFileSystem {
    let blockedSubstring: String
    private let underlying = CoordinatedVaultFileSystem()

    func fileExists(at url: URL) -> Bool { underlying.fileExists(at: url) }
    func isReadableFile(at url: URL) -> Bool { underlying.isReadableFile(at: url) }
    func readString(from url: URL) -> String? { underlying.readString(from: url) }
    func readData(from url: URL) -> Data? { underlying.readData(from: url) }
    func readPrefix(from url: URL, maxBytes: Int) -> Data? { underlying.readPrefix(from: url, maxBytes: maxBytes) }
    func isDownloaded(at url: URL) -> Bool { underlying.isDownloaded(at: url) }
    func startDownloading(at url: URL) { underlying.startDownloading(at: url) }

    @discardableResult
    func writeString(_ content: String, to url: URL) -> Bool {
        guard !url.lastPathComponent.contains(blockedSubstring) else { return false }
        return underlying.writeString(content, to: url)
    }

    @discardableResult
    func writeData(_ data: Data, to url: URL) -> Bool { underlying.writeData(data, to: url) }
    @discardableResult
    func delete(at url: URL) -> Bool { underlying.delete(at: url) }
    @discardableResult
    func move(from sourceURL: URL, to destinationURL: URL) -> Bool { underlying.move(from: sourceURL, to: destinationURL) }
    @discardableResult
    func createDirectory(at url: URL) -> Bool { underlying.createDirectory(at: url) }
}

/// Real filesystem that reports every read as unavailable, standing in for an
/// iCloud vault whose note bodies have been evicted.
struct UnreadableFileSystem: VaultFileSystem {
    private let underlying = CoordinatedVaultFileSystem()

    func fileExists(at url: URL) -> Bool { underlying.fileExists(at: url) }
    func isReadableFile(at url: URL) -> Bool { false }
    func readString(from url: URL) -> String? { nil }
    func readData(from url: URL) -> Data? { nil }
    func readPrefix(from url: URL, maxBytes: Int) -> Data? { nil }
    func isDownloaded(at url: URL) -> Bool { false }
    func startDownloading(at url: URL) {}

    @discardableResult
    func writeString(_ content: String, to url: URL) -> Bool { underlying.writeString(content, to: url) }
    @discardableResult
    func writeData(_ data: Data, to url: URL) -> Bool { underlying.writeData(data, to: url) }
    @discardableResult
    func delete(at url: URL) -> Bool { underlying.delete(at: url) }
    @discardableResult
    func move(from sourceURL: URL, to destinationURL: URL) -> Bool { underlying.move(from: sourceURL, to: destinationURL) }
    @discardableResult
    func createDirectory(at url: URL) -> Bool { underlying.createDirectory(at: url) }
}

enum TestDates {
    static func iso(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }

    /// Fixed "now" for the suites: 2026-09-01T12:00:00Z.
    static let now = iso("2026-09-01T12:00:00Z")
}
