import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Client protocol

/// Abstraction over the chat model backend so `ChatAgent` can be unit-tested with a fake.
public protocol LLMClienting: Sendable {
    /// One non-streaming completion. Returns the assistant message (may contain tool calls).
    func complete(_ request: ChatRequest) async throws -> ChatMessage
    /// A streaming completion: text deltas, then (optionally) assembled tool calls + finish.
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error>
}

// MARK: - SSE decoder (pure, unit-testable)

/// Incrementally decodes OpenAI/OpenRouter SSE `data:` lines into `ChatStreamEvent`s.
/// Accumulates streamed `tool_calls` deltas (arguments arrive in fragments) keyed by index.
struct SSEStreamDecoder {
    private struct Partial { var id: String = ""; var name: String = ""; var arguments: String = "" }
    private var partials: [Int: Partial] = [:]
    private var emittedToolCalls = false
    private(set) var isDone = false

    /// Feed one raw line (as produced by `URLSession.bytes.lines`). Returns events to emit.
    mutating func ingest(_ rawLine: String) -> [ChatStreamEvent] {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        // Skip blank lines and SSE comments/keep-alives (": OPENROUTER PROCESSING").
        guard !line.isEmpty, !line.hasPrefix(":") else { return [] }
        guard line.hasPrefix("data:") else { return [] }
        let payload = String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            isDone = true
            return []
        }
        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data) else {
            return []
        }

        var events: [ChatStreamEvent] = []
        for choice in chunk.choices {
            if let content = choice.delta.content, !content.isEmpty {
                events.append(.textDelta(content))
            }
            if let deltas = choice.delta.toolCalls {
                for d in deltas {
                    var p = partials[d.index] ?? Partial()
                    if let id = d.id { p.id = id }
                    if let n = d.function?.name { p.name += n }
                    if let a = d.function?.arguments { p.arguments += a }
                    partials[d.index] = p
                }
            }
            if let reason = choice.finishReason {
                events.append(contentsOf: flushToolCalls())
                events.append(.finished(reason: reason))
                isDone = true
            }
        }
        return events
    }

    /// Assemble any accumulated tool calls (once). Ordered by streamed index.
    mutating func flushToolCalls() -> [ChatStreamEvent] {
        guard !emittedToolCalls, !partials.isEmpty else { return [] }
        emittedToolCalls = true
        let calls = partials
            .sorted { $0.key < $1.key }
            .map { _, p in
                ToolCall(id: p.id.isEmpty ? UUID().uuidString : p.id,
                         type: "function",
                         function: .init(name: p.name, arguments: p.arguments))
            }
        return [.toolCalls(calls)]
    }
}

// MARK: - OpenRouter client

/// Hand-rolled OpenRouter (OpenAI-compatible) client. Zero external dependencies — pure `URLSession`.
public struct OpenRouterClient: LLMClienting {
    public struct Configuration: Sendable {
        public var apiKey: String
        public var baseURL: URL
        /// Optional OpenRouter attribution headers.
        public var referer: String?
        public var title: String?
        public var session: URLSession

        public init(apiKey: String,
                    baseURL: URL = URL(string: "https://openrouter.ai/api/v1")!,
                    referer: String? = nil,
                    title: String? = nil,
                    session: URLSession = .shared) {
            self.apiKey = apiKey
            self.baseURL = baseURL
            self.referer = referer
            self.title = title
            self.session = session
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    // Build the POST /chat/completions request.
    func makeURLRequest(_ request: ChatRequest, stream: Bool) throws -> URLRequest {
        guard !configuration.apiKey.isEmpty else { throw LLMError.missingAPIKey }
        let url = configuration.baseURL.appendingPathComponent("chat/completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if stream { req.setValue("text/event-stream", forHTTPHeaderField: "Accept") }
        if let referer = configuration.referer { req.setValue(referer, forHTTPHeaderField: "HTTP-Referer") }
        if let title = configuration.title { req.setValue(title, forHTTPHeaderField: "X-Title") }
        let encoder = JSONEncoder()
        req.httpBody = try encoder.encode(ChatCompletionPayload(request, stream: stream))
        return req
    }

    public func complete(_ request: ChatRequest) async throws -> ChatMessage {
        let urlRequest = try makeURLRequest(request, stream: false)
        let (data, response) = try await configuration.session.data(for: urlRequest)
        try Self.validate(response, data: data)
        do {
            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            guard let message = decoded.choices.first?.message else { throw LLMError.emptyResponse }
            return message
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.decoding(String(describing: error))
        }
    }

    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try makeURLRequest(request, stream: true)
                    let (bytes, response) = try await configuration.session.bytes(for: urlRequest)
                    try Self.validate(response, data: nil)
                    var decoder = SSEStreamDecoder()
                    for try await line in bytes.lines {
                        for event in decoder.ingest(line) {
                            continuation.yield(event)
                        }
                        if decoder.isDone { break }
                    }
                    // Safety net: if the stream ended without an explicit finish but produced
                    // tool calls, surface them.
                    for event in decoder.flushToolCalls() { continuation.yield(event) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Status validation

    static func validate(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw LLMError.http(status: http.statusCode, body: body)
        }
    }
}
