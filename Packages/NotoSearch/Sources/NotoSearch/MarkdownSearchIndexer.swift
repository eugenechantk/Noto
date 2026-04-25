import Foundation

public struct MarkdownSearchIndexer: Sendable {
    public let vaultURL: URL
    public let indexDirectory: URL

    private let extractor: MarkdownSearchDocumentExtractor

    public init(vaultURL: URL, indexDirectory: URL? = nil) {
        self.vaultURL = vaultURL.standardizedFileURL
        self.indexDirectory = indexDirectory ?? vaultURL.appendingPathComponent(".noto", isDirectory: true)
        self.extractor = MarkdownSearchDocumentExtractor(vaultURL: vaultURL)
    }

    public func openStore() throws -> SearchIndexStore {
        try SearchIndexStore(indexDirectory: indexDirectory)
    }

    public func scanDocuments() throws -> [(document: SearchDocument, fileModifiedAt: Date)] {
        let files = try markdownFiles(in: vaultURL)
        return try files.map { fileURL in
            let modifiedAt = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return (try extractor.extract(fileURL: fileURL), modifiedAt)
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
        let documents = try scanDocuments()
        let store = try openStore()
        let catalog = Dictionary(uniqueKeysWithValues: try store.noteCatalog().map { ($0.relativePath, $0.contentHash) })
        var upserted = 0

        for entry in documents where catalog[entry.document.relativePath] != entry.document.contentHash {
            try store.upsert(entry.document, fileModifiedAt: entry.fileModifiedAt)
            upserted += 1
        }

        let deleted = try store.deleteMissing(existingRelativePaths: Set(documents.map(\.document.relativePath)))
        let stats = try store.stats()
        return SearchIndexRefreshResult(scanned: documents.count, upserted: upserted, deleted: deleted, stats: stats)
    }

    private func markdownFiles(in rootURL: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
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
            files.append(url.standardizedFileURL)
        }

        return files.sorted { lhs, rhs in
            SearchUtilities.relativePath(for: lhs, in: rootURL)
                .localizedCaseInsensitiveCompare(SearchUtilities.relativePath(for: rhs, in: rootURL)) == .orderedAscending
        }
    }
}
