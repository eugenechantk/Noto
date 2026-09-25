import Foundation
import NotoShareCapture

/// Downloads a post's media into the vault's `.attachments/` folder (the
/// folder `NotoVault.AttachmentStore` uses) under stable names, so a
/// re-delivered job reuses what is already there.
public struct MediaDownloader: Sendable {
    public static let attachmentsFolder = ".attachments"
    static let maxBytes = 250 * 1024 * 1024
    private static let knownExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "heic", "mp4", "mov", "m4v"]

    let vaultURL: URL
    let http: any HTTPFetching

    public init(vaultURL: URL, http: any HTTPFetching = URLSessionFetcher()) {
        self.vaultURL = vaultURL
        self.http = http
    }

    /// `x-2102386784814735508-1.mp4`
    public static func fileName(for post: SocialPost, index: Int, media: SocialMedia) -> String {
        let ext = media.url.pathExtension.lowercased()
        let chosen = knownExtensions.contains(ext) ? (ext == "jpeg" ? "jpg" : ext) : (media.kind == .video ? "mp4" : "jpg")
        return "\(post.platform.rawValue)-\(post.postID)-\(index).\(chosen)"
    }

    /// Vault-relative path for every media URL of the post and its quoted posts.
    public func download(_ post: SocialPost) async throws -> [URL: String] {
        var paths: [URL: String] = [:]
        try FileManager.default.createDirectory(at: vaultURL.appendingPathComponent(Self.attachmentsFolder), withIntermediateDirectories: true)
        for (offset, media) in post.media.enumerated() {
            let relative = "\(Self.attachmentsFolder)/\(Self.fileName(for: post, index: offset + 1, media: media))"
            let destination = vaultURL.appendingPathComponent(relative)
            if let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 {
                paths[media.url] = relative
                continue
            }
            let (data, response) = try await http.fetch(Browser.request(media.url))
            guard (200..<300).contains(response.statusCode), !data.isEmpty else {
                throw SocialPostError.badResponse(status: response.statusCode)
            }
            guard data.count <= Self.maxBytes else { throw SocialPostError.unreadable("media larger than 250 MB") }
            try data.write(to: destination, options: .atomic)
            paths[media.url] = relative
        }
        for quoted in post.quoted {
            paths.merge(try await download(quoted)) { first, _ in first }
        }
        return paths
    }
}

/// The markdown Hermes appends under a capture: the author and text, one
/// image line per media item (the editor renders `![](x.mp4)` as the video's
/// first frame), then each quoted post the same way under "Quoting @author".
/// Plain paragraphs rather than `>` quotes — Noto's editor does not style
/// blockquotes, so `>` would show as literal text.
public enum ShareMediaMarkdown {
    public static func block(for post: SocialPost, paths: [URL: String]) -> String {
        var sections = section(for: post, heading: post.author.map { "**@\($0)**" }, paths: paths)
        for quoted in post.quoted {
            sections += section(for: quoted, heading: "Quoting " + (quoted.author.map { "**@\($0)**" } ?? "a post"), paths: paths)
        }
        return sections.joined(separator: "\n\n")
    }

    /// The first attachment path the block references — its idempotency key.
    public static func firstAttachment(in block: String) -> String? {
        guard let start = block.range(of: "](\(MediaDownloader.attachmentsFolder)/") else { return nil }
        let rest = block[block.index(start.lowerBound, offsetBy: 2)...]
        return rest.firstIndex(of: ")").map { String(rest[..<$0]) }
    }

    private static func section(for post: SocialPost, heading: String?, paths: [URL: String]) -> [String] {
        var parts: [String] = []
        let text = post.text.map(normalized)
        switch (heading, text) {
        case let (heading?, text?): parts.append(heading + "\n" + text)
        case let (heading?, nil): parts.append(heading)
        case let (nil, text?): parts.append(text)
        case (nil, nil): break
        }
        let media = post.media.compactMap { paths[$0.url] }.map { "![](\($0))" }
        if !media.isEmpty { parts.append(media.joined(separator: "\n")) }
        return parts
    }

    /// Collapses runs of blank lines to one so the block stays compact.
    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
    }
}

/// Finds the capture note a job belongs to and appends the media block once.
public struct CaptureNoteAppender: Sendable {
    let vaultURL: URL

    public init(vaultURL: URL) {
        self.vaultURL = vaultURL
    }

    /// The job's `inbox/` path if it exists; otherwise (when `searchVault`) the
    /// most recently modified note that links the shared URL — the capture
    /// after Digest filed it elsewhere.
    public func locate(_ job: ShareMediaJob, searchVault: Bool) -> URL? {
        if CaptureNotePath.isInboxCapturePath(job.notePath) {
            let direct = vaultURL.appendingPathComponent(job.notePath)
            if FileManager.default.fileExists(atPath: direct.path) { return direct }
        }
        guard searchVault else { return nil }
        let needles = Set([job.url.absoluteString, SharedLinkCapture.linkDestination(for: job.url)])
        var best: (url: URL, modified: Date)?
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: vaultURL, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        for case let file as URL in enumerator where file.pathExtension.lowercased() == "md" {
            guard let text = try? String(contentsOf: file, encoding: .utf8),
                  needles.contains(where: { text.contains($0) }) else { continue }
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if best == nil || modified > best!.modified { best = (file, modified) }
        }
        return best?.url
    }

    public enum Result: Equatable {
        case appended
        case alreadyPresent
    }

    /// Appends `block` after the note's content, separated by a blank line.
    /// A note that already references the block's first attachment is left alone.
    public func append(_ block: String, to note: URL) throws -> Result {
        var result = Result.alreadyPresent
        var failure: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: note, options: .forMerging, error: &coordinationError) { url in
            do {
                let existing = try String(contentsOf: url, encoding: .utf8)
                if let key = ShareMediaMarkdown.firstAttachment(in: block), existing.contains(key) { return }
                let trimmed = existing.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
                try (trimmed + "\n\n" + block + "\n").write(to: url, atomically: true, encoding: .utf8)
                result = .appended
            } catch {
                failure = error
            }
        }
        if let error = coordinationError ?? failure { throw error }
        return result
    }
}
