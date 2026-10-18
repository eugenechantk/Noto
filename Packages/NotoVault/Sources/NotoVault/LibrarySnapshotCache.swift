import Foundation

/// The last Library snapshot, saved to disk so Library can show it at once on the
/// next launch while a fresh scan runs in the background (`LibraryModel`).
/// Reads never throw: a missing, corrupt, other-vault or other-schema file is no cache.
public struct LibrarySnapshotCache: Sendable {
    /// Bump when `LibrarySnapshot`'s stored shape changes, so old files are ignored.
    static let schemaVersion = 1

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `Caches/NotoLibrary/library-snapshot.plist`. iOS may purge it under storage
    /// pressure, which only costs one first-load scan.
    public static var standard: LibrarySnapshotCache? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first.map {
            LibrarySnapshotCache(fileURL: $0.appendingPathComponent("NotoLibrary/library-snapshot.plist"))
        }
    }

    struct Envelope: Codable {
        let schemaVersion: Int
        let vaultPath: String
        let snapshot: LibrarySnapshot
    }

    public func read(vaultRootURL: URL) -> LibrarySnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let envelope = try? PropertyListDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == Self.schemaVersion,
              envelope.vaultPath == Self.key(for: vaultRootURL) else { return nil }
        return envelope.snapshot
    }

    public func write(_ snapshot: LibrarySnapshot, vaultRootURL: URL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let envelope = Envelope(schemaVersion: Self.schemaVersion, vaultPath: Self.key(for: vaultRootURL), snapshot: snapshot)
        try encoder.encode(envelope).write(to: fileURL, options: .atomic)
    }

    /// Note URLs in the snapshot are absolute, so a cache only belongs to the vault path it was saved for.
    static func key(for vaultRootURL: URL) -> String {
        vaultRootURL.standardizedFileURL.path
    }
}
