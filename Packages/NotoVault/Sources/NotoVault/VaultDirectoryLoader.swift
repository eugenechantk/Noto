import Foundation

public struct VaultDirectoryLoader: Sendable {
    private let titleResolver: NoteTitleResolver

    public init(titleResolver: NoteTitleResolver = NoteTitleResolver()) {
        self.titleResolver = titleResolver
    }

    public func loadItems(in directoryURL: URL) throws -> [VaultListItem] {
        let children = try FileManager.default.contentsOfDirectory(
            at: directoryURL.standardizedFileURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var folders: [FolderSummary] = []
        var notes: [NoteSummary] = []

        for childURL in children {
            guard let values = try? childURL.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]) else {
                continue
            }
            let modifiedAt = values.contentModificationDate ?? .distantPast
            let normalizedURL = childURL.standardizedFileURL

            if values.isDirectory == true {
                folders.append(FolderSummary(
                    id: Self.stableID(for: normalizedURL),
                    folderURL: normalizedURL,
                    name: normalizedURL.lastPathComponent,
                    modifiedDate: modifiedAt
                ))
            } else if normalizedURL.pathExtension == "md" {
                notes.append(NoteSummary(
                    id: noteID(at: normalizedURL),
                    fileURL: normalizedURL,
                    title: titleResolver.title(forFileAt: normalizedURL),
                    modifiedDate: modifiedAt
                ))
            }
        }

        let sortedFolders = folders.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let sortedNotes = notes.sorted { $0.modifiedDate > $1.modifiedDate }

        return sortedFolders.map(VaultListItem.folder) + sortedNotes.map(VaultListItem.note)
    }

    public static func stableID(for url: URL) -> UUID {
        var hash = FNV1a128()
        hash.update(url.standardizedFileURL.path)
        return hash.uuid
    }

    private func noteID(at url: URL) -> UUID {
        guard let markdown = try? String(contentsOf: url, encoding: .utf8),
              let frontmatterID = frontmatterID(from: markdown) else {
            return Self.stableID(for: url)
        }
        return frontmatterID
    }

    private func frontmatterID(from markdown: String) -> UUID? {
        guard markdown.hasPrefix("---") else { return nil }
        let searchRange = markdown.index(markdown.startIndex, offsetBy: 3)..<markdown.endIndex
        guard let closeRange = markdown.range(of: "\n---", range: searchRange) else { return nil }
        let frontmatter = String(markdown[markdown.startIndex..<closeRange.upperBound])

        for line in frontmatter.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("id:") {
                let value = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                return UUID(uuidString: value)
            }
        }
        return nil
    }
}

private struct FNV1a128 {
    private var high: UInt64 = 0xcbf29ce484222325
    private var low: UInt64 = 0x84222325cbf29ce4

    mutating func update(_ string: String) {
        for byte in string.utf8 {
            high ^= UInt64(byte)
            high &*= 0x100000001b3
            low ^= UInt64(byte)
            low &*= 0x100000001b3
            low ^= high.rotateLeft(13)
        }
    }

    var uuid: UUID {
        var bytes: uuid_t = (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
        bytes.0 = UInt8(truncatingIfNeeded: high >> 56)
        bytes.1 = UInt8(truncatingIfNeeded: high >> 48)
        bytes.2 = UInt8(truncatingIfNeeded: high >> 40)
        bytes.3 = UInt8(truncatingIfNeeded: high >> 32)
        bytes.4 = UInt8(truncatingIfNeeded: high >> 24)
        bytes.5 = UInt8(truncatingIfNeeded: high >> 16)
        bytes.6 = UInt8(truncatingIfNeeded: high >> 8)
        bytes.7 = UInt8(truncatingIfNeeded: high)
        bytes.8 = UInt8(truncatingIfNeeded: low >> 56)
        bytes.9 = UInt8(truncatingIfNeeded: low >> 48)
        bytes.10 = UInt8(truncatingIfNeeded: low >> 40)
        bytes.11 = UInt8(truncatingIfNeeded: low >> 32)
        bytes.12 = UInt8(truncatingIfNeeded: low >> 24)
        bytes.13 = UInt8(truncatingIfNeeded: low >> 16)
        bytes.14 = UInt8(truncatingIfNeeded: low >> 8)
        bytes.15 = UInt8(truncatingIfNeeded: low)
        return UUID(uuid: bytes)
    }
}

private extension UInt64 {
    func rotateLeft(_ shift: Int) -> UInt64 {
        (self << shift) | (self >> (64 - shift))
    }
}
