import Accelerate
import Foundation

/// Brute-force exact cosine search over every stored chunk vector.
///
/// All vectors are L2-normalized, so cosine = dot product, and the whole scan
/// is one matrix-vector multiply. Measured ~0.2 ms at 10k×512 on Apple
/// Silicon; an ANN index is unjustified below hundreds of thousands of chunks
/// (see the plan doc). The in-memory matrix is cached and reloaded only when
/// the store's generation counter changes.
public final class SemanticSearcher: @unchecked Sendable {
    private let indexDirectory: URL
    private let lock = NSLock()
    private var cache: Cache?

    private struct Cache {
        let generation: Int
        let dims: Int
        let matrix: [Float]
        let chunks: [SemanticIndexStore.ChunkRecord]
    }

    public init(indexDirectory: URL) {
        self.indexDirectory = indexDirectory
    }

    public convenience init(vaultURL: URL) {
        self.init(indexDirectory: MarkdownSearchIndexer.defaultIndexDirectory(for: vaultURL))
    }

    /// Top-`limit` chunks by cosine similarity to an (L2-normalized) query
    /// vector. `minScore` drops vibes-only tail matches.
    public func search(queryVector: [Float], limit: Int = 50, minScore: Float = 0.2) throws -> [SemanticSearchHit] {
        guard !queryVector.isEmpty, limit > 0 else { return [] }
        guard let cache = try loadCacheIfNeeded() else { return [] }
        let rowCount = cache.chunks.count
        guard rowCount > 0 else { return [] }
        guard cache.dims == queryVector.count else {
            throw SearchIndexStoreError.sqlite(
                "query dims \(queryVector.count) != index dims \(cache.dims)"
            )
        }

        // (rowCount × dims) · (dims × 1) → (rowCount × 1) in a single
        // Accelerate call; memory-bandwidth-bound, milliseconds at 100k rows.
        var scores = [Float](repeating: 0, count: rowCount)
        cache.matrix.withUnsafeBufferPointer { matrix in
            queryVector.withUnsafeBufferPointer { query in
                scores.withUnsafeMutableBufferPointer { output in
                    vDSP_mmul(
                        matrix.baseAddress!, 1,
                        query.baseAddress!, 1,
                        output.baseAddress!, 1,
                        vDSP_Length(rowCount),
                        1,
                        vDSP_Length(cache.dims)
                    )
                }
            }
        }

        var order = Array(scores.indices)
        let k = min(limit, rowCount)
        order.sort { scores[$0] > scores[$1] }

        var hits: [SemanticSearchHit] = []
        hits.reserveCapacity(k)
        for index in order.prefix(k) {
            let score = scores[index]
            guard score >= minScore else { break }
            let chunk = cache.chunks[index]
            hits.append(SemanticSearchHit(
                chunkID: chunk.chunkID,
                noteID: chunk.noteID,
                relativePath: chunk.relativePath,
                noteTitle: chunk.noteTitle,
                heading: chunk.heading,
                snippet: chunk.snippet,
                lineStart: chunk.lineStart,
                score: score,
                kind: chunk.kind,
                imagePath: chunk.imagePath
            ))
        }
        return hits
    }

    /// Drops the cached matrix; next search reloads from disk.
    public func invalidate() {
        lock.lock()
        cache = nil
        lock.unlock()
    }

    private func loadCacheIfNeeded() throws -> Cache? {
        let databaseURL = indexDirectory.appendingPathComponent("semantic.sqlite")
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }

        let store = try SemanticIndexStore(indexDirectory: indexDirectory)
        let generation = try store.generation()

        lock.lock()
        if let cache, cache.generation == generation {
            lock.unlock()
            return cache
        }
        lock.unlock()

        let (dims, matrix, chunks) = try store.allEmbeddings()
        let fresh = Cache(generation: generation, dims: dims, matrix: matrix, chunks: chunks)

        lock.lock()
        cache = fresh
        lock.unlock()
        return fresh
    }
}
