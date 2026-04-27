import Foundation

public struct MarkdownSearchIndexer: Sendable {
    public let vaultURL: URL
    public let indexDirectory: URL

    private let extractor: MarkdownSearchDocumentExtractor

    public init(vaultURL: URL, indexDirectory: URL? = nil) {
        self.vaultURL = vaultURL.standardizedFileURL
        self.indexDirectory = indexDirectory ?? Self.defaultIndexDirectory(for: self.vaultURL)
        self.extractor = MarkdownSearchDocumentExtractor(vaultURL: vaultURL)
    }

    public static func defaultIndexDirectory(for vaultURL: URL) -> URL {
        let standardizedVaultURL = vaultURL.standardizedFileURL
        let vaultKey = SearchUtilities.contentHash(standardizedVaultURL.path)
        let appSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return appSupportDirectory
            .appendingPathComponent("Noto", isDirectory: true)
            .appendingPathComponent("SearchIndexes", isDirectory: true)
            .appendingPathComponent(vaultKey, isDirectory: true)
    }

    public func openStore() throws -> SearchIndexStore {
        try SearchIndexStore(indexDirectory: indexDirectory)
    }

    public func scanDocuments() throws -> [SearchIndexedDocument] {
        let files = try markdownFiles(in: vaultURL)
        return files.compactMap { file in
            guard file.isAvailableForIndexing else {
                Self.startDownloadingIfNeeded(file.url)
                return nil
            }
            do {
                return try SearchIndexedDocument(
                    document: extractor.extract(fileURL: file.url),
                    fileModifiedAt: file.modifiedAt,
                    fileSize: file.fileSize
                )
            } catch {
                return nil
            }
        }
    }

    @discardableResult
    public func rebuild() throws -> SearchIndexRefreshResult {
        let documents = try scanDocuments()
        let store = try openStore()
        let stats = try store.rebuild(documents: documents)
        return SearchIndexRefreshResult(scanned: documents.count, upserted: documents.count, deleted: 0, stats: stats)
    }

    @discardableResult
    public func refreshChangedFiles() throws -> SearchIndexRefreshResult {
        let files = try markdownFiles(in: vaultURL)
        let store = try openStore()
        let catalog = Dictionary(uniqueKeysWithValues: try store.noteCatalog().map { ($0.relativePath, $0) })
        var upserted = 0

        for file in files {
            if let entry = catalog[file.relativePath],
               entry.fileSize == file.fileSize,
               Self.matchesStoredModifiedDate(entry.fileModifiedAt, file.modifiedAt) {
                continue
            }
            guard file.isAvailableForIndexing else {
                Self.startDownloadingIfNeeded(file.url)
                continue
            }

            let document: SearchDocument
            do {
                document = try extractor.extract(fileURL: file.url)
            } catch {
                continue
            }
            if catalog[file.relativePath]?.contentHash == document.contentHash {
                continue
            }

            try store.upsert(document, fileModifiedAt: file.modifiedAt, fileSize: file.fileSize)
            upserted += 1
        }

        let deleted = try store.deleteMissing(existingRelativePaths: Set(files.map(\.relativePath)))
        let stats = try store.stats()
        return SearchIndexRefreshResult(scanned: files.count, upserted: upserted, deleted: deleted, stats: stats)
    }

    @discardableResult
    public func refreshFile(at fileURL: URL) throws -> SearchIndexStats {
        let normalizedURL = fileURL.standardizedFileURL
        guard normalizedURL.pathExtension.lowercased() == "md",
              isInVault(normalizedURL) else {
            return try openStore().stats()
        }

        guard FileManager.default.fileExists(atPath: normalizedURL.path) else {
            return try removeFile(at: normalizedURL)
        }

        let values = try? normalizedURL.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey,
            .ubiquitousItemDownloadingStatusKey,
        ])
        let isAvailableForIndexing = values?.ubiquitousItemDownloadingStatus.map { $0 == .current } ?? true
        guard isAvailableForIndexing else {
            Self.startDownloadingIfNeeded(normalizedURL)
            return try openStore().stats()
        }

        let document = try extractor.extract(fileURL: normalizedURL)
        let store = try openStore()
        try store.upsert(
            document,
            fileModifiedAt: values?.contentModificationDate ?? Date(),
            fileSize: values?.fileSize ?? 0
        )
        return try store.stats()
    }

    @discardableResult
    public func removeFile(at fileURL: URL) throws -> SearchIndexStats {
        let normalizedURL = fileURL.standardizedFileURL
        guard isInVault(normalizedURL) else {
            return try openStore().stats()
        }

        let relativePath = SearchUtilities.relativePath(for: normalizedURL, in: vaultURL)
        let store = try openStore()
        try store.delete(relativePath: relativePath)
        return try store.stats()
    }

    private func markdownFiles(in rootURL: URL) throws -> [MarkdownFileSnapshot] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .contentModificationDateKey,
                .fileSizeKey,
                .ubiquitousItemDownloadingStatusKey,
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [MarkdownFileSnapshot] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey,
                .contentModificationDateKey,
                .fileSizeKey,
                .ubiquitousItemDownloadingStatusKey,
            ])
            if values?.isDirectory == true {
                if url.lastPathComponent.hasPrefix(".") {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard url.pathExtension.lowercased() == "md",
                  !url.lastPathComponent.hasPrefix(".") else {
                continue
            }
            let normalizedURL = url.standardizedFileURL
            files.append(
                MarkdownFileSnapshot(
                    url: normalizedURL,
                    relativePath: SearchUtilities.relativePath(for: normalizedURL, in: rootURL),
                    modifiedAt: values?.contentModificationDate ?? .distantPast,
                    fileSize: values?.fileSize ?? 0,
                    isAvailableForIndexing: values?.ubiquitousItemDownloadingStatus.map { $0 == .current } ?? true
                )
            )
        }

        return files.sorted { lhs, rhs in
            lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
        }
    }

    private static func matchesStoredModifiedDate(_ stored: Date?, _ current: Date) -> Bool {
        guard let stored else { return false }
        return abs(stored.timeIntervalSince(current)) < 1
    }

    private static func startDownloadingIfNeeded(_ url: URL) {
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            // Non-ubiquitous and provider-backed files can reject this. Indexing
            // should keep going and pick the file up on a later refresh.
        }
    }

    private func isInVault(_ url: URL) -> Bool {
        let vaultPath = vaultURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        return filePath == vaultPath || filePath.hasPrefix(vaultPath + "/")
    }
}

private struct MarkdownFileSnapshot {
    let url: URL
    let relativePath: String
    let modifiedAt: Date
    let fileSize: Int
    let isAvailableForIndexing: Bool
}
