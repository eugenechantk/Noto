import Foundation

/// A read-only projection for library lists, search palettes and inspectors.
/// Identity stays the frontmatter UUID; filenames remain freely renameable.
public struct VaultLibraryNote: Identifiable, Equatable, Sendable {
    public let record: VaultNoteRecord
    public let relativePath: String
    public let content: String
    public let isAvailable: Bool
    public var id: UUID { record.id }
    public var title: String { record.title }
    public var fileURL: URL { record.fileURL }
    public var preview: String { Self.preview(of: content) }
    public var isPinned: Bool { NoteFrontmatter.value(for: "pinned", in: content)?.lowercased() == "true" }
    public var snoozedUntil: Date? { NoteFrontmatter.value(for: "snoozed_until", in: content).flatMap(NotePropertyClassifier.date) }
    public var isInbox: Bool { relativePath.lowercased().hasPrefix("inbox/") }
    public var isDaily: Bool { relativePath.hasPrefix("Daily Notes/") }
    public func dailyDate(calendar: Calendar = .current) -> Date? {
        guard isDaily else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        return formatter.date(from: fileURL.deletingPathExtension().lastPathComponent)
    }
    public func isDaily(on date: Date, calendar: Calendar = .current) -> Bool {
        dailyDate(calendar: calendar).map { calendar.isDate($0, inSameDayAs: date) } ?? false
    }
    public static func mondayWeekStart(containing date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        let daysSinceMonday = (calendar.component(.weekday, from: date) + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: start) ?? start
    }
    public var breadcrumb: String { relativePath.split(separator: "/").dropLast().joined(separator: " › ") }

    public func snippet(matching query: String) -> String {
        let markdown = VaultMarkdown.stripFrontmatter(content)
            .replacingOccurrences(of: #"\A\s*#\s+[^\n]*(?:\n|$)"#, with: "", options: .regularExpression)
        let body = Self.plainTextSnippet(from: markdown)
        let terms = [query] + query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let match = terms.filter({ !$0.isEmpty }).compactMap({ body.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) }).first else { return preview }
        let before = min(70, body.distance(from: body.startIndex, to: match.lowerBound))
        let start = body.index(match.lowerBound, offsetBy: -before)
        let end = body.index(match.upperBound, offsetBy: 110, limitedBy: body.endIndex) ?? body.endIndex
        let text = body[start..<end].split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (start > body.startIndex ? "…" : "") + text + (end < body.endIndex ? "…" : "")
    }

    public static func plainTextSnippet(from markdown: String) -> String {
        var text = markdown
        let wikiLinks = try! NSRegularExpression(pattern: #"\[\[([^\]|]+)(?:\|([^\]]+))?\]\]"#)
        let original = text as NSString
        for match in wikiLinks.matches(in: text, range: NSRange(location: 0, length: original.length)).reversed() {
            let alias = match.range(at: 2)
            let label = original.substring(with: alias.location == NSNotFound ? match.range(at: 1) : alias)
            if let range = Range(match.range, in: text) { text.replaceSubrange(range, with: label) }
        }
        for mark in ["**", "__", "~~", "`"] { text = text.replacingOccurrences(of: mark, with: "") }
        for (pattern, replacement) in [
            (#"(?m)^#{1,6}\s+"#, ""),
            (#"(?m)^[\t ]*(?:[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)"#, ""),
            (#"!?\[([^\]]+)\]\([^)]+\)"#, "$1"),
            (#"\*([^*]+)\*"#, "$1")
        ] { text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression) }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public static func preview(of markdown: String) -> String {
        var lines = VaultMarkdown.stripFrontmatter(markdown).components(separatedBy: .newlines)
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeFirst() }
        if !lines.isEmpty { lines.removeFirst() }
        let body = lines.filter { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            let level = text.prefix(while: { $0 == "#" }).count
            return !(1...6).contains(level) || text.dropFirst(level).first != " "
        }.map { line in
            var text = line.trimmingCharacters(in: .whitespaces)
            for prefix in ["- [ ] ", "- [x] ", "- [X] ", "- ", "* "] where text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)); break }
            text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
            return text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        }.joined(separator: " ")
        return String(body.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(240))
    }

    public struct Heading: Identifiable, Equatable, Sendable {
        public let line: Int
        public let level: Int
        public let title: String
        public var id: Int { line }
    }

    public static func outline(of markdown: String) -> [Heading] {
        var fence: String?
        return VaultMarkdown.stripFrontmatter(markdown).components(separatedBy: .newlines).enumerated().compactMap { line, raw in
            let text = raw.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("```") || text.hasPrefix("~~~") {
                let marker = String(text.prefix(3))
                if fence == marker { fence = nil } else if fence == nil { fence = marker }
                return nil
            }
            guard fence == nil else { return nil }
            let level = text.prefix(while: { $0 == "#" }).count
            guard (1...6).contains(level), text.dropFirst(level).first == " " else { return nil }
            return Heading(line: line, level: level, title: String(text.dropFirst(level)).trimmingCharacters(in: .whitespaces))
        }
    }

    public static func dateSection(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)), date >= weekAgo { return "Previous 7 Days" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: now) ? "MMMM" : "MMMM yyyy"
        return formatter.string(from: date)
    }
}

public struct VaultLibrarySnapshot: Sendable {
    public let notes: [VaultLibraryNote]
    public let folders: [SidebarTreeNode]

    public static func load(vaultURL: URL, fileSystem: any VaultFileSystem = CoordinatedVaultFileSystem()) throws -> Self {
        let rows = try SidebarTreeLoader(directoryLoader: VaultDirectoryLoader(noteMetadataStrategy: .fileOnly)).loadRows(rootURL: vaultURL)
        let resolver = NoteTitleResolver()
        var notes: [VaultLibraryNote] = []
        var folders: [SidebarTreeNode] = []
        let root = vaultURL.standardizedFileURL.path + "/"
        for row in rows {
            if case .folder = row.kind { folders.append(row); continue }
            // A bounded prefix keeps list scans from loading large note bodies.
            let prefix = fileSystem.readPrefix(from: row.url, maxBytes: 64 * 1024)
            let content = prefix.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let record = VaultNoteRecord(id: VaultMarkdown.idFromFrontmatter(content) ?? row.noteID ?? VaultDirectoryLoader.stableID(for: row.url), fileURL: row.url,
                title: resolver.title(from: content, fallbackTitle: row.name), modifiedDate: row.modifiedAt)
            notes.append(VaultLibraryNote(record: record, relativePath: String(row.url.path.dropFirst(root.count)), content: content, isAvailable: prefix != nil))
        }
        return Self(notes: notes.sorted { $0.record.modifiedDate > $1.record.modifiedDate }, folders: folders)
    }

    public func notes(in folder: URL, includingDescendants: Bool = false) -> [VaultLibraryNote] {
        notes.filter {
            includingDescendants ? $0.fileURL.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/")
                : $0.fileURL.deletingLastPathComponent().standardizedFileURL.path == folder.standardizedFileURL.path
        }
    }
    public func noteCount(in folder: URL) -> Int { notes.filter { $0.fileURL.path.hasPrefix(folder.standardizedFileURL.path + "/") }.count }

    public func matching(_ query: String) -> [VaultLibraryNote] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return notes }
        return notes.filter { note in words.allSatisfy { note.title.localizedCaseInsensitiveContains($0) || note.content.localizedCaseInsensitiveContains($0) } }
            .sorted { lhs, rhs in
                let l = lhs.title.localizedCaseInsensitiveContains(query)
                let r = rhs.title.localizedCaseInsensitiveContains(query)
                return l == r ? lhs.record.modifiedDate > rhs.record.modifiedDate : l
            }
    }

    public func backlinks(to target: VaultLibraryNote) -> [VaultLibraryNote] {
        let pattern = try! NSRegularExpression(pattern: #"\[\[([^\]|]+)(?:\|[^\]]*)?\]\]"#)
        let targets = Set([target.title, target.relativePath, String(target.relativePath.dropLast(3)), target.fileURL.deletingPathExtension().lastPathComponent, target.id.uuidString].map { $0.lowercased() })
        return notes.filter { source in
            guard source.id != target.id else { return false }
            let body = VaultMarkdown.stripFrontmatter(source.content) as NSString
            return pattern.matches(in: body as String, range: NSRange(location: 0, length: body.length)).contains { match in
                let link = body.substring(with: match.range(at: 1)).split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
                return targets.contains(link.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            }
        }
    }
}
