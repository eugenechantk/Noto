//
//  EmbeddingIndexer.swift
//  NotoHNSW
//
//  Processes dirty blocks through the embedding pipeline:
//  strip markdown -> check word count -> check content hash -> embed -> HNSW insert.
//

#if canImport(USearch)
import CryptoKit
import Foundation
import NotoCore
import NotoDirtyTracker
import NotoEmbedding
import NotoModels
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.noto", category: "EmbeddingIndexer")

public final class EmbeddingIndexer {

    public let embeddingModel: EmbeddingModel
    public let hnswIndex: HNSWIndex
    public let modelContext: ModelContext

    private static let minimumWordCount = 3
    private static let batchSaveInterval = 50

    public init(embeddingModel: EmbeddingModel, hnswIndex: HNSWIndex, modelContext: ModelContext) {
        self.embeddingModel = embeddingModel
        self.hnswIndex = hnswIndex
        self.modelContext = modelContext
    }

    /// Processes a batch of dirty blocks (called during flush).
    public func processDirtyBlocks(blockIds: [(UUID, DirtyOperation)]) async {
        var processedCount = 0

        for (blockId, operation) in blockIds {
            switch operation {
            case .delete:
                await handleDelete(blockId: blockId)

            case .upsert:
                await handleUpsert(blockId: blockId)
            }

            processedCount += 1
            if processedCount % Self.batchSaveInterval == 0 {
                try? modelContext.save()
            }
        }

        // Final save
        try? modelContext.save()

        // Persist HNSW index
        do {
            try hnswIndex.save()
        } catch {
            logger.error("Failed to save HNSW index after processing: \(error)")
        }

        logger.info("Processed \(blockIds.count) dirty blocks for embedding")
    }

    /// Builds embeddings for all blocks that don't have one yet (first launch).
    public func buildAll(progressHandler: ((Int, Int) -> Void)? = nil) async {
        let descriptor = FetchDescriptor<Block>(
            predicate: #Predicate<Block> { block in
                block.isArchived == false && block.embedding == nil
            }
        )

        let blocks: [Block]
        do {
            blocks = try modelContext.fetch(descriptor)
        } catch {
            logger.error("buildAll fetch failed: \(error)")
            return
        }

        let total = blocks.count
        guard total > 0 else {
            logger.info("buildAll: no blocks to embed")
            return
        }

        logger.info("buildAll: embedding \(total) blocks")
        var completed = 0

        for block in blocks {
            let plainText = PlainTextExtractor.plainText(from: block.content)
            let wordCount = plainText.split(separator: " ").count

            if wordCount < Self.minimumWordCount {
                completed += 1
                if completed % Self.batchSaveInterval == 0 {
                    progressHandler?(completed, total)
                }
                continue
            }

            let hash = sha256(plainText)

            do {
                let vector = try embeddingModel.embed(plainText)
                await hnswIndex.add(blockId: block.id, vector: vector)

                let embedding = BlockEmbedding(
                    block: block,
                    embedding: vector,
                    modelVersion: EmbeddingModel.modelVersion,
                    contentHash: hash
                )
                modelContext.insert(embedding)
            } catch {
                logger.error("buildAll embed failed for block \(block.id): \(error)")
            }

            completed += 1
            if completed % Self.batchSaveInterval == 0 {
                try? modelContext.save()
                progressHandler?(completed, total)
            }
        }

        try? modelContext.save()

        do {
            try hnswIndex.save()
        } catch {
            logger.error("buildAll HNSW save failed: \(error)")
        }

        progressHandler?(completed, total)
        logger.info("buildAll complete: embedded \(completed)/\(total) blocks")
    }

    /// Rebuilds HNSW index from existing BlockEmbedding records (no CoreML needed).
    public func rebuildIndex() async {
        let descriptor = FetchDescriptor<BlockEmbedding>()
        let embeddings: [BlockEmbedding]
        do {
            embeddings = try modelContext.fetch(descriptor)
        } catch {
            logger.error("rebuildIndex fetch failed: \(error)")
            return
        }

        let pairs = embeddings.compactMap { emb -> (blockId: UUID, vector: [Float])? in
            guard let block = emb.block else { return nil }
            return (blockId: block.id, vector: emb.embedding)
        }

        do {
            try await hnswIndex.rebuild(from: pairs)
        } catch {
            logger.error("rebuildIndex failed: \(error)")
        }
    }

    // MARK: - Private

    private func handleDelete(blockId: UUID) async {
        await hnswIndex.remove(blockId: blockId)

        // Delete BlockEmbedding if it exists
        let descriptor = FetchDescriptor<BlockEmbedding>(
            predicate: #Predicate<BlockEmbedding> { emb in
                emb.block?.id == blockId
            }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
    }

    private func handleUpsert(blockId: UUID) async {
        // Fetch the block
        let blockDescriptor = FetchDescriptor<Block>(
            predicate: #Predicate<Block> { $0.id == blockId }
        )
        guard let block = try? modelContext.fetch(blockDescriptor).first else {
            return // block not found, skip
        }

        let plainText = PlainTextExtractor.plainText(from: block.content)
        let wordCount = plainText.split(separator: " ").count

        // Fetch existing embedding
        let embDescriptor = FetchDescriptor<BlockEmbedding>(
            predicate: #Predicate<BlockEmbedding> { emb in
                emb.block?.id == blockId
            }
        )
        let existingEmbedding = try? modelContext.fetch(embDescriptor).first

        // Skip short blocks
        if wordCount < Self.minimumWordCount {
            if let existing = existingEmbedding {
                await hnswIndex.remove(blockId: blockId)
                modelContext.delete(existing)
            }
            return
        }

        // Check content hash
        let hash = sha256(plainText)
        if let existing = existingEmbedding, existing.contentHash == hash {
            return // content unchanged, skip
        }

        // Generate embedding
        let vector: [Float]
        do {
            vector = try embeddingModel.embed(plainText)
        } catch {
            logger.error("Failed to embed block \(blockId): \(error)")
            return
        }

        // Insert/update HNSW
        await hnswIndex.add(blockId: block.id, vector: vector)

        // Create or update BlockEmbedding
        if let existing = existingEmbedding {
            existing.embedding = vector
            existing.contentHash = hash
            existing.generatedAt = Date()
        } else {
            let embedding = BlockEmbedding(
                block: block,
                embedding: vector,
                modelVersion: EmbeddingModel.modelVersion,
                contentHash: hash
            )
            modelContext.insert(embedding)
        }
    }

    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
#endif
