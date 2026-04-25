import Foundation
import Testing
import NotoSearch

@Suite("MarkdownSearchDocumentExtractor")
struct MarkdownSearchDocumentExtractorTests {
    @Test("Extractor strips frontmatter and creates heading-bounded sections")
    func extractorCreatesSearchDocument() throws {
        let vault = try makeFixtureVault()
        defer { removeDirectory(vault) }

        let fileURL = vault.appendingPathComponent("Projects/Launch Notes.md")
        let document = try MarkdownSearchDocumentExtractor(vaultURL: vault).extract(fileURL: fileURL)

        #expect(document.id.uuidString == "11111111-1111-4111-8111-111111111111")
        #expect(document.relativePath == "Projects/Launch Notes.md")
        #expect(document.folderPath == "Projects")
        #expect(document.title == "Launch Notes")
        #expect(document.plainText.contains("TikTok hooks"))
        #expect(!document.plainText.contains("created:"))
        #expect(document.sections.map(\.heading) == ["Launch Notes", "Acquisition", "Monetization"])
        #expect(document.sections.first { $0.heading == "Acquisition" }?.plainText.contains("App Store keyword tests") == true)
    }

    @Test("Extractor uses path-derived fallback ID when frontmatter ID is absent")
    func extractorUsesPathFallbackID() throws {
        let vault = try makeFixtureVault()
        defer { removeDirectory(vault) }

        let fileURL = vault.appendingPathComponent("Body Only.md")
        let first = try MarkdownSearchDocumentExtractor(vaultURL: vault).extract(fileURL: fileURL)
        let second = try MarkdownSearchDocumentExtractor(vaultURL: vault).extract(fileURL: fileURL)

        #expect(first.id == second.id)
        #expect(first.title == "Body Only Match")
    }
}
