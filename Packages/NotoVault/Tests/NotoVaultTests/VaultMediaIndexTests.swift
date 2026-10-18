import Foundation
import Testing
@testable import NotoVault

/// Test case index
/// 1. secondScanReusesUnchangedNotesWithoutReading — SC1: an unchanged note is not read again; same items
/// 2. changedNewAndDeletedNotesAreReflected — SC2: edited notes re-read, new notes appear, deleted notes drop out
/// 3. evictedNotesAreNeverReadAndKeepTheirLastMedia — SC3: no read of an evicted note; download started; last items kept
/// 4. evictedNoteNeverSeenCountsAsUnavailable — SC3: an evicted note with no history is unavailable, not read
/// 5. cachedSnapshotNeedsNoReads — SC4: the last scan renders with zero note reads, even with every note evicted
/// 6. cachedNotesSearchCurrentLinkMetadata — SC5: search text for a reused note uses the latest link metadata
/// 7. corruptIndexFallsBackToFullScan — SC6: garbage on disk means a normal full scan, then a valid index
/// 8. thumbnailStoreRoundTripsAndKeysOnFileIdentity — SC7: data survives a new store instance; a changed file misses
/// 9. thumbnailStorePrunesOldestBeyondLimit — SC7: the store stays bounded
struct VaultMediaIndexTests {
    private func makeVault() throws -> URL {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("media-index-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("inbox"), withIntermediateDirectories: true)
        return vault
    }

    private func indexURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("media-index-\(UUID().uuidString).json")
    }

    @Test func secondScanReusesUnchangedNotesWithoutReading() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        try "# A\n![](.attachments/a.jpg)".write(to: vault.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "# B\nno media here".write(to: vault.appendingPathComponent("inbox/b.md"), atomically: true, encoding: .utf8)
        let index = indexURL()
        defer { try? FileManager.default.removeItem(at: index) }

        let fs = RecordingFileSystem()
        let first = try VaultMediaLibrary(vaultURL: vault, fileSystem: fs, indexURL: index).scan()
        #expect(fs.reads.count == 2)

        let fs2 = RecordingFileSystem()
        let second = try VaultMediaLibrary(vaultURL: vault, fileSystem: fs2, indexURL: index).scan()
        #expect(fs2.reads.isEmpty)
        #expect(second.items.map(\.id) == first.items.map(\.id))
        #expect(second.items.first?.mediaURL == vault.appendingPathComponent(".attachments/a.jpg").standardizedFileURL)
        #expect(second.items.first?.noteTitle == "A")
    }

    @Test func changedNewAndDeletedNotesAreReflected() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let a = vault.appendingPathComponent("a.md")
        let b = vault.appendingPathComponent("b.md")
        try "# A\n![](.attachments/a.jpg)".write(to: a, atomically: true, encoding: .utf8)
        try "# B\n![](.attachments/b.png)".write(to: b, atomically: true, encoding: .utf8)
        let index = indexURL()
        defer { try? FileManager.default.removeItem(at: index) }
        _ = try VaultMediaLibrary(vaultURL: vault, indexURL: index).scan()

        try "# A edited\n![](.attachments/a.mp4)".write(to: a, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: b)
        try "# C\n![](.attachments/c.jpg)".write(to: vault.appendingPathComponent("inbox/c.md"), atomically: true, encoding: .utf8)

        let fs = RecordingFileSystem()
        let result = try VaultMediaLibrary(vaultURL: vault, fileSystem: fs, indexURL: index).scan()
        #expect(Set(fs.reads.map(\.lastPathComponent)) == ["a.md", "c.md"])
        #expect(Set(result.items.map(\.noteTitle)) == ["A edited", "C"])
        #expect(result.items.first { $0.noteTitle == "A edited" }?.kind == .video)
    }

    @Test func evictedNotesAreNeverReadAndKeepTheirLastMedia() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let a = vault.appendingPathComponent("a.md")
        try "# A\n![](.attachments/a.jpg)".write(to: a, atomically: true, encoding: .utf8)
        let index = indexURL()
        defer { try? FileManager.default.removeItem(at: index) }
        _ = try VaultMediaLibrary(vaultURL: vault, indexURL: index).scan()

        // Edited elsewhere and now evicted on this device.
        try "# A newer\n![](.attachments/new.jpg)".write(to: a, atomically: true, encoding: .utf8)
        let fs = RecordingFileSystem(evicted: [a])
        let result = try VaultMediaLibrary(vaultURL: vault, fileSystem: fs, indexURL: index).scan()
        #expect(fs.reads.isEmpty)
        #expect(fs.downloadsStarted.map(\.lastPathComponent) == ["a.md"])
        #expect(result.items.map(\.noteTitle) == ["A"])
        #expect(result.unavailableNoteCount == 0)
    }

    @Test func evictedNoteNeverSeenCountsAsUnavailable() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let a = vault.appendingPathComponent("a.md")
        try "# A\n![](.attachments/a.jpg)".write(to: a, atomically: true, encoding: .utf8)
        let fs = RecordingFileSystem(evicted: [a])
        let result = try VaultMediaLibrary(vaultURL: vault, fileSystem: fs, indexURL: indexURL()).scan()
        #expect(fs.reads.isEmpty)
        #expect(result.items.isEmpty)
        #expect(result.unavailableNoteCount == 1)
        // Without an index the scan must not block on evicted notes either.
        let plain = try VaultMediaLibrary(vaultURL: vault, fileSystem: fs).scan()
        #expect(fs.reads.isEmpty)
        #expect(plain.unavailableNoteCount == 1)
    }

    @Test func cachedSnapshotNeedsNoReads() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let a = vault.appendingPathComponent("a.md")
        let b = vault.appendingPathComponent("inbox/b.md")
        try "# A\n![](.attachments/a.jpg)".write(to: a, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 10)], ofItemAtPath: a.path)
        try "# B\n![](https://cdn.example/b.png)".write(to: b, atomically: true, encoding: .utf8)
        let index = indexURL()
        defer { try? FileManager.default.removeItem(at: index) }
        let scanned = try VaultMediaLibrary(vaultURL: vault, indexURL: index).scan()

        let fs = RecordingFileSystem(evicted: [a, b])
        let cached = VaultMediaLibrary(vaultURL: vault, fileSystem: fs, indexURL: index).cachedSnapshot()
        #expect(fs.reads.isEmpty)
        #expect(cached.items.map(\.id) == scanned.items.map(\.id))
        #expect(cached.items.map(\.mediaURL) == scanned.items.map(\.mediaURL))
        #expect(VaultMediaLibrary(vaultURL: vault, indexURL: indexURL()).cachedSnapshot().items.isEmpty)
    }

    @Test func cachedNotesSearchCurrentLinkMetadata() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        try "# Note\nunicorn\nhttps://example.com/post\n![](.attachments/a.jpg)".write(to: vault.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        let index = indexURL()
        defer { try? FileManager.default.removeItem(at: index) }
        let first = try VaultMediaLibrary(vaultURL: vault, indexURL: index, linkSearchText: { _ in "Old preview" }).scan()
        #expect(VaultMediaLibrary.filtered(first.items, query: "unicorn old").count == 1)

        let fs = RecordingFileSystem()
        let reused = try VaultMediaLibrary(vaultURL: vault, fileSystem: fs, indexURL: index, linkSearchText: { _ in "Fresh préview" }).scan()
        #expect(fs.reads.isEmpty)
        #expect(VaultMediaLibrary.filtered(reused.items, query: "old").isEmpty)
        #expect(VaultMediaLibrary.filtered(reused.items, query: "unicorn fresh preview").count == 1)
    }

    @Test func corruptIndexFallsBackToFullScan() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        try "# A\n![](.attachments/a.jpg)".write(to: vault.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        let index = indexURL()
        defer { try? FileManager.default.removeItem(at: index) }
        try Data("not json".utf8).write(to: index)

        let fs = RecordingFileSystem()
        let result = try VaultMediaLibrary(vaultURL: vault, fileSystem: fs, indexURL: index).scan()
        #expect(fs.reads.count == 1)
        #expect(result.items.count == 1)
        let again = RecordingFileSystem()
        _ = try VaultMediaLibrary(vaultURL: vault, fileSystem: again, indexURL: index).scan()
        #expect(again.reads.isEmpty)
    }

    @Test func thumbnailStoreRoundTripsAndKeysOnFileIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("thumbs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = URL(fileURLWithPath: "/vault/.attachments/a.mp4")
        let key = MediaThumbnailStore.key(forFile: file, modified: Date(timeIntervalSince1970: 100), size: 42)
        MediaThumbnailStore(directoryURL: directory).store(Data([1, 2, 3]), for: key)

        let reopened = MediaThumbnailStore(directoryURL: directory)
        #expect(reopened.data(for: key) == Data([1, 2, 3]))
        #expect(reopened.data(for: MediaThumbnailStore.key(forFile: file, modified: Date(timeIntervalSince1970: 101), size: 42)) == nil)
        #expect(reopened.data(for: MediaThumbnailStore.key(forFile: file, modified: Date(timeIntervalSince1970: 100), size: 43)) == nil)
        #expect(MediaThumbnailStore.key(forRemote: URL(string: "https://cdn.example/a.jpg")!) != key)
    }

    @Test func thumbnailStorePrunesOldestBeyondLimit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("thumbs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MediaThumbnailStore(directoryURL: directory, maxEntries: 5)
        for n in 0..<8 {
            store.store(Data([UInt8(n)]), for: "key-\(n)")
        }
        let remaining = (0..<8).filter { store.data(for: "key-\($0)") != nil }
        #expect(remaining.count <= 5)
        #expect(remaining.contains(7))
    }
}

/// The real file system, recording note reads and download requests; `evicted`
/// notes report "not downloaded" the way iCloud placeholders do.
private final class RecordingFileSystem: VaultFileSystem, @unchecked Sendable {
    private let base = CoordinatedVaultFileSystem()
    private let lock = NSLock()
    private let evicted: Set<URL>
    private var recordedReads: [URL] = []
    private var recordedDownloads: [URL] = []

    init(evicted: [URL] = []) {
        self.evicted = Set(evicted.map(\.standardizedFileURL))
    }

    var reads: [URL] { lock.withLock { recordedReads } }
    var downloadsStarted: [URL] { lock.withLock { recordedDownloads } }

    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func isReadableFile(at url: URL) -> Bool { base.isReadableFile(at: url) }
    func readString(from url: URL) -> String? {
        lock.withLock { recordedReads.append(url) }
        return base.readString(from: url)
    }
    func readData(from url: URL) -> Data? { base.readData(from: url) }
    func readPrefix(from url: URL, maxBytes: Int) -> Data? { base.readPrefix(from: url, maxBytes: maxBytes) }
    func writeString(_ content: String, to url: URL) -> Bool { base.writeString(content, to: url) }
    func writeData(_ data: Data, to url: URL) -> Bool { base.writeData(data, to: url) }
    func delete(at url: URL) -> Bool { base.delete(at: url) }
    func move(from sourceURL: URL, to destinationURL: URL) -> Bool { base.move(from: sourceURL, to: destinationURL) }
    func createDirectory(at url: URL) -> Bool { base.createDirectory(at: url) }
    func isDownloaded(at url: URL) -> Bool { !evicted.contains(url.standardizedFileURL) }
    func startDownloading(at url: URL) {
        lock.withLock { recordedDownloads.append(url) }
    }
}
