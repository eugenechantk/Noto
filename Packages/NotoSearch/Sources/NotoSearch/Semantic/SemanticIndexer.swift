import Foundation
import os.log

private let semanticLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.noto.NotoSearch",
    category: "SemanticIndexer"
)

/// Keeps the semantic index in sync with the keyword index.
///
/// The FTS catalog in `search.sqlite` is the authority on which notes exist and
/// what their current content hash is. The semantic indexer diffs that catalog
/// against `semantic.sqlite`, re-extracts only changed notes, and re-embeds
/// only chunks whose (model version + text) hash is new. If `search.sqlite`
/// doesn't exist yet, semantic refresh is a graceful no-op — embeddings always
/// trail the keyword index, never lead it.
public struct SemanticIndexer: Sendable {
    public let vaultURL: URL
    public let indexDirectory: URL
    private let embedding: any TextEmbedding
    private let chunker: SemanticChunker
    private let extractor: MarkdownSearchDocumentExtractor
    private let describer: (any ImageDescribing)?
    private let imageFetcher: (any RemoteImageFetching)?
    private let embedBatchSize = 32
    private let maxImagesPerNote = 12
    private let maxOCRTokens = 350

    public init(
        vaultURL: URL,
        embedding: any TextEmbedding,
        indexDirectory: URL? = nil,
        maxTokensPerChunk: Int = 400,
        describer: (any ImageDescribing)? = VisionImageDescriber(),
        imageFetcher: (any RemoteImageFetching)? = CachedRemoteImageFetcher()
    ) {
        self.vaultURL = vaultURL.standardizedFileURL
        self.indexDirectory = indexDirectory ?? MarkdownSearchIndexer.defaultIndexDirectory(for: self.vaultURL)
        self.embedding = embedding
        self.chunker = SemanticChunker(modelVersion: embedding.modelVersion, maxTokensPerChunk: maxTokensPerChunk)
        self.extractor = MarkdownSearchDocumentExtractor(vaultURL: self.vaultURL)
        self.describer = describer
        self.imageFetcher = imageFetcher
    }

    public func openStore() throws -> SemanticIndexStore {
        try SemanticIndexStore(indexDirectory: indexDirectory)
    }

    /// Diff the keyword index catalog against the semantic index and close the
    /// gap. `shouldContinue` is polled between notes so a long initial embed
    /// can be cancelled; completed notes stay persisted either way.
    @discardableResult
    public func refreshFromSearchIndex(
        shouldContinue: @Sendable () -> Bool = { true },
        onProgress: (@Sendable (_ processed: Int, _ total: Int) -> Void)? = nil
    ) throws -> SemanticRefreshResult {
        let searchDatabaseURL = indexDirectory.appendingPathComponent("search.sqlite")

        // Bug 018: on a nearly-full device, index + image-cache writes fail in
        // confusing ways (SQLite "disk full", partial rows). Refuse up front
        // with an actionable error instead.
        if let freeBytes = Self.availableCapacity(at: indexDirectory), freeBytes < 150 * 1_024 * 1_024 {
            let freeMB = freeBytes / (1_024 * 1_024)
            throw SearchIndexStoreError.sqlite(
                "Not enough free storage to build the search index (\(freeMB) MB free, 150 MB needed). Free up space and indexing will resume automatically."
            )
        }

        let store = try openStore()

        guard FileManager.default.fileExists(atPath: searchDatabaseURL.path) else {
            return SemanticRefreshResult(
                scannedNotes: 0, refreshedNotes: 0, embeddedChunks: 0,
                reusedChunks: 0, deletedNotes: 0, stats: try store.stats()
            )
        }

        let searchCatalog = try SearchIndexStore(indexDirectory: indexDirectory).noteCatalog()
        let semanticCatalog = Dictionary(
            uniqueKeysWithValues: try store.noteCatalog().map { ($0.noteID, $0) }
        )
        let searchNoteIDs = Set(searchCatalog.map(\.noteID))

        var deletedNotes = 0
        for (noteID, _) in semanticCatalog where !searchNoteIDs.contains(noteID) {
            if try store.deleteNote(noteID: noteID) {
                deletedNotes += 1
            }
        }

        let modelVersion = embedding.modelVersion
        let candidates = searchCatalog.filter { entry in
            guard let existing = semanticCatalog[entry.noteID] else { return true }
            return existing.noteContentHash != entry.contentHash || existing.modelVersion != modelVersion
        }

        var refreshedNotes = 0
        var embeddedChunks = 0
        var reusedChunks = 0
        var consecutiveFailures = 0

        for (processed, entry) in candidates.enumerated() {
            guard shouldContinue() else { break }
            onProgress?(processed, candidates.count)

            // Each note's transient allocations (OCR bitmaps, Vision results,
            // Core ML feature buffers, SQLite strings) drain here instead of
            // accumulating across the whole sweep — the long synchronous loop
            // otherwise rides the jetsam ceiling on 4 GB devices (bug 018).
            let outcome: Result<(embedded: Int, reused: Int), Error>? = autoreleasepool {
                let fileURL = vaultURL.appendingPathComponent(entry.relativePath)
                let document: SearchDocument
                do {
                    document = try extractor.extract(fileURL: fileURL)
                } catch {
                    semanticLogger.debug("skip unreadable \(entry.relativePath, privacy: .public)")
                    return nil
                }
                do {
                    return .success(try refreshNote(document: document, fileURL: fileURL, store: store))
                } catch {
                    return .failure(error)
                }
            }

            switch outcome {
            case .success(let counts):
                refreshedNotes += 1
                embeddedChunks += counts.embedded
                reusedChunks += counts.reused
                consecutiveFailures = 0
            case .failure(let error):
                consecutiveFailures += 1
                semanticLogger.error(
                    "embed failed for \(entry.relativePath, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
                // One bad note must not kill a multi-hour sweep: skip it and
                // continue. Only abort when failures are consecutive enough to
                // indicate a systemic problem (model unavailable, disk full) —
                // everything embedded so far is already persisted either way.
                if consecutiveFailures >= 3 {
                    throw error
                }
            case nil:
                break
            }
        }
        onProgress?(candidates.count, candidates.count)

        return SemanticRefreshResult(
            scannedNotes: searchCatalog.count,
            refreshedNotes: refreshedNotes,
            embeddedChunks: embeddedChunks,
            reusedChunks: reusedChunks,
            deletedNotes: deletedNotes,
            stats: try store.stats()
        )
    }

    /// Destroy the semantic store and re-embed everything from the current
    /// keyword catalog.
    @discardableResult
    public func rebuild(
        shouldContinue: @Sendable () -> Bool = { true },
        onProgress: (@Sendable (_ processed: Int, _ total: Int) -> Void)? = nil
    ) throws -> SemanticRefreshResult {
        try openStore().destroy()
        return try refreshFromSearchIndex(shouldContinue: shouldContinue, onProgress: onProgress)
    }

    private func refreshNote(
        document: SearchDocument,
        fileURL: URL,
        store: SemanticIndexStore
    ) throws -> (embedded: Int, reused: Int) {
        let chunks = chunker.chunks(for: document)
        let existingVectors = try store.existingVectors(noteID: document.id)

        var pairs: [(chunk: SemanticChunk, vector: [Float])] = []
        var pending: [SemanticChunk] = []
        var reused = 0

        for chunk in chunks {
            if let vector = existingVectors[chunk.contentHash] {
                pairs.append((chunk, vector))
                reused += 1
            } else {
                pending.append(chunk)
            }
        }

        // Image chunks: described + embedded only when the image bytes (or the
        // describer/model versions) changed; otherwise reused from the store.
        let imageOutcome = imageChunkPairs(document: document, fileURL: fileURL, store: store)
        pairs.append(contentsOf: imageOutcome.reusedPairs)
        reused += imageOutcome.reusedPairs.count
        pending.append(contentsOf: imageOutcome.pendingChunks)

        var embedded = 0
        for batchStart in stride(from: 0, to: pending.count, by: embedBatchSize) {
            let batch = Array(pending[batchStart..<min(batchStart + embedBatchSize, pending.count)])
            let vectors = try embedding.embed(batch.map(\.embeddedText))
            guard vectors.count == batch.count else {
                throw SearchIndexStoreError.sqlite("embedding returned \(vectors.count) vectors for \(batch.count) texts")
            }
            for (chunk, vector) in zip(batch, vectors) {
                pairs.append((chunk, vector))
                embedded += 1
            }
        }

        try store.replaceNote(
            noteID: document.id,
            relativePath: document.relativePath,
            noteTitle: document.title,
            noteContentHash: document.contentHash,
            modelVersion: chunker.modelVersion,
            describerVersion: describer?.describerVersion,
            chunks: pairs
        )
        return (embedded, reused)
    }

    // MARK: - Image chunks

    private func imageChunkPairs(
        document: SearchDocument,
        fileURL: URL,
        store: SemanticIndexStore
    ) -> (reusedPairs: [(chunk: SemanticChunk, vector: [Float])], pendingChunks: [SemanticChunk]) {
        guard let describer else { return ([], []) }
        guard let markdown = try? MarkdownSearchDocumentExtractor.readMarkdown(from: fileURL) else {
            return ([], [])
        }
        let references = MarkdownImageExtractor.references(in: markdown).prefix(maxImagesPerNote)
        guard !references.isEmpty else { return ([], []) }

        let existing = (try? store.existingImageChunks(noteID: document.id)) ?? [:]
        var reusedPairs: [(chunk: SemanticChunk, vector: [Float])] = []
        var pendingChunks: [SemanticChunk] = []
        var seenChunkIDs = Set<UUID>()

        // Resolve all image bytes up front, remote fetches in parallel — the
        // describe/embed stages stay serial, but the network never blocks them
        // one URL at a time (dead links in big vaults made first indexing
        // crawl when fetched inline).
        let resolvedData = prefetchImageData(for: Array(references))

        for reference in references {
            guard let data = resolvedData[reference.target] ?? nil else { continue }
            let invalidationHash = SearchUtilities.contentHash(
                "\(chunker.modelVersion)|\(describer.describerVersion)|\(SearchUtilities.contentHash(data))|\(reference.altText)|\(document.title)"
            )

            if let existingRow = existing[invalidationHash] {
                if seenChunkIDs.insert(existingRow.chunk.id).inserted {
                    reusedPairs.append(existingRow)
                }
                continue
            }

            guard let description = try? describer.describe(imageData: data), !description.isEmpty else {
                continue
            }
            let chunk = imageChunk(
                document: document,
                reference: reference,
                description: description,
                contentHash: invalidationHash
            )
            if seenChunkIDs.insert(chunk.id).inserted {
                pendingChunks.append(chunk)
            }
        }
        return (reusedPairs, pendingChunks)
    }

    private func imageData(for reference: MarkdownImageReference) -> Data? {
        if reference.isRemote {
            guard let url = URL(string: reference.target) else { return nil }
            return imageFetcher?.fetch(url: url)
        }
        let url = vaultURL.appendingPathComponent(reference.target)
        return try? Data(contentsOf: url)
    }

    /// Loads every reference's bytes, running remote fetches on a concurrent
    /// queue (capped width). Local reads are cheap and stay inline.
    private func prefetchImageData(for references: [MarkdownImageReference]) -> [String: Data?] {
        var results = [String: Data?](minimumCapacity: references.count)
        let remote = references.filter(\.isRemote)
        let local = references.filter { !$0.isRemote }

        for reference in local {
            results[reference.target] = imageData(for: reference)
        }
        guard !remote.isEmpty else { return results }

        let lock = NSLock()
        var remoteResults = [String: Data?](minimumCapacity: remote.count)
        DispatchQueue.concurrentPerform(iterations: remote.count) { index in
            let reference = remote[index]
            let data = imageData(for: reference)
            lock.lock()
            remoteResults[reference.target] = data
            lock.unlock()
        }
        for (key, value) in remoteResults {
            results[key] = value
        }
        return results
    }

    private func imageChunk(
        document: SearchDocument,
        reference: MarkdownImageReference,
        description: ImageDescription,
        contentHash: String
    ) -> SemanticChunk {
        let fallbackName = reference.isRemote
            ? (URL(string: reference.target)?.lastPathComponent ?? "image")
            : (reference.target as NSString).lastPathComponent
        let displayName = reference.altText.isEmpty ? fallbackName : reference.altText

        var bodyParts: [String] = []
        if !reference.altText.isEmpty { bodyParts.append(reference.altText) }
        if !description.ocrText.isEmpty {
            bodyParts.append(cappedText(description.ocrText, maxTokens: maxOCRTokens))
        }
        if !description.labels.isEmpty {
            bodyParts.append(description.labels.joined(separator: ", "))
        }
        let body = bodyParts.joined(separator: "\n")
        let header = "\(document.title) > \(displayName)"
        let snippet = description.ocrText.isEmpty
            ? description.labels.joined(separator: ", ")
            : description.ocrText.replacingOccurrences(of: "\n", with: " ")

        return SemanticChunk(
            id: SearchUtilities.stableID(for: "\(document.id.uuidString):image:\(reference.target)"),
            noteID: document.id,
            heading: displayName,
            lineStart: reference.line,
            lineEnd: reference.line,
            embeddedText: "\(header)\n\(body)",
            snippetText: String(snippet.prefix(240)),
            contentHash: contentHash,
            kind: .image,
            imagePath: reference.target
        )
    }

    static func availableCapacity(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    private func cappedText(_ text: String, maxTokens: Int) -> String {
        guard SemanticChunker.estimatedTokens(text) > maxTokens else { return text }
        var lines: [String] = []
        var tokens = 0
        for line in text.components(separatedBy: "\n") {
            let lineTokens = SemanticChunker.estimatedTokens(line)
            if tokens + lineTokens > maxTokens { break }
            lines.append(line)
            tokens += lineTokens
        }
        return lines.isEmpty ? String(text.prefix(1_000)) : lines.joined(separator: "\n")
    }
}
