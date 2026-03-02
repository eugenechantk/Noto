//
//  SemanticSearchTests.swift
//  NotoTests
//
//  Tests for semantic search components: WordPieceTokenizer, BertTokenizer,
//  HNSWIndex (synthetic vectors), UUID key mapping.
//

#if canImport(USearch)
import Testing
import Foundation
import SwiftData
import NotoHNSW
import NotoEmbedding
import NotoFTS5
import NotoDirtyTracker
@testable import Noto

// MARK: - Test Helpers

/// Creates a normalized random vector of the given dimension.
func randomVector(dimensions: Int = 384) -> [Float] {
    var v = (0..<dimensions).map { _ in Float.random(in: -1...1) }
    let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
    return v.map { $0 / norm }
}

/// Computes cosine similarity between two vectors.
func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
}

/// Creates a vector biased toward a target vector (for testing nearest-neighbor).
func biasedVector(toward target: [Float], strength: Float = 0.9) -> [Float] {
    let noise = randomVector(dimensions: target.count)
    let v = zip(target, noise).map { $0.0 * strength + $0.1 * (1.0 - strength) }
    let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
    return v.map { $0 / norm }
}

/// Creates a temp VectorKeyStore for testing.
func createTestVectorKeyStore() async -> (VectorKeyStore, URL) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("vector-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let store = VectorKeyStore(directory: tempDir)
    await store.createTablesIfNeeded()
    return (store, tempDir)
}

/// Creates a temp HNSWIndex for testing.
func createTestHNSWIndex() async -> (HNSWIndex, VectorKeyStore, URL) {
    let (store, tempDir) = await createTestVectorKeyStore()
    let indexPath = tempDir.appendingPathComponent("test.usearch")
    let index = HNSWIndex(path: indexPath, vectorKeyStore: store)
    return (index, store, tempDir)
}

// MARK: - UUID Key Mapping Tests

struct UUIDKeyMappingTests {

    @Test
    func deterministic() {
        let uuid = UUID()
        let key1 = HNSWIndex.uuidToKey(uuid)
        let key2 = HNSWIndex.uuidToKey(uuid)
        #expect(key1 == key2)
    }

    @Test
    func distinctKeys() {
        var keys = Set<UInt64>()
        for _ in 0..<1000 {
            let key = HNSWIndex.uuidToKey(UUID())
            keys.insert(key)
        }
        #expect(keys.count == 1000)
    }

    @Test
    func roundTripViaVectorKeyMap() async throws {
        let (store, tempDir) = await createTestVectorKeyStore()
        defer { cleanupTempDir(tempDir) }

        let uuid = UUID()
        let key = HNSWIndex.uuidToKey(uuid)

        await store.setVectorKey(blockId: uuid, key: key)
        let retrieved = await store.getBlockId(vectorKey: key)

        #expect(retrieved == uuid)

        await store.close()
    }
}

// MARK: - VectorKeyStore Tests

struct VectorKeyStoreTests {

    @Test
    func setAndGetVectorKey() async {
        let (store, tempDir) = await createTestVectorKeyStore()
        defer { cleanupTempDir(tempDir) }

        let blockId = UUID()
        let key: UInt64 = 42
        await store.setVectorKey(blockId: blockId, key: key)

        let retrieved = await store.getVectorKey(blockId: blockId)
        #expect(retrieved == key)
        await store.close()
    }

    @Test
    func getBlockIdReverseLookup() async {
        let (store, tempDir) = await createTestVectorKeyStore()
        defer { cleanupTempDir(tempDir) }

        let blockId = UUID()
        let key: UInt64 = 99
        await store.setVectorKey(blockId: blockId, key: key)

        let retrieved = await store.getBlockId(vectorKey: key)
        #expect(retrieved == blockId)
        await store.close()
    }

    @Test
    func removeVectorKey() async {
        let (store, tempDir) = await createTestVectorKeyStore()
        defer { cleanupTempDir(tempDir) }

        let blockId = UUID()
        let key: UInt64 = 77
        await store.setVectorKey(blockId: blockId, key: key)
        await store.removeVectorKey(blockId: blockId)

        let retrieved = await store.getVectorKey(blockId: blockId)
        #expect(retrieved == nil)
        await store.close()
    }

    @Test
    func nonExistentKeyReturnsNil() async {
        let (store, tempDir) = await createTestVectorKeyStore()
        defer { cleanupTempDir(tempDir) }

        let retrieved = await store.getVectorKey(blockId: UUID())
        #expect(retrieved == nil)
        await store.close()
    }
}

// MARK: - HNSW Index Tests (Synthetic Vectors)

struct HNSWIndexTests {

    @Test
    func addAndSearch() async throws {
        let (index, store, tempDir) = await createTestHNSWIndex()
        defer { cleanupTempDir(tempDir) }

        let blockId = UUID()
        let vector = randomVector()

        await index.add(blockId: blockId, vector: vector)

        let results = await index.search(vector: vector, count: 1)
        #expect(results.count == 1)
        #expect(results.first?.blockId == blockId)
        #expect(results.first!.distance < 0.01)

        await store.close()
    }

    @Test
    func kNearest() async throws {
        let (index, store, tempDir) = await createTestHNSWIndex()
        defer { cleanupTempDir(tempDir) }

        let queryVector = randomVector()

        // Insert 9 random vectors
        for _ in 0..<9 {
            await index.add(blockId: UUID(), vector: randomVector())
        }

        // Insert one vector biased toward the query
        let biasedId = UUID()
        await index.add(blockId: biasedId, vector: biasedVector(toward: queryVector))

        let results = await index.search(vector: queryVector, count: 10)
        #expect(!results.isEmpty)
        #expect(results.first?.blockId == biasedId)

        await store.close()
    }

    @Test
    func removeVector() async throws {
        let (index, store, tempDir) = await createTestHNSWIndex()
        defer { cleanupTempDir(tempDir) }

        let blockId = UUID()
        await index.add(blockId: blockId, vector: randomVector())
        #expect(index.contains(blockId: blockId) == true)

        await index.remove(blockId: blockId)
        #expect(index.contains(blockId: blockId) == false)

        await store.close()
    }

    @Test
    func containsCheck() async throws {
        let (index, store, tempDir) = await createTestHNSWIndex()
        defer { cleanupTempDir(tempDir) }

        let blockId = UUID()
        #expect(index.contains(blockId: blockId) == false)

        await index.add(blockId: blockId, vector: randomVector())
        #expect(index.contains(blockId: blockId) == true)

        await store.close()
    }

    @Test
    func saveAndLoad() async throws {
        let (store, tempDir) = await createTestVectorKeyStore()
        defer { cleanupTempDir(tempDir) }

        let indexPath = tempDir.appendingPathComponent("test.usearch")

        let index1 = HNSWIndex(path: indexPath, vectorKeyStore: store)
        var ids: [UUID] = []
        for _ in 0..<100 {
            let id = UUID()
            ids.append(id)
            await index1.add(blockId: id, vector: randomVector())
        }
        try index1.save()

        // Create new index from same path
        let index2 = HNSWIndex(path: indexPath, vectorKeyStore: store)
        let cnt = try index2.count
        #expect(cnt == 100)

        for id in ids.prefix(5) {
            #expect(index2.contains(blockId: id) == true)
        }

        await store.close()
    }

    @Test
    func countAfterRemoval() async throws {
        let (index, store, tempDir) = await createTestHNSWIndex()
        defer { cleanupTempDir(tempDir) }

        var ids: [UUID] = []
        for _ in 0..<5 {
            let id = UUID()
            ids.append(id)
            await index.add(blockId: id, vector: randomVector())
        }

        #expect(try index.count == 5)

        await index.remove(blockId: ids[0])
        await index.remove(blockId: ids[1])

        #expect(try index.count == 3)

        await store.close()
    }

    @Test
    func emptySearch() async throws {
        let (index, store, tempDir) = await createTestHNSWIndex()
        defer { cleanupTempDir(tempDir) }

        let results = await index.search(vector: randomVector(), count: 10)
        #expect(results.isEmpty)

        await store.close()
    }
}

// MARK: - Similarity Threshold Tests

struct SimilarityThresholdTests {

    @Test
    func thresholdFiltersLowSimilarity() async throws {
        let (index, store, tempDir) = await createTestHNSWIndex()
        defer { cleanupTempDir(tempDir) }

        let queryVector = randomVector()

        // Similar vector
        let similarId = UUID()
        await index.add(blockId: similarId, vector: biasedVector(toward: queryVector, strength: 0.99))

        // Opposite vector
        let oppositeId = UUID()
        let oppositeVector: [Float] = queryVector.map { -$0 }
        await index.add(blockId: oppositeId, vector: oppositeVector)

        let results = await index.search(vector: queryVector, count: 10)

        if let similarResult = results.first(where: { $0.blockId == similarId }) {
            let similarity = 1.0 - similarResult.distance
            #expect(similarity >= 0.3)
        }

        if let dissimilarResult = results.first(where: { $0.blockId == oppositeId }) {
            let similarity = 1.0 - dissimilarResult.distance
            #expect(similarity < 0.3)
        }

        await store.close()
    }
}

// MARK: - BertTokenizer Tests

struct BertTokenizerTests {

    static func createTestVocab() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vocab-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let vocabURL = tempDir.appendingPathComponent("vocab.txt")
        let tokens = [
            "[PAD]",    // 0
            "[UNK]",    // 1
            "[CLS]",    // 2
            "[SEP]",    // 3
            "[MASK]",   // 4
            "the",      // 5
            "hello",    // 6
            "world",    // 7
            "a",        // 8
            "is",       // 9
            "test",     // 10
            "##ing",    // 11
            "##s",      // 12
            "un",       // 13
            "##aff",    // 14
            "##able",   // 15
            ",",        // 16
            "!",        // 17
            "short",    // 18
            "cafe",     // 19
        ]
        try tokens.joined(separator: "\n").write(to: vocabURL, atomically: true, encoding: .utf8)
        return vocabURL
    }

    @Test
    func basicTokenization() throws {
        let vocabURL = try Self.createTestVocab()
        defer { try? FileManager.default.removeItem(at: vocabURL.deletingLastPathComponent()) }

        let tokenizer = try BertTokenizer(vocabURL: vocabURL, maxSequenceLength: 32)
        let output = tokenizer.tokenize("hello world")

        #expect(output.inputIds[0] == 2) // [CLS]
        let sepIndex = output.inputIds.firstIndex(of: 3)
        #expect(sepIndex != nil)
    }

    @Test
    func knownTokenIds() throws {
        let vocabURL = try Self.createTestVocab()
        defer { try? FileManager.default.removeItem(at: vocabURL.deletingLastPathComponent()) }

        let tokenizer = try BertTokenizer(vocabURL: vocabURL, maxSequenceLength: 32)
        let output = tokenizer.tokenize("the")

        #expect(output.inputIds[0] == 2)  // [CLS]
        #expect(output.inputIds[1] == 5)  // "the"
        #expect(output.inputIds[2] == 3)  // [SEP]
    }

    @Test
    func punctuationSplit() throws {
        let vocabURL = try Self.createTestVocab()
        defer { try? FileManager.default.removeItem(at: vocabURL.deletingLastPathComponent()) }

        let tokenizer = try BertTokenizer(vocabURL: vocabURL, maxSequenceLength: 32)
        let output = tokenizer.tokenize("hello, world!")

        #expect(output.inputIds[0] == 2)  // [CLS]
        #expect(output.inputIds[1] == 6)  // hello
        #expect(output.inputIds[2] == 16) // ,
        #expect(output.inputIds[3] == 7)  // world
        #expect(output.inputIds[4] == 17) // !
        #expect(output.inputIds[5] == 3)  // [SEP]
    }

    @Test
    func attentionMask() throws {
        let vocabURL = try Self.createTestVocab()
        defer { try? FileManager.default.removeItem(at: vocabURL.deletingLastPathComponent()) }

        let tokenizer = try BertTokenizer(vocabURL: vocabURL, maxSequenceLength: 16)
        let output = tokenizer.tokenize("short")

        // [CLS], short, [SEP] = 3 real tokens
        #expect(output.attentionMask[0] == 1)
        #expect(output.attentionMask[1] == 1)
        #expect(output.attentionMask[2] == 1)
        #expect(output.attentionMask[3] == 0)
        #expect(output.inputIds.count == 16)
        #expect(output.attentionMask.count == 16)
    }

    @Test
    func maxLengthTruncation() throws {
        let vocabURL = try Self.createTestVocab()
        defer { try? FileManager.default.removeItem(at: vocabURL.deletingLastPathComponent()) }

        let tokenizer = try BertTokenizer(vocabURL: vocabURL, maxSequenceLength: 4)
        let output = tokenizer.tokenize("hello world test")

        #expect(output.inputIds.count == 4)
        #expect(output.attentionMask.count == 4)
        #expect(output.inputIds[0] == 2) // [CLS]
        #expect(output.inputIds[3] == 3) // [SEP]
    }

    @Test
    func unicodeHandling() throws {
        let vocabURL = try Self.createTestVocab()
        defer { try? FileManager.default.removeItem(at: vocabURL.deletingLastPathComponent()) }

        let tokenizer = try BertTokenizer(vocabURL: vocabURL, maxSequenceLength: 32)
        let output = tokenizer.tokenize("café")

        #expect(output.inputIds[0] == 2)  // [CLS]
        #expect(output.inputIds[1] == 19) // cafe
        #expect(output.inputIds[2] == 3)  // [SEP]
    }

    @Test
    func subwordSplitting() throws {
        let vocabURL = try Self.createTestVocab()
        defer { try? FileManager.default.removeItem(at: vocabURL.deletingLastPathComponent()) }

        let tokenizer = try BertTokenizer(vocabURL: vocabURL, maxSequenceLength: 32)
        let output = tokenizer.tokenize("unaffable")

        #expect(output.inputIds[0] == 2)  // [CLS]
        #expect(output.inputIds[1] == 13) // un
        #expect(output.inputIds[2] == 14) // ##aff
        #expect(output.inputIds[3] == 15) // ##able
        #expect(output.inputIds[4] == 3)  // [SEP]
    }
}

// MARK: - WordPieceTokenizer Tests

struct WordPieceTokenizerTests {

    @Test
    func knownWord() {
        let vocab: [String: Int] = ["hello": 1, "world": 2, "[UNK]": 0]
        let wp = WordPieceTokenizer(vocab: vocab)

        let result = wp.tokenize(word: "hello")
        #expect(result == [1])
    }

    @Test
    func unknownWord() {
        let vocab: [String: Int] = ["hello": 1, "[UNK]": 0]
        let wp = WordPieceTokenizer(vocab: vocab)

        let result = wp.tokenize(word: "xyz")
        #expect(result == [0])
    }

    @Test
    func subwordSplit() {
        let vocab: [String: Int] = ["un": 1, "##aff": 2, "##able": 3, "[UNK]": 0]
        let wp = WordPieceTokenizer(vocab: vocab)

        let result = wp.tokenize(word: "unaffable")
        #expect(result == [1, 2, 3])
    }

    @Test
    func veryLongWord() {
        let vocab: [String: Int] = ["[UNK]": 0]
        let wp = WordPieceTokenizer(vocab: vocab, maxInputCharsPerWord: 10)

        let longWord = String(repeating: "a", count: 100)
        let result = wp.tokenize(word: longWord)
        #expect(result == [0])
    }
}
#endif
