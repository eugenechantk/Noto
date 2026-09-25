import Foundation

/// Cloudflare Queues HTTP pull consumer: pull a leased batch, then ack or
/// retry each lease. Same API the OpenClaw Linear poller uses.
public struct CloudflareQueueClient: Sendable {
    public struct Message: Equatable, Sendable {
        public let leaseID: String
        public let attempts: Int
        public let body: Data
    }

    public struct Retry: Equatable, Sendable {
        public let leaseID: String
        public let delaySeconds: Int

        public init(leaseID: String, delaySeconds: Int) {
            self.leaseID = leaseID
            self.delaySeconds = delaySeconds
        }
    }

    let accountID: String
    let queueID: String
    let token: String
    let http: any HTTPFetching

    public init(accountID: String, queueID: String, token: String, http: any HTTPFetching = URLSessionFetcher()) {
        self.accountID = accountID
        self.queueID = queueID
        self.token = token
        self.http = http
    }

    var baseURL: URL {
        URL(string: "https://api.cloudflare.com/client/v4/accounts/\(accountID)/queues/\(queueID)/messages")!
    }

    public func pull(batchSize: Int = 10, visibilityTimeoutMs: Int = 10 * 60 * 1000) async throws -> [Message] {
        let result = try await post(baseURL.appendingPathComponent("pull"),
                                    body: ["batch_size": batchSize, "visibility_timeout_ms": visibilityTimeoutMs])
        let messages = (result["result"] as? [String: Any])?["messages"] as? [[String: Any]] ?? []
        return messages.compactMap { raw in
            guard let lease = raw["lease_id"] as? String else { return nil }
            return Message(leaseID: lease, attempts: raw["attempts"] as? Int ?? 0, body: Self.bodyData(raw["body"]))
        }
    }

    public func acknowledge(acks: [String], retries: [Retry]) async throws {
        guard !acks.isEmpty || !retries.isEmpty else { return }
        _ = try await post(baseURL.appendingPathComponent("ack"), body: [
            "acks": acks.map { ["lease_id": $0] },
            "retries": retries.map { ["lease_id": $0.leaseID, "delay_seconds": $0.delaySeconds] },
        ])
    }

    /// A JSON message arrives as its JSON text (or already decoded); a bytes
    /// message as base64. Normalise to the JSON bytes either way.
    static func bodyData(_ body: Any?) -> Data {
        switch body {
        case let text as String:
            if (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)) is [String: Any] {
                return Data(text.utf8)
            }
            return Data(base64Encoded: text) ?? Data(text.utf8)
        case let object as [String: Any]:
            return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        default:
            return Data()
        }
    }

    private func post(_ url: URL, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await http.fetch(request)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(response.statusCode), object["success"] as? Bool == true else {
            let message = ((object["errors"] as? [[String: Any]])?.first?["message"] as? String) ?? "HTTP \(response.statusCode)"
            throw SocialPostError.unreadable("Cloudflare Queues: \(message)")
        }
        return object
    }
}
