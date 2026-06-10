//
//  GraniteTokenizerTests.swift
//  NotoEmbeddingTests
//
//  Test Case Index
//  ---------------
//  1. goldenFixtureMatchesPython      — all 20 golden cases (EN/ZH/JA/KO/Cyrillic/emoji/markdown/contractions/truncation) match Python HF input_ids exactly
//  2. emptyStringIsSpecialsOnly       — "" encodes to exactly [CLS, SEP] = [179934, 179938]
//  3. specialTokensWrapEveryEncoding  — every encoding starts with CLS 179934 and ends with SEP 179938
//  4. truncationCapsAt512WithSEPLast  — long_trunc golden case: encode(maxTokens: 512) is exactly 512 ids, equals golden, SEP last
//  5. truncationNoOpWhenUnderBudget   — encode(_:maxTokens:) leaves short inputs untouched (== encode(_:))
//  6. doubleEncodeIsDeterministic     — encoding the same text twice yields identical ids
//

import Foundation
import Testing

@testable import NotoEmbedding

// MARK: - Fixtures

/// One golden case from tokenizer_golden.json: Python `tok(text, truncation=True, max_length=512)["input_ids"]`.
private struct GoldenCase: Decodable {
    let name: String
    let text: String
    let ids: [Int]
}

/// Shared fixtures. The tokenizer parses the 24 MB tokenizer.json once per test process.
private enum Fixtures {
    static let tokenizer: GraniteTokenizer = {
        do {
            return try GraniteTokenizer.bundled()
        } catch {
            fatalError("Failed to load bundled GraniteTokenizer: \(error)")
        }
    }()

    static let golden: [GoldenCase] = {
        guard let url = Bundle.module.url(forResource: "tokenizer_golden", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let cases = try? JSONDecoder().decode([GoldenCase].self, from: data)
        else {
            fatalError("Failed to load tokenizer_golden.json from test bundle")
        }
        return cases
    }()

    static let clsId = 179934 // <|startoftext|>
    static let sepId = 179938 // <|return|>
}

// MARK: - Tests

@Suite("GraniteTokenizer")
struct GraniteTokenizerTests {
    /// All 20 golden cases match the Python HF tokenizer exactly (ids include specials; max_length=512 truncation).
    @Test func goldenFixtureMatchesPython() {
        let cases = Fixtures.golden
        #expect(cases.count == 20, "Expected 20 golden cases, got \(cases.count)")
        for goldenCase in cases {
            let ids = Fixtures.tokenizer.encode(goldenCase.text, maxTokens: 512)
            #expect(
                ids == goldenCase.ids,
                "Golden case '\(goldenCase.name)' mismatch: expected \(goldenCase.ids), got \(ids)"
            )
        }
    }

    /// The empty string encodes to exactly [CLS, SEP] with no content tokens.
    @Test func emptyStringIsSpecialsOnly() {
        #expect(Fixtures.tokenizer.encode("") == [Fixtures.clsId, Fixtures.sepId])
    }

    /// Every encoding is wrapped in CLS (179934) first and SEP (179938) last.
    @Test func specialTokensWrapEveryEncoding() {
        let samples = ["hello world", "今天天气很好", "a", "  spaces  "]
        for sample in samples {
            let ids = Fixtures.tokenizer.encode(sample)
            #expect(ids.first == Fixtures.clsId, "'\(sample)' should start with CLS, got \(String(describing: ids.first))")
            #expect(ids.last == Fixtures.sepId, "'\(sample)' should end with SEP, got \(String(describing: ids.last))")
            #expect(ids.count >= 3, "'\(sample)' should have content between specials")
        }
    }

    /// The long_trunc golden case truncates to exactly 512 ids with SEP appended after truncation.
    @Test func truncationCapsAt512WithSEPLast() throws {
        let longTrunc = try #require(Fixtures.golden.first { $0.name == "long_trunc" })
        let ids = Fixtures.tokenizer.encode(longTrunc.text, maxTokens: 512)
        #expect(ids.count == 512)
        #expect(ids == longTrunc.ids)
        #expect(ids.first == Fixtures.clsId)
        #expect(ids.last == Fixtures.sepId)
        // Untruncated encoding must be longer than 512 for this case to be meaningful.
        #expect(Fixtures.tokenizer.encode(longTrunc.text).count > 512)
    }

    /// Truncation is a no-op when the encoding already fits the budget.
    @Test func truncationNoOpWhenUnderBudget() {
        let text = "Meeting notes from Tuesday"
        let untruncated = Fixtures.tokenizer.encode(text)
        #expect(untruncated.count < 512)
        #expect(Fixtures.tokenizer.encode(text, maxTokens: 512) == untruncated)
    }

    /// Encoding the same text twice produces identical ids (no hidden state).
    @Test func doubleEncodeIsDeterministic() {
        let text = "Standup notes 周一：Backend team 完成了 payment gateway 的集成测试。🎉"
        let first = Fixtures.tokenizer.encode(text)
        let second = Fixtures.tokenizer.encode(text)
        #expect(first == second)
        let firstTruncated = Fixtures.tokenizer.encode(text, maxTokens: 16)
        let secondTruncated = Fixtures.tokenizer.encode(text, maxTokens: 16)
        #expect(firstTruncated == secondTruncated)
        #expect(firstTruncated.count == 16)
    }
}
