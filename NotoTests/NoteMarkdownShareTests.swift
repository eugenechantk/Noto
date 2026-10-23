import Foundation
import Testing
import NotoVault
@testable import Noto

@Suite("Note Markdown sharing")
struct NoteMarkdownShareTests {
    #if os(macOS)
    @Test("Context sharing uses the chosen note and preserves current unsaved edits")
    @MainActor
    func contextShareUsesChosenNote() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstText = MarkdownNote.makeFrontmatter(id: UUID()) + "# First\n\n**First body**"
        let secondText = MarkdownNote.makeFrontmatter(id: UUID()) + "# Second\n\n- [ ] Second body"
        try firstText.write(to: directory.appendingPathComponent("First.md"), atomically: true, encoding: .utf8)
        try secondText.write(to: directory.appendingPathComponent("Second.md"), atomically: true, encoding: .utf8)
        let model = MacDesktopModel(store: MarkdownNoteStore(vaultURL: directory))
        await model.refresh()
        let first = try #require(model.library?.notes.first { $0.title == "First" })
        let second = try #require(model.library?.notes.first { $0.title == "Second" })
        model.open(first)
        model.document = firstText + "\nUnsaved edit"
        model.documentReady = true
        #expect(try await model.markdownShare(for: first).loadText() == "# First\n\n**First body**\nUnsaved edit")
        #expect(try await model.markdownShare(for: second).loadText() == "# Second\n\n- [ ] Second body")
        model.documentReady = false
        #expect(model.selectedNoteShare == nil)
        #expect(try await model.markdownShare(for: first).loadText() == "# First\n\n**First body**")
    }
    #endif

    @Test("Editor sharing uses unsaved text before autosave updates bound content")
    @MainActor
    func sharesLatestEditorText() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MarkdownNoteStore(vaultURL: directory)
        let note = store.createNote()
        let session = NoteEditorSession(store: store, note: note)
        await session.loadNoteContent()
        defer { session.cancelBackgroundWork() }
        let original = session.content
        let edited = original + "\n**Unsaved text 中文**\n"
        session.handleEditorChange(edited)
        #expect(session.content == original)
        let item = try #require(session.markdownShare)
        #expect(try await item.loadText() == MarkdownNote.stripFrontmatter(edited))
    }

    @Test("An unloaded editor cannot share its placeholder")
    @MainActor
    func unloadedEditorCannotShare() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let note = MarkdownNote(id: UUID(), fileURL: directory.appendingPathComponent("Missing.md"), title: "Missing", modifiedDate: Date())
        let session = NoteEditorSession(store: MarkdownNoteStore(vaultURL: directory, autoload: false), note: note)
        #expect(session.markdownShare == nil)
    }
}
