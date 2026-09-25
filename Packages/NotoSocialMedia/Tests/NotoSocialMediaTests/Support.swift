import Foundation
@testable import NotoSocialMedia

/// Serves canned responses by URL prefix and records every request.
final class FakeHTTP: HTTPFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [(prefix: String, status: Int, data: Data)] = []
    private(set) var requests: [URLRequest] = []

    func serve(_ prefix: String, status: Int = 200, data: Data) {
        lock.withLock { routes.append((prefix, status, data)) }
    }

    func serve(_ prefix: String, status: Int = 200, text: String) {
        serve(prefix, status: status, data: Data(text.utf8))
    }

    var requestedURLs: [String] { lock.withLock { requests.compactMap { $0.url?.absoluteString } } }

    func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let route = lock.withLock { () -> (Int, Data)? in
            requests.append(request)
            return routes.first { url.absoluteString.hasPrefix($0.prefix) }.map { ($0.status, $0.data) }
        }
        let (status, data) = route ?? (404, Data())
        return (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    static func text(_ name: String) throws -> String {
        String(decoding: try data(name), as: UTF8.self)
    }

    /// An Instagram embed page whose `contextJSON` carries `shortcodeMedia`.
    static func instagramEmbed(shortcodeMedia: [String: Any]) throws -> String {
        let context: [String: Any] = ["context": ["type": shortcodeMedia["__typename"] ?? ""], "gql_data": ["shortcode_media": shortcodeMedia]]
        let inner = String(decoding: try JSONSerialization.data(withJSONObject: context), as: UTF8.self)
        let escaped = String(decoding: try JSONSerialization.data(withJSONObject: inner, options: .fragmentsAllowed), as: UTF8.self)
        return "<html><script>requireLazy([],function(){ new PolarisEmbed({\"isRichEmbed\":true,\"contextJSON\":\(escaped)}) });</script></html>"
    }

    static func tempDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

import Testing
