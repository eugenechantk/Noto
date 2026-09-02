import Darwin
import Foundation
import NotoAgentCore

@main
struct NotoAgentCLI {
    static func main() {
        do {
            let arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
            if arguments.command == "help" {
                print(Self.help)
                return
            }

            let vaultPath = try arguments.requiredValue(
                "vault",
                fallback: ProcessInfo.processInfo.environment["NOTO_VAULT"]
            )
            let service = NotoAgentService(vaultURL: URL(fileURLWithPath: vaultPath, isDirectory: true))

            switch arguments.command {
            case "health":
                try emit(service.health())

            case "daily-append":
                let text = try arguments.text()
                let requestID = try arguments.requiredValue("request-id")
                let date = try arguments.dateValue("date") ?? Date()
                try emit(service.dailyAppend(text: text, requestID: requestID, date: date))

            case "append":
                let text = try arguments.text()
                let requestID = try arguments.requiredValue("request-id")
                let path = try arguments.requiredValue("path")
                let date = try arguments.dateValue("date") ?? Date()
                try emit(service.append(
                    relativePath: path,
                    text: text,
                    requestID: requestID,
                    date: date
                ))

            case "search":
                let query = try arguments.requiredValue("query")
                let limit = try arguments.intValue("limit") ?? 8
                try emit(service.search(query: query, limit: limit))

            case "read":
                let path = try arguments.requiredValue("path")
                try emit(service.read(
                    relativePath: path,
                    startLine: try arguments.intValue("start-line"),
                    endLine: try arguments.intValue("end-line"),
                    maxCharacters: try arguments.intValue("max-characters") ?? 40_000
                ))

            default:
                throw CLIError.unknownCommand(arguments.command)
            }
        } catch {
            emitError(error)
            exit(1)
        }
    }

    private static func emit<Value: Encodable>(_ value: Value) throws {
        let envelope = SuccessEnvelope(data: value)
        let encoded = try JSONEncoder.output.encode(envelope)
        FileHandle.standardOutput.write(encoded)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func emitError(_ error: Error) {
        let envelope = FailureEnvelope(error: String(describing: error))
        let encoded = (try? JSONEncoder.output.encode(envelope))
            ?? Data("{\"success\":false,\"error\":\"Unknown error\"}\n".utf8)
        FileHandle.standardError.write(encoded)
        FileHandle.standardError.write(Data("\n".utf8))
    }

    private static let help = """
    noto-agent — deterministic local bridge for Hermes and a Noto markdown vault

    Usage:
      noto-agent health --vault <path>
      noto-agent daily-append --vault <path> --request-id <id> (--text <text> | --text-stdin)
      noto-agent search --vault <path> --query <query> [--limit 8]
      noto-agent read --vault <path> --path <relative.md> [--start-line N] [--end-line N]
      noto-agent append --vault <path> --path <relative.md> --request-id <id> (--text <text> | --text-stdin)

    Set NOTO_VAULT to omit --vault. All command results are JSON.
    """
}

private struct Arguments {
    let command: String
    private let values: [String: String]
    private let flags: Set<String>

    init(_ raw: [String]) throws {
        guard let first = raw.first else {
            command = "help"
            values = [:]
            flags = []
            return
        }
        if first == "--help" || first == "-h" || first == "help" {
            command = "help"
            values = [:]
            flags = []
            return
        }

        command = first
        var parsedValues: [String: String] = [:]
        var parsedFlags = Set<String>()
        var index = 1
        while index < raw.count {
            let option = raw[index]
            guard option.hasPrefix("--") else {
                throw CLIError.unexpectedArgument(option)
            }
            let key = String(option.dropFirst(2))
            if key == "text-stdin" {
                parsedFlags.insert(key)
                index += 1
                continue
            }
            let valueIndex = index + 1
            guard valueIndex < raw.count, !raw[valueIndex].hasPrefix("--") else {
                throw CLIError.missingValue(option)
            }
            parsedValues[key] = raw[valueIndex]
            index += 2
        }
        values = parsedValues
        flags = parsedFlags
    }

    func requiredValue(_ key: String, fallback: String? = nil) throws -> String {
        let value = values[key] ?? fallback
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLIError.missingOption("--\(key)")
        }
        return value
    }

    func intValue(_ key: String) throws -> Int? {
        guard let raw = values[key] else { return nil }
        guard let value = Int(raw), value > 0 else {
            throw CLIError.invalidInteger("--\(key)", raw)
        }
        return value
    }

    func dateValue(_ key: String) throws -> Date? {
        guard let raw = values[key] else { return nil }
        guard let value = ISO8601DateFormatter().date(from: raw) else {
            throw CLIError.invalidDate("--\(key)", raw)
        }
        return value
    }

    func text() throws -> String {
        if flags.contains("text-stdin") {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard let value = String(data: data, encoding: .utf8) else {
                throw CLIError.invalidStdin
            }
            return value
        }
        return try requiredValue("text")
    }
}

private enum CLIError: Error, CustomStringConvertible {
    case unknownCommand(String)
    case unexpectedArgument(String)
    case missingValue(String)
    case missingOption(String)
    case invalidInteger(String, String)
    case invalidDate(String, String)
    case invalidStdin

    var description: String {
        switch self {
        case .unknownCommand(let command): "Unknown command: \(command)"
        case .unexpectedArgument(let argument): "Unexpected argument: \(argument)"
        case .missingValue(let option): "Missing value after \(option)"
        case .missingOption(let option): "Missing required option: \(option)"
        case .invalidInteger(let option, let value): "\(option) requires a positive integer, got: \(value)"
        case .invalidDate(let option, let value): "\(option) requires an ISO-8601 date, got: \(value)"
        case .invalidStdin: "Standard input is not valid UTF-8 text."
        }
    }
}

private struct SuccessEnvelope<Value: Encodable>: Encodable {
    let success = true
    let data: Value
}

private struct FailureEnvelope: Encodable {
    let success = false
    let error: String
}

private extension JSONEncoder {
    static var output: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
