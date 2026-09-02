// TEST INDEX
// 1) inlineTagExtraction — parses inline list syntax from frontmatter tags
// 2) denormalizedTagExtraction — parses denormalized tags and normalizes values
// 3) missingTagFieldReturnsEmpty — missing tags field in frontmatter yields no tags
// 4) noFrontmatterReturnsEmpty — content without frontmatter yields no tags

import Testing
import NotoTags
import NotoVault
@testable import Noto

import Foundation

@Suite("TagController")
struct TagControllerTests {
    @Test("Extracts tags from inline frontmatter list syntax")
    func inlineTagExtraction() {
        let tags = TagController.tagNames(inFrontmatterOf: """
        ---
        tags: [one, two]
        ---
        # Title
        """)

        #expect(tags == ["one", "two"].compactMap(TagName.init))
    }

    @Test("Normalizes denormalized frontmatter tags before returning")
    func denormalizedTagExtraction() {
        let tags = TagController.tagNames(inFrontmatterOf: """
        ---
        tags: [A, "B C"]
        ---
        """)

        #expect(tags == ["a", "b-c"].compactMap(TagName.init))
    }

    @Test("Returns empty when tags field is missing")
    func missingTagFieldReturnsEmpty() {
        let tags = TagController.tagNames(inFrontmatterOf: """
        ---
        id: 550e8400-e29b-41d4-a716-446655440000
        ---
        """)

        #expect(tags.isEmpty)
    }

    @Test("Returns empty when no frontmatter exists")
    func noFrontmatterReturnsEmpty() {
        let tags = TagController.tagNames(inFrontmatterOf: "# Title\n\nBody")

        #expect(tags.isEmpty)
    }

    @MainActor
    @Test("commitTags normalizes and dedupes members")
    func commitTagsNormalizesAndDedupesMembers() throws {
        let vault = makeTagControllerTempVault()
        defer { cleanupTagControllerTempVault(vault) }

        let store = MarkdownNoteStore(vaultURL: vault)
        let note = store.createNote()
        let loaded = store.saveContent(MarkdownNote.makeFrontmatter(id: note.id) + "# Template Tags", for: note)
        let session = NoteEditorSession(store: store, note: loaded.note, isNew: false)
        session.applyExternalContentEdit(MarkdownNote.makeFrontmatter(id: loaded.note.id) + "# Template Tags")

        let controller = TagController(vaultURL: vault)
        let committed = controller.commitTags(
            ["Daily Notes", "daily-notes", "Draft", "Draft", ""],
            previous: [],
            frontmatterKey: "tags",
            session: session
        )

        #expect(committed.map(\.rawValue) == ["daily-notes", "draft"])

        let document = try #require(EditableFrontmatterDocument(markdown: session.content))
        let tagsValue = document.fields.first(where: { $0.key == "tags" })?.value ?? ""
        #expect(NotePropertyClassifier.parseTags(tagsValue) == ["daily-notes", "draft"])
    }

    @MainActor
    @Test("commitTags applies templates only for newly added tags")
    func commitTagsAppliesTemplatesOnlyOnFirstAdd() {
        let vault = makeTagControllerTempVault()
        defer { cleanupTagControllerTempVault(vault) }

        let store = MarkdownNoteStore(vaultURL: vault)
        let note = store.createNote()
        let initialContent = MarkdownNote.makeFrontmatter(id: note.id) + "# Template Tags"
        let loaded = store.saveContent(initialContent, for: note)
        let session = NoteEditorSession(store: store, note: loaded.note, isNew: false)
        session.applyExternalContentEdit(initialContent)

        let controller = TagController(vaultURL: vault)
        _ = controller.save(TagDefinition(name: TagName("project plan")!, template: "Project template"))

        _ = controller.commitTags(["idea", "project plan"], previous: [TagName("idea")!], frontmatterKey: "tags", session: session)
        let marker = "<!-- noto:tag-template:project-plan -->"
        let firstCount = session.content.components(separatedBy: marker).count - 1

        #expect(firstCount == 1)
        #expect(session.content.contains("Project template"))

        let existing = EditableFrontmatterDocument(markdown: session.content)!.fields
            .first(where: { $0.key == "tags" })
            .map { NotePropertyClassifier.parseTags($0.value).compactMap(TagName.init) } ?? []

        let committedAgain = controller.commitTags(
            ["idea", "project plan"],
            previous: existing,
            frontmatterKey: "tags",
            session: session
        )

        #expect(committedAgain == [TagName("idea")!, TagName("project-plan")!])
        let secondCount = session.content.components(separatedBy: marker).count - 1
        #expect(secondCount == 1)
    }

    @MainActor
    @Test("save preserves original createdAt for existing tag definitions")
    func savePreservesOriginalCreatedAt() {
        let vault = makeTagControllerTempVault()
        defer { cleanupTagControllerTempVault(vault) }

        let controller = TagController(vaultURL: vault)
        let tagName = TagName("project plan")!
        let originalCreatedAt = Date(timeIntervalSince1970: 1)
        let original = TagDefinition(name: tagName, template: "First template", createdAt: originalCreatedAt, modifiedAt: originalCreatedAt)
        _ = controller.save(original)

        let updated = controller.save(TagDefinition(name: tagName, template: "Updated template"))
        #expect(updated.createdAt == originalCreatedAt)
        let reloaded = controller.definition(for: tagName)
        #expect(reloaded?.template == "Updated template")
        #expect(reloaded?.createdAt == originalCreatedAt)
    }

    @MainActor
    @Test("remove deletes a tag definition")
    func removeDeletesDefinition() {
        let vault = makeTagControllerTempVault()
        defer { cleanupTagControllerTempVault(vault) }

        let controller = TagController(vaultURL: vault)
        let tagName = TagName("draft")!
        _ = controller.save(TagDefinition(name: tagName, template: "Draft template"))

        controller.remove(tagName)
        #expect(controller.definition(for: tagName) == nil)
    }
}

private func makeTagControllerTempVault() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("NotoTagControllerTests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func cleanupTagControllerTempVault(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}
