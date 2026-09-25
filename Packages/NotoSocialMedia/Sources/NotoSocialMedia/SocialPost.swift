import Foundation
import NotoShareCapture

/// One image or video attached to a post, as the platform serves it.
public struct SocialMedia: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case image
        case video
    }

    public let kind: Kind
    /// Full-size image, or the best progressive MP4 for a video.
    public let url: URL

    public init(kind: Kind, url: URL) {
        self.kind = kind
        self.url = url
    }
}

/// A resolved X or Instagram post: who wrote it, what it says, its media in
/// order (a carousel is several items), and the post it quotes, if any.
public struct SocialPost: Equatable, Sendable {
    public let platform: ShareMediaPlatform
    /// Stable id used to name downloaded files (`x-<status id>`, `instagram-<shortcode>`).
    public let postID: String
    public let author: String?
    public let text: String?
    public let media: [SocialMedia]
    public let quoted: [SocialPost]

    public init(platform: ShareMediaPlatform, postID: String, author: String?, text: String?,
                media: [SocialMedia], quoted: [SocialPost] = []) {
        self.platform = platform
        self.postID = postID
        self.author = author
        self.text = text
        self.media = media
        self.quoted = quoted
    }

    /// This post's media followed by every quoted post's.
    public var allMedia: [SocialMedia] {
        media + quoted.flatMap(\.allMedia)
    }
}

public enum SocialPostError: Error, Equatable {
    case unsupportedURL
    case badResponse(status: Int)
    case unreadable(String)
}

/// Minimal HTTP seam so resolvers and the downloader run against fixtures in tests.
public protocol HTTPFetching: Sendable {
    func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionFetcher: HTTPFetching {
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SocialPostError.badResponse(status: 0) }
        return (data, http)
    }
}

enum Browser {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
}
