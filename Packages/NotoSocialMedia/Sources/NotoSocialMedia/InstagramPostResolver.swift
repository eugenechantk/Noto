import Foundation
import NotoShareCapture

/// Reads an Instagram post through its public embed page
/// (`/p/<shortcode>/embed/captioned/`), whose `contextJSON` carries the same
/// `shortcode_media` graph the app uses: `GraphImage`, `GraphVideo`, or a
/// `GraphSidecar` carousel of either.
public enum InstagramPostResolver {
    private static let kinds: Set<String> = ["p", "reel", "reels", "tv"]

    public static func shortcode(in url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        for (index, part) in parts.enumerated() where kinds.contains(part) && index + 1 < parts.count {
            let code = parts[index + 1]
            if !code.isEmpty { return code }
        }
        return nil
    }

    public static func embedURL(for shortcode: String) -> URL {
        URL(string: "https://www.instagram.com/p/\(shortcode)/embed/captioned/")!
    }

    public static func parse(html: String, shortcode: String) throws -> SocialPost {
        guard let media = try shortcodeMedia(in: html) else {
            throw SocialPostError.unreadable("embed page has no media graph — private post or login wall")
        }
        let owner = media["owner"] as? [String: Any]
        let caption = ((media["edge_media_to_caption"] as? [String: Any])?["edges"] as? [[String: Any]])?
            .first.flatMap { ($0["node"] as? [String: Any])?["text"] as? String }
        let children = ((media["edge_sidecar_to_children"] as? [String: Any])?["edges"] as? [[String: Any]])?
            .compactMap { $0["node"] as? [String: Any] } ?? []
        let items = (children.isEmpty ? [media] : children).compactMap(mediaItem(from:))
        guard !items.isEmpty else { throw SocialPostError.unreadable("post has no media") }
        let text = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        return SocialPost(platform: .instagram, postID: (media["shortcode"] as? String) ?? shortcode,
                          author: owner?["username"] as? String,
                          text: (text?.isEmpty ?? true) ? nil : text, media: items)
    }

    static func mediaItem(from node: [String: Any]) -> SocialMedia? {
        if (node["is_video"] as? Bool) == true, let raw = node["video_url"] as? String, let url = URL(string: raw) {
            return SocialMedia(kind: .video, url: url)
        }
        guard let raw = node["display_url"] as? String, let url = URL(string: raw) else { return nil }
        return SocialMedia(kind: .image, url: url)
    }

    /// `"contextJSON":"<escaped JSON>"` → `context.gql_data.shortcode_media`.
    static func shortcodeMedia(in html: String) throws -> [String: Any]? {
        guard let regex = try? NSRegularExpression(pattern: #""contextJSON":"((?:[^"\\]|\\.)*)""#),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let escaped = "\"" + html[range] + "\""
        guard let inner = try JSONSerialization.jsonObject(with: Data(escaped.utf8), options: .fragmentsAllowed) as? String,
              let context = try JSONSerialization.jsonObject(with: Data(inner.utf8)) as? [String: Any] else {
            return nil
        }
        return (context["gql_data"] as? [String: Any])?["shortcode_media"] as? [String: Any]
    }
}

/// Routes a shared URL to its platform resolver.
public struct SocialPostResolver: Sendable {
    let http: any HTTPFetching

    public init(http: any HTTPFetching = URLSessionFetcher()) {
        self.http = http
    }

    public func resolve(_ url: URL) async throws -> SocialPost {
        switch ShareMediaSource.platform(for: url) {
        case .x:
            guard let id = XPostResolver.statusID(in: url) else { throw SocialPostError.unsupportedURL }
            return try XPostResolver.parse(try await get(XPostResolver.requestURL(for: id)))
        case .instagram:
            guard let code = InstagramPostResolver.shortcode(in: url) else { throw SocialPostError.unsupportedURL }
            let data = try await get(InstagramPostResolver.embedURL(for: code))
            return try InstagramPostResolver.parse(html: String(decoding: data, as: UTF8.self), shortcode: code)
        case nil:
            throw SocialPostError.unsupportedURL
        }
    }

    private func get(_ url: URL) async throws -> Data {
        let (data, response) = try await http.fetch(Browser.request(url))
        guard (200..<300).contains(response.statusCode) else { throw SocialPostError.badResponse(status: response.statusCode) }
        return data
    }
}
