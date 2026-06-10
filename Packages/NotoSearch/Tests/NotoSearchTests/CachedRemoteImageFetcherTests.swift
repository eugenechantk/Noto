import Foundation
import Testing
@testable import NotoSearch

/// Test case index
/// 1. testValidPNGIsFetchedAndCached — 200 + image/png → returns body, writes exactly one cache file
/// 2. testSecondFetchIsServedFromCacheWhenNetworkFails — stub turns into errors; cached data still returned
/// 3. test404ReturnsNilAndCachesNothing — non-200 → nil, cache stays empty
/// 4. testNonImagePayloadReturnsNilAndCachesNothing — text/html + HTML bytes → nil, cache stays empty
/// 5. testTransportErrorReturnsNil — connection failure → nil, cache stays empty
///
/// Serialized: all tests share `RemoteImageStubURLProtocol.responder`.
@Suite(.serialized)
struct CachedRemoteImageFetcherTests {
    private let imageURL = URL(string: "https://example.com/assets/diagram.png")!

    @Test func testValidPNGIsFetchedAndCached() throws {
        let (fetcher, cacheDirectory) = makeFetcher()
        defer { cleanUp(cacheDirectory) }
        let png = tinyPNG()
        RemoteImageStubURLProtocol.responder = { _ in
            .success(statusCode: 200, contentType: "image/png", body: png)
        }
        defer { RemoteImageStubURLProtocol.responder = nil }

        let fetched = fetcher.fetch(url: imageURL)
        #expect(fetched == png)
        #expect(fetcher.cachedData(for: imageURL) == png)
        let cacheFiles = (try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path)) ?? []
        #expect(cacheFiles.count == 1)
    }

    @Test func testSecondFetchIsServedFromCacheWhenNetworkFails() throws {
        let (fetcher, cacheDirectory) = makeFetcher()
        defer { cleanUp(cacheDirectory) }
        let png = tinyPNG()
        RemoteImageStubURLProtocol.responder = { _ in
            .success(statusCode: 200, contentType: "image/png", body: png)
        }
        defer { RemoteImageStubURLProtocol.responder = nil }
        #expect(fetcher.fetch(url: imageURL) == png)

        // Network goes away; the cache must answer.
        RemoteImageStubURLProtocol.responder = { _ in
            .failure(URLError(.notConnectedToInternet))
        }
        #expect(fetcher.fetch(url: imageURL) == png)
    }

    @Test func test404ReturnsNilAndCachesNothing() throws {
        let (fetcher, cacheDirectory) = makeFetcher()
        defer { cleanUp(cacheDirectory) }
        RemoteImageStubURLProtocol.responder = { _ in
            .success(statusCode: 404, contentType: "text/plain", body: Data("not found".utf8))
        }
        defer { RemoteImageStubURLProtocol.responder = nil }

        #expect(fetcher.fetch(url: imageURL) == nil)
        #expect(fetcher.cachedData(for: imageURL) == nil)
        let cacheFiles = (try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path)) ?? []
        #expect(cacheFiles.isEmpty)
    }

    @Test func testNonImagePayloadReturnsNilAndCachesNothing() throws {
        let (fetcher, cacheDirectory) = makeFetcher()
        defer { cleanUp(cacheDirectory) }
        RemoteImageStubURLProtocol.responder = { _ in
            .success(
                statusCode: 200,
                contentType: "text/html",
                body: Data("<html><body>Sign in to view this image</body></html>".utf8)
            )
        }
        defer { RemoteImageStubURLProtocol.responder = nil }

        #expect(fetcher.fetch(url: imageURL) == nil)
        #expect(fetcher.cachedData(for: imageURL) == nil)
        let cacheFiles = (try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path)) ?? []
        #expect(cacheFiles.isEmpty)
    }

    @Test func testTransportErrorReturnsNil() throws {
        let (fetcher, cacheDirectory) = makeFetcher()
        defer { cleanUp(cacheDirectory) }
        RemoteImageStubURLProtocol.responder = { _ in
            .failure(URLError(.timedOut))
        }
        defer { RemoteImageStubURLProtocol.responder = nil }

        #expect(fetcher.fetch(url: imageURL) == nil)
        #expect(fetcher.cachedData(for: imageURL) == nil)
    }

    // MARK: - Helpers

    private func makeFetcher() -> (CachedRemoteImageFetcher, URL) {
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("noto-image-cache-tests-\(UUID().uuidString)", isDirectory: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RemoteImageStubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let fetcher = CachedRemoteImageFetcher(cacheDirectory: cacheDirectory, session: session, timeout: 5)
        return (fetcher, cacheDirectory)
    }

    private func cleanUp(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Minimal valid PNG (8x8 white) generated in code — no fixture files.
    private func tinyPNG() -> Data {
        guard let data = try? DescriberTestImageRenderer.pngData(text: nil, fontSize: 0, width: 8, height: 8) else {
            Issue.record("failed to render tiny PNG")
            return Data()
        }
        return data
    }
}

// MARK: - URLProtocol stub (no real network)

enum RemoteImageStubResponse {
    case success(statusCode: Int, contentType: String, body: Data)
    case failure(Error)
}

final class RemoteImageStubURLProtocol: URLProtocol {
    /// Set per test; suite is `.serialized` so this shared state is safe.
    nonisolated(unsafe) static var responder: ((URLRequest) -> RemoteImageStubResponse)?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let responder = Self.responder, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        switch responder(request) {
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .success(let statusCode, let contentType, let body):
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": contentType,
                    "Content-Length": "\(body.count)",
                ]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
