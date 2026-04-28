import Foundation

public enum VaultMarkdown {
    public static func title(from content: String, fallbackTitle: String = "Untitled") -> String {
        let body = stripFrontmatter(content)
        let firstLine = body.prefix { $0 != "\n" }
        var title = String(firstLine).trimmingCharacters(in: .whitespaces)
        if let headingRange = title.range(of: #"^#{1,3}\s*"#, options: .regularExpression) {
            title = String(title[headingRange.upperBound...])
        }
        title = title.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? fallbackTitle : title
    }

    public static func displayTitle(for fileURL: URL, content: String) -> String {
        let resolvedTitle = title(from: content)
        if resolvedTitle == "Untitled" {
            let fallback = fileURL.deletingPathExtension().lastPathComponent
            return fallback.isEmpty ? resolvedTitle : fallback
        }
        return resolvedTitle
    }

    public static func stripFrontmatter(_ content: String) -> String {
        guard content.hasPrefix("---") else { return content }
        let searchRange = content.index(content.startIndex, offsetBy: 3)..<content.endIndex
        guard let closeRange = content.range(of: "\n---", range: searchRange) else { return content }
        let afterFrontmatter = content[closeRange.upperBound...]
        return String(afterFrontmatter.drop { $0 == "\n" })
    }

    public static func idFromFrontmatter(_ content: String) -> UUID? {
        guard content.hasPrefix("---") else { return nil }
        let searchRange = content.index(content.startIndex, offsetBy: 3)..<content.endIndex
        guard let closeRange = content.range(of: "\n---", range: searchRange) else { return nil }
        let frontmatter = String(content[content.startIndex..<closeRange.upperBound])
        for line in frontmatter.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("id:") {
                let value = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                return UUID(uuidString: value)
            }
        }
        return nil
    }

    public static func makeFrontmatter(id: UUID, createdAt: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let now = formatter.string(from: createdAt)
        return """
        ---
        id: \(id.uuidString)
        created: \(now)
        updated: \(now)
        ---

        """
    }

    public static func updateTimestamp(in content: String, date: Date = Date()) -> String {
        guard content.hasPrefix("---") else { return content }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let now = formatter.string(from: date)

        let lines = content.components(separatedBy: "\n")
        var updated = lines
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("updated:") {
                updated[index] = "updated: \(now)"
                break
            }
        }
        return updated.joined(separator: "\n")
    }

    public static func sanitizeFilename(_ name: String, maxLength: Int = 100) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?\"<>|*")
        var sanitized = name.components(separatedBy: illegal).joined()
        sanitized = sanitized.trimmingCharacters(in: .whitespaces)
        if sanitized.count > maxLength {
            sanitized = String(sanitized.prefix(maxLength))
        }
        return sanitized
    }

    public static func isDailyNoteFileStem(_ stem: String) -> Bool {
        stem.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    public static func resolveFileConflict(for filename: String, in directory: URL, fileSystem: VaultFileSystem) -> URL {
        var candidate = directory.appendingPathComponent(filename)
        guard !fileSystem.fileExists(at: candidate) else {
            let stem = candidate.deletingPathExtension().lastPathComponent
            let ext = candidate.pathExtension
            var counter = 2
            while fileSystem.fileExists(at: candidate) {
                let newName = ext.isEmpty ? "\(stem)(\(counter))" : "\(stem)(\(counter)).\(ext)"
                candidate = directory.appendingPathComponent(newName)
                counter += 1
            }
            return candidate
        }
        return candidate
    }

    public static func resolveFolderConflict(named name: String, in directory: URL, fileSystem: VaultFileSystem) -> URL {
        var candidate = directory.appendingPathComponent(name)
        var counter = 2
        while fileSystem.fileExists(at: candidate) {
            candidate = directory.appendingPathComponent("\(name)(\(counter))")
            counter += 1
        }
        return candidate
    }
}
