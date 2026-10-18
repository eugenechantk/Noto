#if os(macOS)
import Foundation
import Testing
@testable import Noto

@Suite("Desktop capture and navigation") @MainActor
struct MacDesktopModelTests {
    @Test func snoozedCaptureDoesNotReopenAfterRefresh() async throws {
        let root = try vault()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = MacDesktopModel(store: MarkdownNoteStore(vaultURL: root))
        model.draft = "Review this next week"; model.fileCapture()
        await model.refresh(); model.select(.inbox)
        model.inboxAction("later")
        await model.refresh()
        #expect(model.visibleNotes.count == 1)
        #expect(model.selectedNote == nil)
        model.select(.inbox)
        #expect(model.selectedNote == nil)
    }

    @Test func captureAndUndoPreserveDraft() async throws {
        let root = try vault()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = MacDesktopModel(store: MarkdownNoteStore(vaultURL: root))
        model.draft = "A small thought"
        model.fileCapture()
        #expect(model.draft.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("inbox"), includingPropertiesForKeys: nil)
        #expect(files.count == 1)
        #expect(MacDesktopModel(store: MarkdownNoteStore(vaultURL: root)).filedToday == 1)
        await model.refresh()
        model.undo()
        #expect(model.draft == "A small thought")
        #expect(!FileManager.default.fileExists(atPath: files[0].path))
        #expect(MacDesktopModel(store: MarkdownNoteStore(vaultURL: root)).filedToday == 0)
        model.select(.inbox)
        #expect(model.visibleNotes.isEmpty)
        #expect(model.selectedNote == nil)
        model.select(.capture); model.fileCapture()
        await model.refresh(); model.select(.inbox)
        #expect(model.visibleNotes.count == 1)
        #expect(model.selectedNote != nil)
    }

    @Test func duplicateRequiresLoadedContentAndIncludesUnsavedEdits() async throws {
        let root = try vault()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = MarkdownNote.makeFrontmatter(id: UUID()) + "# Original\n\nBody."
        try source.write(to: root.appendingPathComponent("Original.md"), atomically: true, encoding: .utf8)
        let model = MacDesktopModel(store: MarkdownNoteStore(vaultURL: root))
        await model.refresh()
        let note = try #require(model.library?.notes.first)
        model.duplicate(note)
        #expect(model.error != nil)
        #expect(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "md" }.count == 1)
        model.error = nil; model.document = source + "\nUnsaved edit."; model.documentReady = true
        model.open(note)
        #expect(model.document.contains("Unsaved edit."))
        #expect(model.documentReady)
        model.duplicate(note)
        let duplicate = try #require(model.selectedNote)
        #expect(duplicate.id != note.id)
        #expect(try String(contentsOf: duplicate.fileURL, encoding: .utf8).contains("Unsaved edit."))
        #expect(try String(contentsOf: note.fileURL, encoding: .utf8) == source)
        model.duplicate(note)
        #expect(model.pendingDuplicate == note.id)
        #expect(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "md" }.count == 2)
        model.select(.capture)
        #expect(model.pendingDuplicate == nil)
    }

    @Test func undoKeepsAnExternallyEditedCapture() throws {
        let root = try vault()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = MacDesktopModel(store: MarkdownNoteStore(vaultURL: root))
        model.draft = "Original thought"; model.fileCapture()
        let file = try #require(FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("inbox"), includingPropertiesForKeys: nil).first)
        let changed = try String(contentsOf: file, encoding: .utf8) + "\nAdded elsewhere"
        try changed.write(to: file, atomically: true, encoding: .utf8)
        model.undo()
        #expect(try String(contentsOf: file, encoding: .utf8) == changed)
        #expect(model.error != nil)
    }

    @Test func inboxAppendWritesDestinationBeforeRemovingCapture() async throws {
        let root = try vault()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Existing.md")
        try (MarkdownNote.makeFrontmatter(id: UUID()) + "# Existing\n\nBefore").write(to: target, atomically: true, encoding: .utf8)
        let model = MacDesktopModel(store: MarkdownNoteStore(vaultURL: root))
        model.draft = "Captured thought"; model.fileCapture()
        await model.refresh(); model.select(.inbox)
        let source = try #require(model.selectedNote?.fileURL)
        model.paletteUsesDraft = false; model.file(to: target, purpose: .append)
        #expect(try String(contentsOf: target, encoding: .utf8).contains("Captured thought"))
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    @Test func failedAppendKeepsCapture() async throws {
        let root = try vault()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = MacDesktopModel(store: MarkdownNoteStore(vaultURL: root))
        model.draft = "Keep this"; model.fileCapture()
        await model.refresh(); model.select(.inbox)
        let source = try #require(model.selectedNote?.fileURL)
        model.paletteUsesDraft = false; model.file(to: root.appendingPathComponent("Missing.md"), purpose: .append)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(model.error != nil)
    }

    @Test func undoDiscardRestoresDocumentSelectionAndProgress() async throws {
        let root = try vault()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = MacDesktopModel(store: MarkdownNoteStore(vaultURL: root))
        model.draft = "Keep this exact thought"; model.fileCapture()
        await model.refresh(); model.select(.inbox)
        let source = try #require(model.selectedNote)
        let original = try String(contentsOf: source.fileURL, encoding: .utf8)
        let completed = model.completedCount
        model.inboxAction("discard")
        #expect(!FileManager.default.fileExists(atPath: source.fileURL.path))
        #expect(model.completedCount == completed + 1)
        model.undo()
        #expect(try String(contentsOf: source.fileURL, encoding: .utf8) == original)
        #expect(model.selectedNote?.id == source.id)
        #expect(model.document == original)
        #expect(model.completedCount == completed)
    }

    @Test func firstDocumentIsTheHistoryBaseline() async throws {
        let root = try vault()
        defer { try? FileManager.default.removeItem(at: root) }
        for title in ["First", "Second"] {
            try (MarkdownNote.makeFrontmatter(id: UUID()) + "# " + title).write(to: root.appendingPathComponent(title + ".md"), atomically: true, encoding: .utf8)
        }
        let model = MacDesktopModel(store: MarkdownNoteStore(vaultURL: root))
        await model.refresh()
        let initial = try #require(model.selectedNote?.id)
        let other = try #require(model.library?.notes.first { $0.id != initial })
        model.open(other)
        #expect(model.history.canGoBack)
        model.navigateHistory(back: true)
        #expect(model.selectedNote?.id == initial)
    }

    private func vault() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("desktop-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
#endif
