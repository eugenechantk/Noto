import Foundation
import NotoSearch
import NotoVault

public enum NotoAgentError: Error, CustomStringConvertible {
    case invalidVault(String)
    case invalidPath(String)
    case noteNotFound(String)
    case invalidText
    case invalidRequestID
    case readFailed(String)
    case writeFailed(String)
    case receiptFailed(String)

    public var description: String {
        switch self {
        case .invalidVault(let path): "Vault is unavailable or not a directory: \(path)"
        case .invalidPath(let path): "Invalid or escaped vault-relative markdown path: \(path)"
        case .noteNotFound(let path): "No markdown note exists at: \(path)"
        case .invalidText: "Text must not be empty."
        case .invalidRequestID: "A non-empty request ID is required for idempotent writes."
        case .readFailed(let path): "Could not read note: \(path)"
        case .writeFailed(let path): "Could not write note: \(path)"
        case .receiptFailed(let detail): "Could not update the idempotency receipt ledger: \(detail)"
        }
    }
}

public struct NotoAgentHealth: Codable, Sendable, Equatable {
    public let vault: String
    public let readable: Bool
    public let writable: Bool
    public let markdownFiles: Int
    public let dailyNotes: Int
}

public struct NotoMutationResult: Codable, Sendable, Equatable {
    public let path: String
    public let deepLink: String
    public let title: String
    public let changed: Bool
    public let duplicate: Bool
    public let modifiedAt: Date
}

public struct NotoSearchHit: Codable, Sendable, Equatable {
    public let path: String
    public let deepLink: String
    public let title: String
    public let breadcrumb: String
    public let snippet: String
    public let lineStart: Int?
    public let kind: String
    public let score: Double
}

public struct NotoReadResult: Codable, Sendable, Equatable {
    public let path: String
    public let deepLink: String
    public let text: String
    public let startLine: Int
    public let endLine: Int
    public let totalLines: Int
    public let truncated: Bool
}

public struct NotoAgentService {
    public let vaultURL: URL
    public let indexDirectory: URL

    private let fileManager: FileManager
    private let fileSystem: any VaultFileSystem
    private let pathResolver: VaultPathResolver

    public init(
        vaultURL: URL,
        indexDirectory: URL? = nil,
        fileManager: FileManager = .default,
        fileSystem: any VaultFileSystem = CoordinatedVaultFileSystem()
    ) {
        self.vaultURL = vaultURL.standardizedFileURL
        self.indexDirectory = indexDirectory
            ?? MarkdownSearchIndexer.defaultIndexDirectory(for: vaultURL.standardizedFileURL)
        self.fileManager = fileManager
        self.fileSystem = fileSystem
        self.pathResolver = VaultPathResolver(vaultRootURL: vaultURL)
    }

    public func health() throws -> NotoAgentHealth {
        try validateVault()
        var markdownFiles = 0
        var dailyNotes = 0
        let dailyRoot = vaultURL.appendingPathComponent("Daily Notes", isDirectory: true).standardizedFileURL.path

        if let enumerator = fileManager.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    continue
                }
                guard url.pathExtension.localizedCaseInsensitiveCompare("md") == .orderedSame else { continue }
                markdownFiles += 1
                if url.deletingLastPathComponent().standardizedFileURL.path == dailyRoot {
                    dailyNotes += 1
                }
            }
        }

        return NotoAgentHealth(
            vault: vaultURL.path,
            readable: fileManager.isReadableFile(atPath: vaultURL.path),
            writable: fileManager.isWritableFile(atPath: vaultURL.path),
            markdownFiles: markdownFiles,
            dailyNotes: dailyNotes
        )
    }

    public func dailyAppend(
        text: String,
        requestID: String,
        date: Date = Date(),
        calendar: Calendar = .current
    ) throws -> NotoMutationResult {
        try validateVault()
        let normalizedText = try validatedText(text)
        let resolved = DailyNoteService(vaultRootURL: vaultURL, fileSystem: fileSystem)
            .ensure(date: date, calendar: calendar)
        guard fileSystem.fileExists(at: resolved.fileURL) else {
            throw NotoAgentError.writeFailed(resolved.fileURL.path)
        }

        let relativePath = try relativeNotePath(for: resolved.fileURL)
        let time = Self.captureTimeFormatter(calendar: calendar).string(from: date)
        return try idempotentMutation(
            relativePath: relativePath,
            requestID: requestID,
            date: date,
            transform: { Self.appendingDailyCapture(normalizedText, time: time, to: $0) }
        )
    }

    public func append(
        relativePath: String,
        text: String,
        requestID: String,
        date: Date = Date()
    ) throws -> NotoMutationResult {
        try validateVault()
        let normalizedText = try validatedText(text)
        return try idempotentMutation(
            relativePath: relativePath,
            requestID: requestID,
            date: date,
            transform: { Self.appendingMarkdownBlock(normalizedText, to: $0) }
        )
    }

    public func search(query: String, limit: Int = 8) throws -> [NotoSearchHit] {
        try validateVault()
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        let indexer = MarkdownSearchIndexer(vaultURL: vaultURL, indexDirectory: indexDirectory)
        _ = try indexer.refreshChangedFiles()
        let results = try indexer.openStore().search(
            query: normalizedQuery,
            vaultURL: vaultURL,
            limit: max(1, min(limit, 50))
        )
        return results.compactMap { result in
            guard let path = pathResolver.relativePath(for: result.fileURL),
                  let deepLink = NotoDeepLink.webURL(vaultRelativePath: path)?.absoluteString else {
                return nil
            }
            return NotoSearchHit(
                path: path,
                deepLink: deepLink,
                title: result.title,
                breadcrumb: result.breadcrumb,
                snippet: result.snippet,
                lineStart: result.lineStart,
                kind: result.kind == .section ? "section" : "note",
                score: result.score
            )
        }
    }

    public func read(
        relativePath: String,
        startLine: Int? = nil,
        endLine: Int? = nil,
        maxCharacters: Int = 40_000
    ) throws -> NotoReadResult {
        try validateVault()
        let fileURL = try resolveExistingNote(relativePath)
        guard let deepLink = NotoDeepLink.webURL(vaultRelativePath: relativePath)?.absoluteString else {
            throw NotoAgentError.invalidPath(relativePath)
        }
        guard let content = fileSystem.readString(from: fileURL)
            ?? (try? String(contentsOf: fileURL, encoding: .utf8)) else {
            if !fileSystem.isDownloaded(at: fileURL) {
                fileSystem.startDownloading(at: fileURL)
            }
            throw NotoAgentError.readFailed(relativePath)
        }

        let lines = content.components(separatedBy: "\n")
        let total = lines.count
        let lower = max(1, startLine ?? 1)
        let requestedUpper = endLine ?? total
        let upper = min(total, max(lower, requestedUpper))
        guard lower <= total else {
            return NotoReadResult(
                path: relativePath,
                deepLink: deepLink,
                text: "",
                startLine: lower,
                endLine: lower - 1,
                totalLines: total,
                truncated: false
            )
        }

        var text = lines[(lower - 1)..<upper].joined(separator: "\n")
        var truncated = false
        if text.count > maxCharacters {
            text = String(text.prefix(maxCharacters))
            truncated = true
        }
        return NotoReadResult(
            path: relativePath,
            deepLink: deepLink,
            text: text,
            startLine: lower,
            endLine: upper,
            totalLines: total,
            truncated: truncated
        )
    }

    private func idempotentMutation(
        relativePath: String,
        requestID: String,
        date: Date = Date(),
        transform: (String) -> String
    ) throws -> NotoMutationResult {
        let normalizedRequestID = requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRequestID.isEmpty else { throw NotoAgentError.invalidRequestID }
        let fileURL = try resolveExistingNote(relativePath)
        let canonicalPath = try relativeNotePath(for: fileURL)
        let receiptsURL = try ensureReceiptLedger()

        var result: Result<NotoMutationResult, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: receiptsURL,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedReceiptsURL in
            do {
                var ledger = try loadLedger(at: coordinatedReceiptsURL)
                if let receipt = ledger.receipts[normalizedRequestID] {
                    result = .success(try mutationResult(
                        fileURL: try resolveExistingNote(receipt.path),
                        relativePath: receipt.path,
                        changed: false,
                        duplicate: true
                    ))
                    return
                }

                try coordinatedMutate(fileURL: fileURL, date: date, transform: transform)
                ledger.receipts[normalizedRequestID] = Receipt(
                    path: canonicalPath,
                    completedAt: date
                )
                try saveLedger(ledger, at: coordinatedReceiptsURL)
                result = .success(try mutationResult(
                    fileURL: fileURL,
                    relativePath: canonicalPath,
                    changed: true,
                    duplicate: false
                ))
            } catch {
                result = .failure(error)
            }
        }

        if let coordinationError {
            throw NotoAgentError.receiptFailed(coordinationError.localizedDescription)
        }
        let mutation = try result?.get() ?? {
            throw NotoAgentError.receiptFailed("No result from coordinated receipt update.")
        }()

        if mutation.changed {
            _ = try MarkdownSearchIndexer(vaultURL: vaultURL, indexDirectory: indexDirectory)
                .refreshFile(at: fileURL)
        }
        return mutation
    }

    private func coordinatedMutate(
        fileURL: URL,
        date: Date,
        transform: (String) -> String
    ) throws {
        var result: Result<Void, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: fileURL,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                let existing = try String(contentsOf: coordinatedURL, encoding: .utf8)
                let updated = NoteFrontmatter.stampingModified(transform(existing), to: date)
                try updated.write(to: coordinatedURL, atomically: false, encoding: .utf8)
                result = .success(())
            } catch {
                result = .failure(error)
            }
        }

        if let coordinationError {
            throw NotoAgentError.writeFailed("\(fileURL.path): \(coordinationError.localizedDescription)")
        }
        do {
            try result?.get() ?? { throw NotoAgentError.writeFailed(fileURL.path) }()
        } catch let error as NotoAgentError {
            throw error
        } catch {
            throw NotoAgentError.writeFailed("\(fileURL.path): \(error.localizedDescription)")
        }
    }

    private func validateVault() throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: vaultURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NotoAgentError.invalidVault(vaultURL.path)
        }
    }

    private func validatedText(_ text: String) throws -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw NotoAgentError.invalidText }
        return normalized
    }

    private func resolveExistingNote(_ relativePath: String) throws -> URL {
        guard let candidate = pathResolver.noteURL(forVaultRelativePath: relativePath) else {
            throw NotoAgentError.invalidPath(relativePath)
        }
        let resolvedRoot = vaultURL.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedCandidate.path.hasPrefix(resolvedRoot + "/") else {
            throw NotoAgentError.invalidPath(relativePath)
        }
        guard fileSystem.fileExists(at: resolvedCandidate) else {
            throw NotoAgentError.noteNotFound(relativePath)
        }
        return resolvedCandidate
    }

    private func relativeNotePath(for fileURL: URL) throws -> String {
        guard let path = pathResolver.relativePath(for: fileURL), !path.isEmpty else {
            throw NotoAgentError.invalidPath(fileURL.path)
        }
        return path
    }

    private func mutationResult(
        fileURL: URL,
        relativePath: String,
        changed: Bool,
        duplicate: Bool
    ) throws -> NotoMutationResult {
        guard let content = fileSystem.readString(from: fileURL)
            ?? (try? String(contentsOf: fileURL, encoding: .utf8)) else {
            throw NotoAgentError.readFailed(relativePath)
        }
        let modifiedAt = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? Date()
        return NotoMutationResult(
            path: relativePath,
            deepLink: try deepLink(for: relativePath),
            title: VaultMarkdown.displayTitle(for: fileURL, content: content),
            changed: changed,
            duplicate: duplicate,
            modifiedAt: modifiedAt
        )
    }

    private func deepLink(for relativePath: String) throws -> String {
        guard let url = NotoDeepLink.webURL(vaultRelativePath: relativePath) else {
            throw NotoAgentError.invalidPath(relativePath)
        }
        return url.absoluteString
    }

    private func ensureReceiptLedger() throws -> URL {
        let directory = vaultURL.appendingPathComponent(".noto", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let ledgerURL = directory.appendingPathComponent("agent-receipts.json")
        if !fileManager.fileExists(atPath: ledgerURL.path) {
            let empty = try JSONEncoder.receipts.encode(ReceiptLedger())
            try empty.write(to: ledgerURL, options: .atomic)
        }
        return ledgerURL
    }

    private func loadLedger(at url: URL) throws -> ReceiptLedger {
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return ReceiptLedger() }
        return try JSONDecoder.receipts.decode(ReceiptLedger.self, from: data)
    }

    private func saveLedger(_ ledger: ReceiptLedger, at url: URL) throws {
        let data = try JSONEncoder.receipts.encode(ledger)
        try data.write(to: url, options: .atomic)
    }

    static func appendingMarkdownBlock(_ block: String, to markdown: String) -> String {
        var result = markdown.trimmingCharacters(in: .newlines)
        result += "\n\n\(block)\n"
        return result
    }

    static func appendingDailyCapture(_ text: String, time: String, to markdown: String) -> String {
        let parts = text.components(separatedBy: "\n")
        let continuation = parts.dropFirst().map { "  \($0)" }.joined(separator: "\n")
        let bullet = "- \(time) — \(parts[0])" + (continuation.isEmpty ? "" : "\n\(continuation)")
        let lines = markdown.components(separatedBy: "\n")

        guard let headingIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "## Captures"
        }) else {
            return markdown.trimmingCharacters(in: .newlines)
                + "\n\n## Captures\n\n\(bullet)\n"
        }

        let nextHeading = lines.indices.dropFirst(headingIndex + 1).first { index in
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            return line.hasPrefix("# ") || line.hasPrefix("## ")
        }
        var updated = lines
        let insertionIndex = nextHeading ?? updated.endIndex
        updated.insert(contentsOf: [bullet, ""], at: insertionIndex)
        return updated.joined(separator: "\n")
    }

    private static func captureTimeFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }
}

private struct ReceiptLedger: Codable {
    var receipts: [String: Receipt] = [:]
}

private struct Receipt: Codable {
    let path: String
    let completedAt: Date
}

private extension JSONEncoder {
    static var receipts: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var receipts: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
