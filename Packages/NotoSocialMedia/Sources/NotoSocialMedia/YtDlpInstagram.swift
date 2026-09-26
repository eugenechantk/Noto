import Foundation
import NotoShareCapture

/// Second route to an Instagram post, used when the public embed page has no
/// media graph — login-only posts, typically reels set to licensed music.
public protocol InstagramLoginFallback: Sendable {
    func resolve(_ url: URL, shortcode: String) async throws -> SocialPost
}

/// Reads `yt-dlp -J` output for an Instagram post: a single `video` or a
/// `playlist` (carousel) of entries.
///
/// For a video it takes the best **single-file MP4** (Instagram's
/// `video_versions`, H.264 + AAC, plays in AVPlayer). The higher-resolution
/// `dash-*` formats are split video/audio — VP9 — and would need ffmpeg to
/// merge and still might not play on iPhone. With no single-file MP4 the
/// poster image is saved instead, so the capture still gets something.
public enum YtDlpInstagramParser {
    public static func parse(_ data: Data, shortcode: String) throws -> SocialPost {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw SocialPostError.unreadable("yt-dlp returned no metadata")
        }
        let entries = (root["entries"] as? [[String: Any]]) ?? []
        let nodes = entries.isEmpty ? [root] : entries
        let media = nodes.compactMap(mediaItem(from:))
        guard !media.isEmpty else { throw SocialPostError.unreadable("yt-dlp found no media") }

        let author = ([root] + entries).lazy.compactMap { node in
            ["channel", "uploader_id", "uploader"].lazy.compactMap { (node[$0] as? String).flatMap(nonEmpty) }.first
        }.first
        let text = ([root] + entries).lazy.compactMap { ($0["description"] as? String).flatMap(nonEmpty) }.first
        return SocialPost(platform: .instagram, postID: shortcode, author: author, text: text, media: media)
    }

    static func mediaItem(from node: [String: Any]) -> SocialMedia? {
        let formats = (node["formats"] as? [[String: Any]]) ?? []
        let progressive = formats.filter(isSingleFileMP4)
        if let best = progressive.max(by: { area($0) < area($1) }),
           let raw = best["url"] as? String, let url = URL(string: raw) {
            return SocialMedia(kind: .video, url: url)
        }
        if formats.isEmpty, isSingleFileMP4(node), let raw = node["url"] as? String, let url = URL(string: raw) {
            return SocialMedia(kind: .video, url: url)
        }
        if let raw = (node["thumbnail"] as? String) ?? largestThumbnail(in: node), let url = URL(string: raw) {
            return SocialMedia(kind: .image, url: url)
        }
        return nil
    }

    private static func isSingleFileMP4(_ format: [String: Any]) -> Bool {
        guard (format["ext"] as? String) == "mp4",
              let raw = format["url"] as? String, URL(string: raw) != nil else { return false }
        if let id = format["format_id"] as? String, id.hasPrefix("dash-") { return false }
        // yt-dlp marks a missing stream as "none"; unknown codecs (nil) are the combined files.
        if (format["vcodec"] as? String) == "none" || (format["acodec"] as? String) == "none" { return false }
        return true
    }

    private static func area(_ format: [String: Any]) -> Int {
        ((format["width"] as? Int) ?? 0) * ((format["height"] as? Int) ?? 0)
    }

    private static func largestThumbnail(in node: [String: Any]) -> String? {
        let thumbnails = (node["thumbnails"] as? [[String: Any]]) ?? []
        return thumbnails.max(by: { area($0) < area($1) })?["url"] as? String
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Runs `yt-dlp` with the user's Instagram login read **live** from a browser
/// profile (`--cookies-from-browser`) — no cookie file is stored, so the login
/// stays as fresh as the browser's own session.
public struct YtDlpRunner: Sendable {
    public let executable: URL
    public let cookiesBrowser: String
    public var timeout: TimeInterval

    public init(executable: URL, cookiesBrowser: String, timeout: TimeInterval = 120) {
        self.executable = executable
        self.cookiesBrowser = cookiesBrowser
        self.timeout = timeout
    }

    func arguments(for url: URL) -> [String] {
        ["--cookies-from-browser", cookiesBrowser, "-J", "--no-warnings", url.absoluteString]
    }

    #if os(macOS)
    /// `yt-dlp -J` output. A failed run is `loginFetchFailed` — transient, so
    /// the queue retries it (the browser session may just need a refresh).
    public func metadata(for url: URL) async throws -> Data {
        let executable = executable
        let arguments = arguments(for: url)
        let timeout = timeout
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                let output = Pipe()
                let errors = Pipe()
                process.standardOutput = output
                process.standardError = errors
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: SocialPostError.loginFetchFailed("could not start yt-dlp: \(error.localizedDescription)"))
                    return
                }
                let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

                // Drain stderr concurrently so a chatty run can't block on a full pipe.
                var errorData = Data()
                let drained = DispatchSemaphore(value: 0)
                DispatchQueue.global(qos: .utility).async {
                    errorData = errors.fileHandleForReading.readDataToEndOfFile()
                    drained.signal()
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                drained.wait()
                killer.cancel()

                if process.terminationStatus == 0, !data.isEmpty {
                    continuation.resume(returning: data)
                } else {
                    let message = String(decoding: errorData, as: UTF8.self)
                        .split(separator: "\n").last.map(String.init) ?? "exit \(process.terminationStatus)"
                    continuation.resume(throwing: SocialPostError.loginFetchFailed(message))
                }
            }
        }
    }
    #endif
}

#if os(macOS)
/// The Mac-side login fallback: `yt-dlp` with the browser's live cookies.
public struct YtDlpInstagramFallback: InstagramLoginFallback {
    let runner: YtDlpRunner

    public init(runner: YtDlpRunner) {
        self.runner = runner
    }

    public func resolve(_ url: URL, shortcode: String) async throws -> SocialPost {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        let data = try await runner.metadata(for: components?.url ?? url)
        return try YtDlpInstagramParser.parse(data, shortcode: shortcode)
    }
}
#endif
