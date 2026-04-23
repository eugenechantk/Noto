import Foundation

public struct SourceNoteSyncResult: Sendable {
    public var created: Int
    public var updated: Int
    public var skippedDeleted: Int
    public var skippedChildDocuments: Int
    public var dryRun: Bool
    public var sourceDirectoryURL: URL
}

public struct SourceNoteSyncEngine: Sendable {
    public static let defaultSourceDirectory = "Captures"

    public init() {}

    public func sync(
        books: [ReadwiseBook],
        vaultURL: URL,
        sourceDirectory: String = Self.defaultSourceDirectory,
        dryRun: Bool = false,
        syncedAt: Date = Date()
    ) throws -> SourceNoteSyncResult {
        let vaultURL = vaultURL.standardizedFileURL
        let sourceDirectoryURL = resolveSourceDirectory(sourceDirectory, vaultURL: vaultURL)
        var state = try SyncStateStore.load(from: vaultURL)
        var created = 0
        var updated = 0
        var skippedDeleted = 0

        if !dryRun {
            try FileManager.default.createDirectory(at: sourceDirectoryURL, withIntermediateDirectories: true)
        }

        for book in books {
            guard !book.isDeleted else {
                skippedDeleted += 1
                continue
            }

            let canonicalKey = book.canonicalKey
            let existingURL = existingNoteURL(
                for: canonicalKey,
                state: state,
                vaultURL: vaultURL,
                sourceDirectoryURL: sourceDirectoryURL
            )
            let noteURL = existingURL ?? nextAvailableNoteURL(
                for: book.displayTitle,
                in: sourceDirectoryURL
            )
            let id = existingURL.flatMap { parseExistingID(at: $0) } ?? UUID()
            let existingMarkdown = existingURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            let markdown: String

            if let existingMarkdown {
                markdown = SourceNoteRenderer.renderUpdatedNote(
                    existingMarkdown: existingMarkdown,
                    book: book,
                    capturedAt: syncedAt
                )
                updated += 1
            } else {
                markdown = SourceNoteRenderer.renderNewNote(
                    for: book,
                    id: id,
                    createdAt: syncedAt,
                    capturedAt: syncedAt
                )
                created += 1
            }

            let generatedHash = SourceNoteRenderer.generatedBlockHash(
                for: SourceNoteRenderer.generatedBlock(for: book, capturedAt: syncedAt)
            )
            let relativePath = relativePath(for: noteURL, base: vaultURL)
            state.sources[canonicalKey] = SourceMapping(
                noteID: id.uuidString,
                relativePath: relativePath,
                generatedBlockHash: generatedHash,
                readwiseUserBookID: book.userBookID,
                updatedAt: ISO8601DateFormatter.noto.string(from: syncedAt)
            )

            if !dryRun {
                try markdown.write(to: noteURL, atomically: true, encoding: .utf8)
            }
        }

        state.lastSuccessfulSyncAt = ISO8601DateFormatter.noto.string(from: syncedAt)
        if !dryRun {
            try SyncStateStore.save(state, to: vaultURL)
        }

        return SourceNoteSyncResult(
            created: created,
            updated: updated,
            skippedDeleted: skippedDeleted,
            skippedChildDocuments: 0,
            dryRun: dryRun,
            sourceDirectoryURL: sourceDirectoryURL
        )
    }

    public func syncReaderDocuments(
        _ documents: [ReaderDocument],
        matchedReadwiseBooks: [String: ReadwiseBook] = [:],
        vaultURL: URL,
        sourceDirectory: String = Self.defaultSourceDirectory,
        dryRun: Bool = false,
        syncedAt: Date = Date()
    ) throws -> SourceNoteSyncResult {
        let vaultURL = vaultURL.standardizedFileURL
        let sourceDirectoryURL = resolveSourceDirectory(sourceDirectory, vaultURL: vaultURL)
        var state = try SyncStateStore.load(from: vaultURL)
        var created = 0
        var updated = 0
        var skippedChildDocuments = 0

        if !dryRun {
            try FileManager.default.createDirectory(at: sourceDirectoryURL, withIntermediateDirectories: true)
        }

        for document in documents {
            guard document.isTopLevelDocument else {
                skippedChildDocuments += 1
                continue
            }

            let canonicalKey = document.canonicalKey
            let existingURL = existingNoteURL(
                for: canonicalKey,
                state: state,
                vaultURL: vaultURL,
                sourceDirectoryURL: sourceDirectoryURL
            )
            let noteURL = existingURL ?? nextAvailableNoteURL(
                for: document.displayTitle,
                in: sourceDirectoryURL
            )
            let id = existingURL.flatMap { parseExistingID(at: $0) } ?? UUID()
            let existingMarkdown = existingURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            let matchedBook = matchedReadwiseBooks[document.id]
            let markdown: String

            if let existingMarkdown {
                if let matchedBook {
                    markdown = SourceNoteRenderer.renderUpdatedNote(
                        existingMarkdown: existingMarkdown,
                        document: document,
                        matchedBook: matchedBook,
                        capturedAt: syncedAt
                    )
                } else {
                    markdown = SourceNoteRenderer.renderUpdatedNote(
                        existingMarkdown: existingMarkdown,
                        document: document,
                        capturedAt: syncedAt
                    )
                }
                updated += 1
            } else {
                if let matchedBook {
                    markdown = SourceNoteRenderer.renderNewNote(
                        for: document,
                        matchedBook: matchedBook,
                        id: id,
                        createdAt: syncedAt,
                        capturedAt: syncedAt
                    )
                } else {
                    markdown = SourceNoteRenderer.renderNewNote(
                        for: document,
                        id: id,
                        createdAt: syncedAt,
                        capturedAt: syncedAt
                    )
                }
                created += 1
            }

            let generatedBlock = matchedBook.map {
                SourceNoteRenderer.generatedBlock(for: document, matchedBook: $0, capturedAt: syncedAt)
            } ?? SourceNoteRenderer.generatedBlock(for: document, capturedAt: syncedAt)
            let generatedHash = SourceNoteRenderer.generatedBlockHash(for: generatedBlock)
            state.sources[canonicalKey] = SourceMapping(
                noteID: id.uuidString,
                relativePath: relativePath(for: noteURL, base: vaultURL),
                generatedBlockHash: generatedHash,
                readwiseUserBookID: matchedBook?.userBookID,
                readerDocumentID: document.id,
                updatedAt: ISO8601DateFormatter.noto.string(from: syncedAt)
            )

            if !dryRun {
                try markdown.write(to: noteURL, atomically: true, encoding: .utf8)
            }
        }

        state.lastSuccessfulReaderSyncAt = ISO8601DateFormatter.noto.string(from: syncedAt)
        if !dryRun {
            try SyncStateStore.save(state, to: vaultURL)
        }

        return SourceNoteSyncResult(
            created: created,
            updated: updated,
            skippedDeleted: 0,
            skippedChildDocuments: skippedChildDocuments,
            dryRun: dryRun,
            sourceDirectoryURL: sourceDirectoryURL
        )
    }

    private func resolveSourceDirectory(_ sourceDirectory: String, vaultURL: URL) -> URL {
        if sourceDirectory.hasPrefix("/") {
            return URL(fileURLWithPath: sourceDirectory, isDirectory: true).standardizedFileURL
        }
        return vaultURL.appendingPathComponent(sourceDirectory, isDirectory: true).standardizedFileURL
    }

    private func existingNoteURL(
        for canonicalKey: String,
        state: ReadwiseSyncState,
        vaultURL: URL,
        sourceDirectoryURL: URL
    ) -> URL? {
        if let relativePath = state.sources[canonicalKey]?.relativePath {
            let mappedURL = vaultURL.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: mappedURL.path) {
                return mappedURL
            }
        }

        return scanForExistingNote(canonicalKey: canonicalKey, in: sourceDirectoryURL)
    }

    private func scanForExistingNote(canonicalKey: String, in directoryURL: URL) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let quotedNeedle = "canonical_key: \"\(canonicalKey)\""
        let plainNeedle = "canonical_key: \(canonicalKey)"
        for fileURL in files where fileURL.pathExtension == "md" {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            if content.contains(quotedNeedle) || content.contains(plainNeedle) {
                return fileURL
            }
        }
        return nil
    }

    private func nextAvailableNoteURL(for title: String, in directoryURL: URL) -> URL {
        let filename = Self.sanitizeFilename(title).nonEmpty ?? "Untitled Source"
        var candidate = directoryURL
            .appendingPathComponent(filename)
            .appendingPathExtension("md")
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            return candidate
        }

        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directoryURL
                .appendingPathComponent("\(filename) (\(counter))")
                .appendingPathExtension("md")
            counter += 1
        }
        return candidate
    }

    private func parseExistingID(at url: URL) -> UUID? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("id:") else { continue }
            let value = trimmed.dropFirst(3)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return UUID(uuidString: value)
        }
        return nil
    }

    private func relativePath(for fileURL: URL, base vaultURL: URL) -> String {
        let filePath = fileURL.standardizedFileURL.path
        let basePath = vaultURL.standardizedFileURL.path
        if filePath.hasPrefix(basePath + "/") {
            return String(filePath.dropFirst(basePath.count + 1))
        }
        return fileURL.lastPathComponent
    }

    public static func sanitizeFilename(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?\"<>|*")
        var sanitized = name.components(separatedBy: illegal).joined()
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if sanitized.count > 100 {
            sanitized = String(sanitized.prefix(100)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return sanitized
    }
}
