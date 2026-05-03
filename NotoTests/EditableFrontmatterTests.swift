import Foundation
import Testing
@testable import Noto

@Suite("Editable Frontmatter")
struct EditableFrontmatterTests {
    @Test("Parses scalar fields")
    func parsesScalarFields() throws {
        let document = try #require(EditableFrontmatterDocument(markdown: """
        ---
        id: abc
        source: https://example.com
        ---
        # Title
        """))

        #expect(document.fields.map(\.key) == ["id", "source"])
        #expect(document.fields[0].value == "abc")
        #expect(document.fields[1].value == "https://example.com")
    }

    @Test("Preserves multiline values when parsing and updating another field")
    func preservesMultilineValues() throws {
        let markdown = """
        ---
        id: abc
        summary: |
          first line
          second line
        updated: old
        ---
        # Title
        """

        let document = try #require(EditableFrontmatterDocument(markdown: markdown))
        let summary = try #require(document.fields.first { $0.key == "summary" })
        #expect(summary.value.contains("first line"))
        #expect(summary.value.contains("second line"))

        let updated = EditableFrontmatterDocument.updatingField(key: "updated", value: "new", in: markdown)
        #expect(updated.contains("summary: |\n  first line\n  second line"))
        #expect(updated.contains("updated: new"))
    }

    @Test("Updates scalar values")
    func updatesScalarValues() {
        let markdown = """
        ---
        id: abc
        updated: old
        ---
        # Title
        """

        let updated = EditableFrontmatterDocument.updatingField(key: "updated", value: "new", in: markdown)

        #expect(updated.contains("updated: new"))
        #expect(!updated.contains("updated: old"))
        #expect(updated.hasSuffix("# Title"))
    }

    @Test("Adds frontmatter to plain markdown")
    func addsFrontmatterToPlainMarkdown() {
        let updated = EditableFrontmatterDocument.addingField(key: "source", value: "https://example.com", in: "# Title")

        #expect(updated == """
        ---
        source: https://example.com
        ---

        # Title
        """)
    }

    @Test("Adds a key value pair to existing frontmatter")
    func addsFieldToExistingFrontmatter() {
        let markdown = """
        ---
        id: abc
        ---
        # Title
        """

        let updated = EditableFrontmatterDocument.addingField(key: "source", value: "https://example.com", in: markdown)

        #expect(updated.contains("id: abc\nsource: https://example.com\n---"))
    }

    @Test("Parses draft key value input")
    func parsesDraftKeyValueInput() throws {
        let parsed = try #require(EditableFrontmatterDocument.parsedFieldInput("source: https://example.com"))
        let keyOnly = try #require(EditableFrontmatterDocument.parsedFieldInput("status"))

        #expect(parsed.key == "source")
        #expect(parsed.value == "https://example.com")
        #expect(keyOnly.key == "status")
        #expect(keyOnly.value == "")
        #expect(EditableFrontmatterDocument.parsedFieldInput("invalid key: value") == nil)
        #expect(EditableFrontmatterDocument.parsedFieldInput("   ") == nil)
    }

    @Test("Deletes a field and its continuation lines")
    func deletesFieldAndContinuationLines() {
        let markdown = """
        ---
        id: abc
        summary: |
          first line
          second line
        updated: old
        ---
        # Title
        """

        let updated = EditableFrontmatterDocument.deletingField(key: "summary", in: markdown)

        #expect(!updated.contains("summary:"))
        #expect(!updated.contains("first line"))
        #expect(updated.contains("id: abc\nupdated: old\n---"))
    }

    @Test("Detects URL-like values")
    func detectsURLLikeValues() throws {
        let document = try #require(EditableFrontmatterDocument(markdown: """
        ---
        source: "https://example.com/article"
        title: Not a URL
        ---
        # Title
        """))

        let source = try #require(document.fields.first { $0.key == "source" })
        let title = try #require(document.fields.first { $0.key == "title" })

        #expect(source.url?.absoluteString == "https://example.com/article")
        #expect(title.url == nil)
    }
}
