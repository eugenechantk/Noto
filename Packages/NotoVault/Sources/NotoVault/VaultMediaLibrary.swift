import Foundation

public enum VaultMediaKind: String, CaseIterable, Sendable {
    case image, video, audio, pdf

    public static func kind(for url: URL, isImageSyntax: Bool) -> Self? {
        switch url.pathExtension.lowercased() {
        case "mp4", "mov", "m4v", "webm": .video
        case "mp3", "m4a", "wav", "aac", "aiff", "ogg", "flac": .audio
        case "pdf": .pdf
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tif", "tiff", "avif", "svg", "bmp": .image
        default: isImageSyntax ? .image : nil
        }
    }
}

public struct VaultMediaItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let mediaURL: URL
    public let kind: VaultMediaKind
    public let caption: String
    public let noteURL: URL
    public let noteRelativePath: String
    public let noteTitle: String
    public let modifiedAt: Date
    /// One normalized, copy-on-write string shared by all media in the note.
    let noteSearchText: String
}

public struct VaultMediaSnapshot: Sendable {
    public let items: [VaultMediaItem]
    public let unavailableNoteCount: Int
}

/// Read-only, on-demand projection of markdown references, never a second
/// content store. Local targets follow the editor's vault-relative convention.
public struct VaultMediaLibrary: Sendable {
    public let vaultURL: URL
    private let fileSystem: any VaultFileSystem
    /// Where the last scan is remembered (see `VaultMediaIndex`); nil scans everything every time.
    private let indexURL: URL?
    private let linkSearchText: @Sendable (URL) -> String?

    public init(vaultURL: URL, fileSystem: any VaultFileSystem = CoordinatedVaultFileSystem(),
                indexURL: URL? = nil,
                linkSearchText: @escaping @Sendable (URL) -> String? = { _ in nil }) {
        self.vaultURL = vaultURL.standardizedFileURL
        self.fileSystem = fileSystem
        self.indexURL = indexURL
        self.linkSearchText = linkSearchText
    }

    /// The last scan's media, straight from the index — no enumeration, no note
    /// reads — so the board can render before `scan()` refreshes it.
    public func cachedSnapshot() -> VaultMediaSnapshot {
        guard let indexURL, let index = VaultMediaIndex.load(from: indexURL) else {
            return VaultMediaSnapshot(items: [], unavailableNoteCount: 0)
        }
        let items = index.notes.flatMap { relative, entry in
            entry.mediaItems(noteRelativePath: relative, vaultURL: vaultURL, linkSearchText: linkSearchText)
        }
        return VaultMediaSnapshot(items: Self.sorted(items), unavailableNoteCount: 0)
    }

    /// Finds media across every note. With an index, a note whose modified date
    /// and size are unchanged is not read again. A note iCloud has evicted is
    /// never read (a coordinated read would block until it downloads): its
    /// download starts and its last known media stand in until it arrives.
    public func scan() throws -> VaultMediaSnapshot {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]
        let previous = indexURL.flatMap(VaultMediaIndex.load(from:)) ?? VaultMediaIndex()
        var next = VaultMediaIndex()
        // Surface an inaccessible root rather than misreporting an empty library.
        _ = try FileManager.default.contentsOfDirectory(at: vaultURL, includingPropertiesForKeys: nil)
        var enumerationError: Error?
        guard let files = FileManager.default.enumerator(
            at: vaultURL, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, error in enumerationError = error; return true }
        ) else { throw CocoaError(.fileReadUnknown) }
        var result: [VaultMediaItem] = []
        var unavailable = 0
        let prefix = vaultURL.path + "/"
        var toRead: [PendingRead] = []
        for case let url as URL in files {
            try Task.checkCancellation()
            guard url.pathExtension.lowercased() == "md" else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isSymbolicLink != true, values?.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { continue }
            let relative = String(path.dropFirst(prefix.count))
            let modifiedAt = values?.contentModificationDate ?? .distantPast
            let size = values?.fileSize ?? -1
            let known = previous.notes[relative]

            if let known, known.matches(modifiedAt: modifiedAt, size: size) {
                next.notes[relative] = known
                result += known.mediaItems(noteRelativePath: relative, vaultURL: vaultURL, linkSearchText: linkSearchText)
                continue
            }
            guard fileSystem.isDownloaded(at: url) else {
                fileSystem.startDownloading(at: url)
                if let known {
                    next.notes[relative] = known
                    result += known.mediaItems(noteRelativePath: relative, vaultURL: vaultURL, linkSearchText: linkSearchText)
                } else {
                    unavailable += 1
                }
                continue
            }
            toRead.append(PendingRead(url: url, relative: relative, modifiedAt: modifiedAt, size: size))
        }
        if let enumerationError { throw enumerationError }

        // Each coordinated read costs ~20 ms of coordination round trip, mostly
        // waiting, so changed notes are read in parallel (a first scan of
        // ~1,200 notes took 24 s one at a time).
        let parsedNotes = readConcurrently(toRead)
        try Task.checkCancellation()
        for (pending, parsed) in zip(toRead, parsedNotes) {
            guard let parsed else {
                unavailable += 1
                fileSystem.startDownloading(at: pending.url)
                continue
            }
            next.notes[pending.relative] = VaultMediaIndex.Entry(parsed, modifiedAt: pending.modifiedAt, size: pending.size, vaultURL: vaultURL)
            result += parsed.items
        }
        if let indexURL { next.save(to: indexURL) }
        return VaultMediaSnapshot(items: Self.sorted(result), unavailableNoteCount: unavailable)
    }

    private struct PendingRead {
        let url: URL
        let relative: String
        let modifiedAt: Date
        let size: Int
    }

    /// Reads and parses notes on several threads; nil for a note that could not be read.
    private func readConcurrently(_ notes: [PendingRead]) -> [ParsedNote?] {
        guard !notes.isEmpty else { return [] }
        var results = [ParsedNote?](repeating: nil, count: notes.count)
        let lock = NSLock()
        fileSystem.batchingReads(of: notes.map(\.url)) {
            // Worker threads are outside the calling task, so a cancelled scan
            // finishes this batch; the caller checks cancellation right after.
            DispatchQueue.concurrentPerform(iterations: notes.count) { index in
                let note = notes[index]
                guard let markdown = fileSystem.readString(from: note.url) else { return }
                let parsed = Self.parse(markdown, noteURL: note.url, vaultURL: vaultURL, modifiedAt: note.modifiedAt,
                                        linkSearchText: linkSearchText)
                lock.lock()
                results[index] = parsed
                lock.unlock()
            }
        }
        return results
    }

    static func sorted(_ items: [VaultMediaItem]) -> [VaultMediaItem] {
        items.sorted {
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            if $0.noteRelativePath != $1.noteRelativePath { return $0.noteRelativePath < $1.noteRelativePath }
            return $0.id < $1.id
        }
    }

    public static func filtered(_ items: [VaultMediaItem], query: String, kind: VaultMediaKind? = nil) -> [VaultMediaItem] {
        let terms = normalized(query).split(whereSeparator: \.isWhitespace).map(String.init)
        return items.filter { item in
            guard kind == nil || item.kind == kind else { return false }
            guard !terms.isEmpty else { return true }
            let mediaText = normalized(item.caption + " " + item.mediaURL.lastPathComponent)
            return terms.allSatisfy { item.noteSearchText.contains($0) || mediaText.contains($0) }
        }
    }

    // The destination alternates single characters with one `(…)` group — never
    // a repeat inside a repeat. `(?:[^\s()]+|…)+` backtracked exponentially on a
    // destination containing spaces (a real Readwise capture hung the scan).
    private static let links = try! NSRegularExpression(
        pattern: #"(?<![\\!])(!?)\[([^\]]*)\]\((<[^>]+>|(?:[^\s()]|\([^)]*\))+)(?:\s+["'][^"']*["'])?\)"#
    )
    private static let inlineCode = try! NSRegularExpression(pattern: #"(`+).*?\1"#)
    private static let webLinks = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    public static func items(in markdown: String, noteURL: URL, vaultURL: URL, modifiedAt: Date = .distantPast,
                             linkSearchText: @Sendable (URL) -> String? = { _ in nil }) -> [VaultMediaItem] {
        parse(markdown, noteURL: noteURL, vaultURL: vaultURL, modifiedAt: modifiedAt, linkSearchText: linkSearchText).items
    }

    /// One note's media plus what the index keeps to rebuild them without the
    /// note: the search text of the note itself, and the web links whose
    /// preview metadata joins the search text fresh on every scan.
    struct ParsedNote {
        var items: [VaultMediaItem]
        var baseSearchText: String?
        var linkedURLs: [URL]
    }

    static func parse(_ markdown: String, noteURL: URL, vaultURL: URL, modifiedAt: Date,
                      linkSearchText: @Sendable (URL) -> String?) -> ParsedNote {
        let root = vaultURL.standardizedFileURL
        let prefix = root.path + "/"
        guard noteURL.standardizedFileURL.path.hasPrefix(prefix) else { return ParsedNote(items: [], baseSearchText: nil, linkedURLs: []) }
        let relative = String(noteURL.standardizedFileURL.path.dropFirst(prefix.count))
        let rawTitle = VaultMarkdown.displayTitle(for: noteURL, content: markdown)
        // Share-sheet notes often start with `[post title](url)`. Captions are
        // plain text so a nested link cannot steal the card's source-note tap.
        let attributedTitle = try? AttributedString(markdown: rawTitle, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        let title = attributedTitle.map { String($0.characters) } ?? rawTitle
        let identity = VaultMarkdown.idFromFrontmatter(markdown)?.uuidString ?? relative
        var sharedSearchText: String?
        var baseSearchText: String?
        var linkedURLs: [URL] = []
        var seen = Set<URL>()
        var result: [VaultMediaItem] = []
        var fence: (character: Character, count: Int)?
        for rawLine in VaultMarkdown.stripFrontmatter(markdown).components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if let first = trimmed.first, first == "`" || first == "~" {
                let count = trimmed.prefix(while: { $0 == first }).count
                if count >= 3 {
                    if let active = fence {
                        if first == active.character && count >= active.count { fence = nil }
                    } else { fence = (first, count) }
                    continue
                }
            }
            guard fence == nil, !rawLine.hasPrefix("    "), !rawLine.hasPrefix("\t") else { continue }
            let line = inlineCode.stringByReplacingMatches(in: rawLine, range: NSRange(rawLine.startIndex..., in: rawLine), withTemplate: "")
            for match in links.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                guard let syntaxRange = Range(match.range(at: 1), in: line),
                      let captionRange = Range(match.range(at: 2), in: line),
                      let targetRange = Range(match.range(at: 3), in: line) else { continue }
                let target = String(line[targetRange]).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
                guard let url = resolve(target, root: root),
                      let kind = VaultMediaKind.kind(for: url, isImageSyntax: !line[syntaxRange].isEmpty),
                      seen.insert(url).inserted else { continue }
                // Normalize once for a note containing media. Notes with no
                // media need no cache reads; each keystroke reuses this text.
                if sharedSearchText == nil {
                    let base = normalized([title, relative, markdown].joined(separator: "\n"))
                    linkedURLs = linkedWebURLs(in: markdown)
                    baseSearchText = base
                    sharedSearchText = searchText(base: base, linkedURLs: linkedURLs, linkSearchText: linkSearchText)
                }
                let noteSearchText = sharedSearchText ?? ""
                result.append(VaultMediaItem(id: identity + "|" + url.absoluteString, mediaURL: url, kind: kind,
                                            caption: String(line[captionRange]), noteURL: noteURL,
                                            noteRelativePath: relative, noteTitle: title, modifiedAt: modifiedAt,
                                            noteSearchText: noteSearchText))
            }
        }
        return ParsedNote(items: result, baseSearchText: baseSearchText, linkedURLs: linkedURLs)
    }

    /// The note's own text plus the current preview metadata of its links —
    /// the same string as normalizing everything joined, since folding is per character.
    static func searchText(base: String, linkedURLs: [URL], linkSearchText: @Sendable (URL) -> String?) -> String {
        let linked = linkedURLs.compactMap(linkSearchText)
        guard !linked.isEmpty else { return base }
        return base + "\n" + normalized(linked.joined(separator: "\n"))
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func linkedWebURLs(in markdown: String) -> [URL] {
        let range = NSRange(markdown.startIndex..., in: markdown)
        var urls = Set<URL>()
        // Parse markdown destinations explicitly; punctuation next to a link
        // must not change the URL used as the preview cache key.
        for match in links.matches(in: markdown, range: range) {
            if let destination = Range(match.range(at: 3), in: markdown),
               let url = URL(string: String(markdown[destination]).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))),
               ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
                urls.insert(url)
            }
        }
        for match in webLinks.matches(in: markdown, range: range) {
            if let url = match.url, ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
                urls.insert(url)
            }
        }
        return urls.sorted { $0.absoluteString < $1.absoluteString }
    }

    private static func resolve(_ target: String, root: URL) -> URL? {
        if let url = URL(string: target), let scheme = url.scheme {
            guard ["https", "http"].contains(scheme.lowercased()), url.host != nil else { return nil }
            return url
        }
        let decoded = target.removingPercentEncoding ?? target
        guard !decoded.isEmpty, !decoded.hasPrefix("/"), !decoded.contains("\\"),
              !decoded.split(separator: "/").contains("..") else { return nil }
        let url = root.appendingPathComponent(decoded).standardizedFileURL
        let resolvedRoot = root.resolvingSymlinksInPath().path + "/"
        var componentURL = root
        for component in decoded.split(separator: "/") {
            componentURL.appendPathComponent(String(component))
            guard componentURL.resolvingSymlinksInPath().path.hasPrefix(resolvedRoot) else { return nil }
        }
        return url
    }
}
