//
//  HNSWIndex.swift
//  NotoHNSW
//
//  Wraps usearch with UUID-to-UInt64 key mapping via VectorKeyStore.
//  Provides add/remove/search operations for 384-dim cosine similarity vectors.
//

#if canImport(USearch)
import Foundation
import NotoEmbedding
import USearch
import os.log

private let logger = Logger(subsystem: "com.noto", category: "HNSWIndex")

public final class HNSWIndex {

    private let index: USearchIndex
    private let indexPath: URL
    private let vectorKeyStore: VectorKeyStore
    private var reservedCapacity: Int = 0
    private static let reserveGrowthFactor = 2
    private static let initialReserveCapacity = 256

    /// Number of vectors currently in the index.
    public var count: Int {
        get throws {
            try index.count
        }
    }

    /// Creates or loads an HNSW index at the given path.
    public init(path: URL, vectorKeyStore: VectorKeyStore) {
        self.indexPath = path
        self.vectorKeyStore = vectorKeyStore

        // Create index with spec: cosine metric, 384 dims, connectivity 16, F16 quantization
        do {
            self.index = try USearchIndex.make(
                metric: .cos,
                dimensions: UInt32(EmbeddingModel.dimensions),
                connectivity: 16,
                quantization: .f16
            )
        } catch {
            logger.error("Failed to create USearch index: \(error)")
            // This is fatal -- create a minimal fallback that will fail on use
            self.index = try! USearchIndex.make(
                metric: .cos,
                dimensions: UInt32(EmbeddingModel.dimensions),
                connectivity: 16,
                quantization: .f16
            )
        }

        // Load existing index if present
        if FileManager.default.fileExists(atPath: path.path) {
            do {
                try index.load(path: path.path)
                let cnt = try index.count
                reservedCapacity = cnt
                logger.info("Loaded HNSW index with \(cnt) vectors from \(path.path)")
            } catch {
                logger.error("Failed to load HNSW index: \(error). Starting fresh.")
            }
        }
    }

    /// Ensures the index has enough reserved capacity for at least one more vector.
    private func ensureCapacity() throws {
        let currentCount = try index.count
        if currentCount >= reservedCapacity {
            let newCapacity = max(Self.initialReserveCapacity, reservedCapacity * Self.reserveGrowthFactor)
            try index.reserve(UInt32(newCapacity))
            reservedCapacity = newCapacity
        }
    }

    /// Converts a UUID to a deterministic UInt64 key using the first 8 bytes.
    public static func uuidToKey(_ uuid: UUID) -> UInt64 {
        let bytes = uuid.uuid
        return UInt64(bytes.0)
            | (UInt64(bytes.1) << 8)
            | (UInt64(bytes.2) << 16)
            | (UInt64(bytes.3) << 24)
            | (UInt64(bytes.4) << 32)
            | (UInt64(bytes.5) << 40)
            | (UInt64(bytes.6) << 48)
            | (UInt64(bytes.7) << 56)
    }

    /// Adds a vector for the given block ID. Updates the vector_key_map.
    public func add(blockId: UUID, vector: [Float]) async {
        let key = Self.uuidToKey(blockId)

        // Remove existing entry if present (usearch doesn't deduplicate by default)
        if (try? index.contains(key: key)) == true {
            _ = try? index.remove(key: key)
        }

        do {
            try ensureCapacity()
            try index.add(key: key, vector: vector)
            await vectorKeyStore.setVectorKey(blockId: blockId, key: key)
        } catch {
            logger.error("Failed to add vector for block \(blockId): \(error)")
        }
    }

    /// Removes a vector for the given block ID.
    public func remove(blockId: UUID) async {
        let key = Self.uuidToKey(blockId)
        do {
            _ = try index.remove(key: key)
            await vectorKeyStore.removeVectorKey(blockId: blockId)
        } catch {
            logger.error("Failed to remove vector for block \(blockId): \(error)")
        }
    }

    /// Searches for the nearest vectors to the query vector.
    /// Returns (blockId, distance) pairs sorted by ascending distance.
    public func search(vector: [Float], count: Int) async -> [(blockId: UUID, distance: Float)] {
        guard count > 0 else { return [] }

        do {
            let (keys, distances) = try index.search(vector: vector, count: count)

            var results: [(UUID, Float)] = []
            results.reserveCapacity(keys.count)

            for i in 0..<keys.count {
                if let uuid = await vectorKeyStore.getBlockId(vectorKey: keys[i]) {
                    results.append((uuid, distances[i]))
                }
            }

            return results
        } catch {
            logger.error("HNSW search failed: \(error)")
            return []
        }
    }

    /// Checks if a vector exists for the given block ID.
    public func contains(blockId: UUID) -> Bool {
        let key = Self.uuidToKey(blockId)
        return (try? index.contains(key: key)) ?? false
    }

    /// Persists the index to disk.
    public func save() throws {
        // Ensure parent directory exists
        let dir = indexPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        try index.save(path: indexPath.path)
        let cnt = try index.count
        logger.info("Saved HNSW index (\(cnt) vectors) to \(self.indexPath.path)")
    }

    /// Clears all vectors from the index (for rebuild).
    public func clear() throws {
        try index.clear()
    }

    /// Rebuilds the index from existing BlockEmbedding records (no CoreML needed).
    public func rebuild(from embeddings: [(blockId: UUID, vector: [Float])]) async throws {
        try index.clear()
        reservedCapacity = 0
        if !embeddings.isEmpty {
            try index.reserve(UInt32(embeddings.count))
            reservedCapacity = embeddings.count
        }
        for emb in embeddings {
            await add(blockId: emb.blockId, vector: emb.vector)
        }
        try save()
        let cnt = try index.count
        logger.info("Rebuilt HNSW index with \(cnt) vectors")
    }
}
#endif
