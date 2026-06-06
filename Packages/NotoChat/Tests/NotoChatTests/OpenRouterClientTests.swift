import Foundation
import Testing
@testable import NotoChat

// Verifies SC4 (request building + non-stream) and SC5 (streaming end-to-end via URLSession).
// Serialized: these tests share MockURLProtocol's static response state.
@Suite(.serialized) struct OpenRouterClientTests {

    private func client(session: URLSession) -> OpenRouterClient {
        OpenRouterClient(configuration: .init(apiKey: "test-key", session: session))
    }

    @Test func buildsCorrectChatCompletionsRequest() throws {
        let c = OpenRouterClient(configuration: .init(apiKey: "secret"))
        let request = ChatRequest(model: "google/gemini-3.1-flash-lite",
                                  messages: [.user("hi")],
                                  tools: VaultTools.toolDefinitions)
        let urlRequest = try c.makeURLRequest(request, stream: false)

        #expect(urlRequest.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(urlRequest.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "google/gemini-3.1-flash-lite")
        #expect(json["stream"] as? Bool == false)
        #expect((json["messages"] as? [[String: Any]])?.count == 1)
        #expect((json["tools"] as? [[String: Any]])?.count == 3)
        #expect(json["tool_choice"] as? String == "auto")
    }

    @Test func missingAPIKeyThrows() {
        let c = OpenRouterClient(configuration: .init(apiKey: ""))
        #expect(throws: LLMError.self) {
            _ = try c.makeURLRequest(ChatRequest(messages: [.user("hi")]), stream: false)
        }
    }

    @Test func completeParsesAssistantMessage() async throws {
        MockURLProtocol.statusCode = 200
        MockURLProtocol.responseData = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["role": "assistant", "content": "Hello there."],
                         "finish_reason": "stop"]]
        ])
        let c = client(session: MockURLProtocol.makeSession())

        let message = try await c.complete(ChatRequest(messages: [.user("hi")]))
        #expect(message.role == .assistant)
        #expect(message.content == "Hello there.")
    }

    @Test func streamYieldsTextDeltasAndFinish() async throws {
        let body = [
            sseLine(["choices": [["delta": ["content": "Hi "]]]]),
            sseLine(["choices": [["delta": ["content": "there"]]]]),
            sseLine(["choices": [["delta": [:], "finish_reason": "stop"]]]),
            "data: [DONE]",
            "",
        ].joined(separator: "\n")
        MockURLProtocol.statusCode = 200
        MockURLProtocol.responseData = Data(body.utf8)
        let c = client(session: MockURLProtocol.makeSession())

        var collected: [ChatStreamEvent] = []
        for try await event in c.stream(ChatRequest(messages: [.user("hi")])) {
            collected.append(event)
        }
        #expect(collected == [.textDelta("Hi "), .textDelta("there"), .finished(reason: "stop")])
    }

    @Test func streamSurfacesHTTPError() async throws {
        MockURLProtocol.statusCode = 401
        MockURLProtocol.responseData = Data("unauthorized".utf8)
        let c = client(session: MockURLProtocol.makeSession())

        await #expect(throws: LLMError.self) {
            for try await _ in c.stream(ChatRequest(messages: [.user("hi")])) {}
        }
    }
}
