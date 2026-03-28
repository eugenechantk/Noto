import Foundation
import OSLog

private let logger = Logger(subsystem: "com.noto.claudeapi", category: "ClaudeAPIClient")

/// Protocol for the Claude API client, enabling testability via mocks.
public protocol ClaudeAPIClientProtocol: Sendable {
    func sendMessage(_ request: MessagesRequest) async throws -> MessagesResponse
}

/// URLSession-based client for the Anthropic Claude Messages API.
public struct ClaudeAPIClient: ClaudeAPIClientProtocol, Sendable {
    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession
    private let anthropicVersion: String

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://ai-gateway.vercel.sh/v1/messages")!,
        session: URLSession = .shared,
        anthropicVersion: String = "2023-06-01"
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
        self.anthropicVersion = anthropicVersion
    }

    public func sendMessage(_ request: MessagesRequest) async throws -> MessagesResponse {
        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        urlRequest.httpBody = try encoder.encode(request)

        logger.debug("Sending request to Claude API: model=\(request.model), maxTokens=\(request.maxTokens)")

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let body = String(data: data, encoding: .utf8)
            logger.error("Claude API error: status=\(httpResponse.statusCode), body=\(body ?? "nil")")
            throw ClaudeAPIError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        do {
            let decoder = JSONDecoder()
            let messagesResponse = try decoder.decode(MessagesResponse.self, from: data)
            logger.debug("Claude API response: stopReason=\(messagesResponse.stopReason), tokens=\(messagesResponse.usage.inputTokens)+\(messagesResponse.usage.outputTokens)")
            return messagesResponse
        } catch {
            logger.error("Failed to decode Claude API response: \(error)")
            throw ClaudeAPIError.decodingError(underlying: error)
        }
    }
}
