import Foundation
@testable import NotoChat

// MARK: - Temp vault

enum TempVault {
    static func make(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notochat-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (rel, content) in files {
            let url = root.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - SSE builder

/// Build a `data: {json}` SSE line from a JSON object (avoids hand-escaping JSON in tests).
func sseLine(_ object: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: object)
    return "data: " + String(data: data, encoding: .utf8)!
}

// MARK: - Mock URLProtocol

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var capturedURL: URL?

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.capturedURL = request.url
        let response = HTTPURLResponse(url: request.url!,
                                       statusCode: MockURLProtocol.statusCode,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: MockURLProtocol.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Scripted fake LLM client

/// Returns a predefined list of stream events per round; repeats the last round if exhausted.
final class ScriptedClient: LLMClienting, @unchecked Sendable {
    private let rounds: [[ChatStreamEvent]]
    private let lock = NSLock()
    private var index = 0

    init(rounds: [[ChatStreamEvent]]) { self.rounds = rounds }

    func complete(_ request: ChatRequest) async throws -> ChatMessage {
        .assistant("unused")
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        lock.lock()
        let events = rounds.isEmpty ? [] : rounds[min(index, rounds.count - 1)]
        index += 1
        lock.unlock()
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}
