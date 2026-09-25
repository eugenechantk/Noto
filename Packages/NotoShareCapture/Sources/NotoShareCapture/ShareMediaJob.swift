import Foundation

public enum ShareMediaPlatform: String, Codable, Sendable {
    case x
    case instagram
}

/// Which shared URLs carry media worth fetching: X status posts and Instagram
/// posts / reels. Everything else stays a plain link capture.
public enum ShareMediaSource {
    private static let xHosts: Set<String> = ["x.com", "www.x.com", "mobile.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com"]
    private static let instagramHosts: Set<String> = ["instagram.com", "www.instagram.com", "m.instagram.com"]
    private static let instagramKinds: Set<String> = ["p", "reel", "reels", "tv"]

    public static func platform(for url: URL) -> ShareMediaPlatform? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased() else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)

        if xHosts.contains(host) {
            // /<user>/status/<id>[/…]  or  /i/web/status/<id>
            if let index = parts.firstIndex(of: "status"), index + 1 < parts.count,
               !parts[index + 1].isEmpty, parts[index + 1].allSatisfy(\.isNumber) {
                return .x
            }
            return nil
        }

        if instagramHosts.contains(host) {
            // /p/<code>/, /reel/<code>/, and the newer /<user>/p/<code>/
            for (index, part) in parts.enumerated() where instagramKinds.contains(part) {
                if index + 1 < parts.count, !parts[index + 1].isEmpty { return .instagram }
            }
            return nil
        }
        return nil
    }
}

/// A request for Hermes to fetch a shared post's media and add it to the
/// capture note. Sent by the share extension through the Cloudflare Worker.
public struct ShareMediaJob: Codable, Equatable, Sendable, Identifiable {
    public static let currentVersion = 1

    public let version: Int
    /// The staged capture's id — the job's identity end to end.
    public let captureId: UUID
    public let url: URL
    public let platform: ShareMediaPlatform
    /// Vault-relative path the capture will be filed at (`inbox/…md`).
    public let notePath: String
    public let sharedAt: Date
    public let title: String?

    public var id: UUID { captureId }

    public init(version: Int = ShareMediaJob.currentVersion, captureId: UUID, url: URL, platform: ShareMediaPlatform,
                notePath: String, sharedAt: Date, title: String?) {
        self.version = version
        self.captureId = captureId
        self.url = url
        self.platform = platform
        self.notePath = notePath
        self.sharedAt = sharedAt
        self.title = title
    }

    /// The job for a staged capture, or nil when the URL has no fetchable media.
    public static func make(for capture: PendingCapture, url: URL, title: String?, calendar: Calendar = .current) -> ShareMediaJob? {
        guard let platform = ShareMediaSource.platform(for: url),
              let notePath = CaptureNotePath.relativePath(forRawBody: capture.body, date: capture.createdAt, calendar: calendar) else {
            return nil
        }
        return ShareMediaJob(captureId: capture.id, url: url, platform: platform, notePath: notePath,
                             sharedAt: capture.createdAt, title: title)
    }

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
