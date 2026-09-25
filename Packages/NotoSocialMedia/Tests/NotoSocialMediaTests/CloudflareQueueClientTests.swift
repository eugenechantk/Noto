import Foundation
import Testing
@testable import NotoSocialMedia

/// Test case index
/// 1. bodyIsNormalisedFromStringObjectOrBase64 — every body shape the pull API can return decodes to the job JSON (SC7)
/// 2. pullAndAckSendAuthenticatedRequests — endpoints, bearer token, batch settings, ack/retry payload, message parsing (SC7)
/// 3. apiErrorsSurface — success:false becomes a thrown error with Cloudflare's message (SC7)
struct CloudflareQueueClientTests {
    @Test func bodyIsNormalisedFromStringObjectOrBase64() throws {
        let json = #"{"captureId":"x"}"#
        #expect(CloudflareQueueClient.bodyData(json) == Data(json.utf8))
        #expect(CloudflareQueueClient.bodyData(Data(json.utf8).base64EncodedString()) == Data(json.utf8))
        let fromObject = CloudflareQueueClient.bodyData(["captureId": "x"])
        #expect((try JSONSerialization.jsonObject(with: fromObject) as? [String: String]) == ["captureId": "x"])
        #expect(CloudflareQueueClient.bodyData(nil).isEmpty)
    }

    @Test func pullAndAckSendAuthenticatedRequests() async throws {
        let http = FakeHTTP()
        let base = "https://api.cloudflare.com/client/v4/accounts/acct/queues/q1/messages"
        http.serve(base + "/pull", text: #"{"success":true,"result":{"messages":[{"lease_id":"L1","attempts":2,"body":"{\"a\":1}"}]}}"#)
        http.serve(base + "/ack", text: #"{"success":true,"result":{}}"#)
        let client = CloudflareQueueClient(accountID: "acct", queueID: "q1", token: "tok", http: http)

        let messages = try await client.pull(batchSize: 5, visibilityTimeoutMs: 1000)
        #expect(messages == [.init(leaseID: "L1", attempts: 2, body: Data(#"{"a":1}"#.utf8))])
        try await client.acknowledge(acks: ["L1"], retries: [.init(leaseID: "L2", delaySeconds: 60)])
        try await client.acknowledge(acks: [], retries: [])

        #expect(http.requests.count == 2)
        let pull = http.requests[0], ack = http.requests[1]
        #expect(pull.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        let pullBody = try #require(try JSONSerialization.jsonObject(with: pull.httpBody!) as? [String: Int])
        #expect(pullBody == ["batch_size": 5, "visibility_timeout_ms": 1000])
        let ackBody = try #require(try JSONSerialization.jsonObject(with: ack.httpBody!) as? [String: [[String: Any]]])
        #expect(ackBody["acks"]?.first?["lease_id"] as? String == "L1")
        #expect(ackBody["retries"]?.first?["delay_seconds"] as? Int == 60)
    }

    @Test func apiErrorsSurface() async {
        let http = FakeHTTP()
        http.serve("https://api.cloudflare.com/", status: 400,
                   text: #"{"success":false,"errors":[{"message":"messages cannot be pulled unless http_pull mode is enabled"}]}"#)
        let client = CloudflareQueueClient(accountID: "a", queueID: "q", token: "t", http: http)
        await #expect(throws: SocialPostError.unreadable("Cloudflare Queues: messages cannot be pulled unless http_pull mode is enabled")) {
            _ = try await client.pull()
        }
    }
}
