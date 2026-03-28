import Foundation

public enum ClaudeAPIError: Error, Sendable {
    case httpError(statusCode: Int, body: String?)
    case decodingError(underlying: Error)
    case invalidResponse
}

public enum ChatLoopError: Error, Sendable {
    case unexpectedStopReason(String)
}
