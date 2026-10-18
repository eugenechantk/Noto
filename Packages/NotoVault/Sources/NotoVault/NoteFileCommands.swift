import Foundation

public enum VaultLibrarySortOrder: String, CaseIterable, Sendable {
    case newest = "Date Modified"
    case oldest = "Oldest First"
    case title = "Title"

    public func sorted(_ notes: [VaultLibraryNote]) -> [VaultLibraryNote] {
        notes.sorted { lhs, rhs in
            switch self {
            case .newest: return lhs.record.modifiedDate > rhs.record.modifiedDate
            case .oldest: return lhs.record.modifiedDate < rhs.record.modifiedDate
            case .title: return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
    }
}

public extension VaultMarkdown {
    /// Changes only the first body line. Frontmatter and all following text stay intact.
    static func renamingTitle(in markdown: String, to title: String) -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).joined(separator: " ")
        guard !title.isEmpty else { return markdown }
        let body = stripFrontmatter(markdown)
        guard !body.isEmpty, let bodyRange = markdown.range(of: body, options: .backwards) else {
            return markdown + (markdown.hasSuffix("\n") || markdown.isEmpty ? "" : "\n") + "# " + title
        }
        let end = markdown[bodyRange.lowerBound...].firstIndex(of: "\n") ?? markdown.endIndex
        var result = markdown
        result.replaceSubrange(bodyRange.lowerBound..<end, with: "# " + title)
        return result
    }
}

public extension NoteRepository {
    /// A duplicate gets a new identity while retaining the source body and custom properties.
    func duplicate(_ note: VaultNoteRecord, content: String? = nil, date: Date = Date()) throws -> VaultNoteRecord {
        guard pathResolver.contains(note.fileURL), let source = content ?? fileSystem.readString(from: note.fileURL) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let id = UUID()
        var markdown = source
        if VaultMarkdown.idFromFrontmatter(markdown) == nil {
            markdown = VaultMarkdown.makeFrontmatter(id: id, createdAt: date) + source
        } else {
            let stamp = ISO8601DateFormatter().string(from: date)
            for (key, value) in [("id", id.uuidString), ("created", stamp), ("modified", stamp), ("updated", stamp)] {
                markdown = NoteFrontmatter.setting(key, to: value, in: markdown)
            }
        }
        let filename = VaultMarkdown.sanitizeFilename(note.title) + " copy.md"
        let url = VaultMarkdown.resolveFileConflict(for: filename, in: note.fileURL.deletingLastPathComponent(), fileSystem: fileSystem)
        guard fileSystem.writeString(markdown, to: url) else { throw CocoaError(.fileWriteUnknown) }
        return VaultNoteRecord(id: id, fileURL: url, title: VaultMarkdown.title(from: markdown), modifiedDate: date)
    }
}
