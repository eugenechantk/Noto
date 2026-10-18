import CryptoKit
import Foundation

/// The Cloudflare copy of the vault's `.attachments/` — R2 behind the
/// `noto-media` Worker (`web/noto-media-worker`), filled by Hermes on the Mac.
/// Reads need a link signed with a key shipped in the app (Info.plist
/// `NotoMediaMirrorURL` / `NotoMediaMirrorKey`, the key from the gitignored
/// `Config/LocalSecrets.xcconfig`). An app without the keys has no mirror.
struct MediaMirror: Equatable, Sendable {
    let baseURL: URL
    let signingKey: String

    static let shared: MediaMirror? = MediaMirror(infoDictionary: Bundle.main.infoDictionary)

    init(baseURL: URL, signingKey: String) {
        self.baseURL = baseURL
        self.signingKey = signingKey
    }

    init?(infoDictionary: [String: Any]?) {
        guard let raw = infoDictionary?["NotoMediaMirrorURL"] as? String, let url = URL(string: raw),
              let key = infoDictionary?["NotoMediaMirrorKey"] as? String,
              !key.isEmpty, !key.contains("$(") else { return nil }
        self.init(baseURL: url, signingKey: key)
    }

    /// `.attachments/<file>` for a file inside a vault's `.attachments` folder —
    /// the mirror's key. Nothing else is mirrored.
    static func key(for fileURL: URL) -> String? {
        guard fileURL.isFileURL else { return nil }
        let parts = fileURL.standardizedFileURL.pathComponents
        guard let index = parts.lastIndex(of: ".attachments"), index + 1 < parts.count else { return nil }
        return ([".attachments"] + parts[(index + 1)...]).joined(separator: "/")
    }

    /// base64url(HMAC-SHA256(secret, "<key>\n<expires>")) — what the Worker checks.
    static func signature(key: String, expires: Int, secret: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data("\(key)\n\(expires)".utf8), using: SymmetricKey(data: Data(secret.utf8)))
        return Data(mac).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The end of tomorrow (UTC): the same link all day, so the URL cache hits,
    /// and never less than a day left.
    static func expiry(now: Date) -> Int {
        (Int(now.timeIntervalSince1970) / 86_400 + 2) * 86_400
    }

    func signedURL(forKey key: String, now: Date = Date()) -> URL {
        var url = baseURL
        for component in key.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        let expires = Self.expiry(now: now)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "exp", value: String(expires)),
            URLQueryItem(name: "sig", value: Self.signature(key: key, expires: expires, secret: signingKey)),
        ]
        return components?.url ?? url
    }

    func url(for fileURL: URL, now: Date = Date()) -> URL? {
        Self.key(for: fileURL).map { signedURL(forKey: $0, now: now) }
    }

    /// `remote/<first 32 hex of SHA-256(URL)>` — where Hermes backs up a web
    /// image a note embeds (`RemoteMediaMirror.key` on the Mac).
    static func remoteKey(for webURL: URL) -> String {
        let digest = SHA256.hash(data: Data(webURL.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return "remote/" + digest.prefix(32)
    }

    /// The small JPEG Hermes uploads next to each video.
    func posterURL(for fileURL: URL, now: Date = Date()) -> URL? {
        Self.key(for: fileURL).map { signedURL(forKey: $0 + ".poster.jpg", now: now) }
    }
}

/// Where to read media from, in order: the mirror (R2) first, then the device —
/// or, for a web image, the mirror's backup first, then the original site
/// (Eugene, 2026-09-26). A request the mirror cannot answer (not uploaded yet,
/// offline) falls through to the next source.
enum MediaSource {
    struct VideoSource: Equatable {
        /// What the player loads first.
        let primary: URL
        /// Played instead if `primary` fails — the downloaded vault file.
        let fallback: URL?
    }

    /// Exists and is downloaded — `isDownloaded` alone reports true for a missing file.
    static func isLocallyAvailable(_ fileURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: fileURL.path) && CoordinatedFileManager.isDownloaded(at: fileURL)
    }

    /// The mirror copy to try first: a vault attachment (its poster for a video
    /// thumbnail) or a web image's backup. Nil when there is nothing to try.
    static func mirrorURL(for url: URL, poster: Bool = false, mirror: MediaMirror? = MediaMirror.shared) -> URL? {
        guard let mirror else { return nil }
        if url.isFileURL {
            return poster ? mirror.posterURL(for: url) : mirror.url(for: url)
        }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return mirror.signedURL(forKey: MediaMirror.remoteKey(for: url))
    }

    /// The local file when it is there and downloaded; otherwise nil, after
    /// starting its iCloud download (a coordinated read would block).
    static func localFileIfAvailable(_ fileURL: URL,
                                     isAvailable: (URL) -> Bool = isLocallyAvailable,
                                     startDownload: (URL) -> Void = { CoordinatedFileManager.startDownloading(at: $0) }) -> URL? {
        if isAvailable(fileURL) { return fileURL }
        startDownload(fileURL)
        return nil
    }

    /// For a player: stream the mirror copy, falling back to the downloaded file.
    static func videoSource(for fileURL: URL, mirror: MediaMirror? = MediaMirror.shared,
                            isAvailable: (URL) -> Bool = isLocallyAvailable,
                            startDownload: (URL) -> Void = { CoordinatedFileManager.startDownloading(at: $0) }) -> VideoSource? {
        let local = localFileIfAvailable(fileURL, isAvailable: isAvailable, startDownload: startDownload)
        if let remote = mirrorURL(for: fileURL, mirror: mirror) {
            return VideoSource(primary: remote, fallback: local)
        }
        return local.map { VideoSource(primary: $0, fallback: nil) }
    }

    /// Bytes from the mirror (or any URL); nil on failure so the caller moves on.
    /// Links are stable for a day and the Worker marks files cacheable for a day,
    /// so repeats come from the URL cache (normal HTTP caching). A failed answer
    /// is dropped from the cache, so a file uploaded later shows on the next try.
    static func remoteData(from url: URL, timeout: TimeInterval = 6) async -> Data? {
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: timeout)
        request.setValue("image/*,application/pdf,*/*;q=0.5", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true, !data.isEmpty else {
            URLCache.shared.removeCachedResponse(for: request)
            return nil
        }
        return data
    }
}
