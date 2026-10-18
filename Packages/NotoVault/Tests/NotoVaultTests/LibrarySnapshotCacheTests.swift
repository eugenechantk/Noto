import Foundation
import Testing
@testable import NotoVault

/// Test case index — the on-disk Library snapshot (feature noto2-library-cache, SC1–SC2).
/// 1. roundTripsSnapshot — a written snapshot reads back unchanged
/// 2. missingFileReadsNil — no file yet means no cache
/// 3. corruptFileReadsNil — unreadable bytes are ignored, not thrown
/// 4. otherVaultReadsNil — a snapshot saved for another vault path is ignored
/// 5. otherSchemaReadsNil — a snapshot saved under another schema version is ignored
struct LibrarySnapshotCacheTests {
    @Test func roundTripsSnapshot() throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let snapshot = Fixture.snapshot(vault: fixture.vault)
        try fixture.cache.write(snapshot, vaultRootURL: fixture.vault)
        #expect(fixture.cache.read(vaultRootURL: fixture.vault) == snapshot)
    }

    @Test func missingFileReadsNil() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        #expect(fixture.cache.read(vaultRootURL: fixture.vault) == nil)
    }

    @Test func corruptFileReadsNil() throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(at: fixture.cache.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a plist".utf8).write(to: fixture.cache.fileURL)
        #expect(fixture.cache.read(vaultRootURL: fixture.vault) == nil)
    }

    @Test func otherVaultReadsNil() throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        try fixture.cache.write(Fixture.snapshot(vault: fixture.vault), vaultRootURL: fixture.vault)
        let otherVault = fixture.root.appendingPathComponent("OtherVault", isDirectory: true)
        #expect(fixture.cache.read(vaultRootURL: otherVault) == nil)
    }

    @Test func otherSchemaReadsNil() throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let stale = LibrarySnapshotCache.Envelope(
            schemaVersion: LibrarySnapshotCache.schemaVersion + 1,
            vaultPath: LibrarySnapshotCache.key(for: fixture.vault),
            snapshot: Fixture.snapshot(vault: fixture.vault)
        )
        try FileManager.default.createDirectory(at: fixture.cache.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListEncoder().encode(stale).write(to: fixture.cache.fileURL)
        #expect(fixture.cache.read(vaultRootURL: fixture.vault) == nil)
    }
}

/// A temp root holding a vault path and a cache file path. Shared with `LibraryModelTests`.
struct Fixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryCache-" + UUID().uuidString, isDirectory: true)
    var vault: URL { root.appendingPathComponent("Vault", isDirectory: true) }
    var cache: LibrarySnapshotCache { LibrarySnapshotCache(fileURL: root.appendingPathComponent("Caches/library.plist")) }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    static func snapshot(vault: URL, titles: [String] = ["Roadmap", "Groceries"], pinnedTitle: String? = "Roadmap") -> LibrarySnapshot {
        let notes = titles.enumerated().map { index, title in
            let url = vault.appendingPathComponent("Projects/\(title).md")
            return LibraryNote(
                note: VaultNoteRecord(id: VaultDirectoryLoader.stableID(for: url), fileURL: url, title: title, modifiedDate: Date(timeIntervalSince1970: 1_000 + Double(index))),
                folderPath: "Projects",
                preview: "Preview of \(title)",
                isPinned: title == pinnedTitle
            )
        }
        let folder = FolderSummary(id: UUID(), folderURL: vault.appendingPathComponent("Projects", isDirectory: true), name: "Projects", modifiedDate: Date(timeIntervalSince1970: 2_000), itemCount: titles.count)
        return LibrarySnapshot(notes: notes, folders: [folder])
    }
}
