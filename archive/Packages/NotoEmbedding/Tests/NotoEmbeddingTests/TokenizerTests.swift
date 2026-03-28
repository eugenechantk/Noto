import Foundation
import Testing
import NotoEmbedding

private func createTestVocabURL() throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("vocab-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let vocabURL = tempDir.appendingPathComponent("vocab.txt")
    let tokens = [
        "[PAD]",
        "[UNK]",
        "[CLS]",
        "[SEP]",
        "hello",
        "world",
        ",",
        "!",
        "un",
        "##aff",
        "##able",
    ]
    try tokens.joined(separator: "\n").write(to: vocabURL, atomically: true, encoding: .utf8)
    return vocabURL
}

struct TokenizerPackageTests {
    @Test
    func wordPieceSubwordSplit() {
        let vocab: [String: Int] = ["un": 1, "##aff": 2, "##able": 3, "[UNK]": 0]
        let tokenizer = WordPieceTokenizer(vocab: vocab)
        #expect(tokenizer.tokenize(word: "unaffable") == [1, 2, 3])
    }

    @Test
    func bertTokenizerAddsSpecialTokens() throws {
        let vocabURL = try createTestVocabURL()
        defer { try? FileManager.default.removeItem(at: vocabURL.deletingLastPathComponent()) }

        let tokenizer = try BertTokenizer(vocabURL: vocabURL, maxSequenceLength: 16)
        let output = tokenizer.tokenize("hello world")

        #expect(output.inputIds[0] == 2)
        #expect(output.inputIds.contains(3))
        #expect(output.inputIds.count == 16)
        #expect(output.attentionMask.count == 16)
    }
}
