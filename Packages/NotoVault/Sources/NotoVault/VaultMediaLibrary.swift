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
    private let linkSearchText: @Sendable (URL) -> String?

    public init(vaultURL: URL, fileSystem: any VaultFileSystem = CoordinatedVaultFileSystem(),
                linkSearchText: @escaping @Sendable (URL) -> String? = { _ in nil }) {
        self.vaultURL = vaultURL.standardizedFileURL
        self.fileSystem = fileSystem
        self.linkSearchText = linkSearchText
    }

    public func scan() throws -> VaultMediaSnapshot {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
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
        for case let url as URL in files {
            try Task.checkCancellation()
            guard url.pathExtension.lowercased() == "md" else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isSymbolicLink != true, values?.isRegularFile == true else { continue }
            // Coordinated reads are authoritative; iCloud metadata can be stale.
            guard let markdown = fileSystem.readString(from: url) else {
                unavailable += 1
                fileSystem.startDownloading(at: url)
                continue
            }
            result += Self.items(in: markdown, noteURL: url, vaultURL: vaultURL,
                                 modifiedAt: values?.contentModificationDate ?? .distantPast,
                                 linkSearchText: linkSearchText)
        }
        if let enumerationError { throw enumerationError }
        result.sort {
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            if $0.noteRelativePath != $1.noteRelativePath { return $0.noteRelativePath < $1.noteRelativePath }
            return $0.id < $1.id
        }
        return VaultMediaSnapshot(items: result, unavailableNoteCount: unavailable)
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

    private static let links = try! NSRegularExpression(
        pattern: #"(?<![\\!])(!?)\[([^\]]*)\]\((<[^>]+>|(?:[^\s()]+|\([^)]*\))+)(?:\s+["'][^"']*["'])?\)"#
    )
    private static let inlineCode = try! NSRegularExpression(pattern: #"(`+).*?\1"#)
    private static let webLinks = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    public static func items(in markdown: String, noteURL: URL, vaultURL: URL, modifiedAt: Date = .distantPast,
                             linkSearchText: @Sendable (URL) -> String? = { _ in nil }) -> [VaultMediaItem] {
        let root = vaultURL.standardizedFileURL
        let prefix = root.path + "/"
        guard noteURL.standardizedFileURL.path.hasPrefix(prefix) else { return [] }
        let relative = String(noteURL.standardizedFileURL.path.dropFirst(prefix.count))
        let rawTitle = VaultMarkdown.displayTitle(for: noteURL, content: markdown)
        // Share-sheet notes often start with `[post title](url)`. Captions are
        // plain text so a nested link cannot steal the card's source-note tap.
        let attributedTitle = try? AttributedString(markdown: rawTitle, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        let title = attributedTitle.map { String($0.characters) } ?? rawTitle
        let identity = VaultMarkdown.idFromFrontmatter(markdown)?.uuidString ?? relative
        var sharedSearchText: String?
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
                let noteSearchText = sharedSearchText ?? normalized(
                    ([title, relative, markdown] + linkedWebURLs(in: markdown).compactMap(linkSearchText)).joined(separator: "\n")
                )
                sharedSearchText = noteSearchText
                result.append(VaultMediaItem(id: identity + "|" + url.absoluteString, mediaURL: url, kind: kind,
                                            caption: String(line[captionRange]), noteURL: noteURL,
                                            noteRelativePath: relative, noteTitle: title, modifiedAt: modifiedAt,
                                            noteSearchText: noteSearchText))
            }
        }
        return result
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
