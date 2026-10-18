import Foundation

/// What the last media scan found, per note, on disk: the note's modified date
/// and size (to tell whether it changed) and the media it referenced. Lets the
/// board render without reading a single note, and a rescan read only notes
/// that changed. A cache, not content: deleting it only costs a full scan.
struct VaultMediaIndex: Codable {
    static let currentVersion = 1

    var version = VaultMediaIndex.currentVersion
    /// Keyed by the note's vault-relative path.
    var notes: [String: Entry] = [:]

    struct Entry: Codable {
        /// `timeIntervalSinceReferenceDate`; compared with a tolerance because
        /// JSON doubles lose the file system's sub-microsecond precision.
        var modified: Double
        var size: Int
        var title: String
        /// Normalized title + path + note text; nil when the note has no media.
        var baseSearchText: String?
        var linkedURLs: [String]
        var items: [Item]

        struct Item: Codable {
            var id: String
            /// Vault-relative path for a local file, absolute URL string otherwise.
            var target: String
            var isLocal: Bool
            var kind: String
            var caption: String
        }

        init(_ parsed: VaultMediaLibrary.ParsedNote, modifiedAt: Date, size: Int, vaultURL: URL) {
            modified = modifiedAt.timeIntervalSinceReferenceDate
            self.size = size
            title = parsed.items.first?.noteTitle ?? ""
            baseSearchText = parsed.baseSearchText
            linkedURLs = parsed.linkedURLs.map(\.absoluteString)
            let prefix = vaultURL.standardizedFileURL.path + "/"
            items = parsed.items.map { item in
                let path = item.mediaURL.standardizedFileURL.path
                let local = item.mediaURL.isFileURL && path.hasPrefix(prefix)
                return Item(id: item.id,
                            target: local ? String(path.dropFirst(prefix.count)) : item.mediaURL.absoluteString,
                            isLocal: local, kind: item.kind.rawValue, caption: item.caption)
            }
        }

        func matches(modifiedAt: Date, size: Int) -> Bool {
            abs(modified - modifiedAt.timeIntervalSinceReferenceDate) < 0.001 && self.size == size
        }

        func mediaItems(noteRelativePath: String, vaultURL: URL,
                        linkSearchText: @Sendable (URL) -> String?) -> [VaultMediaItem] {
            guard !items.isEmpty else { return [] }
            let root = vaultURL.standardizedFileURL
            let noteURL = root.appendingPathComponent(noteRelativePath).standardizedFileURL
            let searchText = VaultMediaLibrary.searchText(
                base: baseSearchText ?? "",
                linkedURLs: linkedURLs.compactMap(URL.init(string:)),
                linkSearchText: linkSearchText
            )
            let modifiedAt = Date(timeIntervalSinceReferenceDate: modified)
            return items.compactMap { item in
                guard let kind = VaultMediaKind(rawValue: item.kind) else { return nil }
                let mediaURL = item.isLocal
                    ? root.appendingPathComponent(item.target).standardizedFileURL
                    : URL(string: item.target)
                guard let mediaURL else { return nil }
                return VaultMediaItem(id: item.id, mediaURL: mediaURL, kind: kind, caption: item.caption,
                                      noteURL: noteURL, noteRelativePath: noteRelativePath, noteTitle: title,
                                      modifiedAt: modifiedAt, noteSearchText: searchText)
            }
        }
    }

    static func load(from url: URL) -> VaultMediaIndex? {
        guard let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(VaultMediaIndex.self, from: data),
              index.version == currentVersion else { return nil }
        return index
    }

    func save(to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
