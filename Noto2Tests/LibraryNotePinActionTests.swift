import Foundation
import NotoVault
import Testing
@testable import Noto2

struct LibraryNotePinActionTests {
    @MainActor @Test func pinSurvivesEditingAndUnpinSurvivesFinalSave() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let url = root.appendingPathComponent("test.md")
        try "---\nid: \(id)\nmodified: 2026-10-18T00:00:00Z\n---\n# Test\nOriginal".write(to: url, atomically: true, encoding: .utf8)
        let controller = VaultController(vaultURL: root, autoloadRoot: false)
        let store = controller.rootStore
        let note = MarkdownNote(id: id, fileURL: url, title: "Test", modifiedDate: Date())
        let session = NoteEditorSession(store: store, note: note, vaultController: controller)
        await session.loadNoteContent()
        try LibraryNotePinAction.toggle(session: session)
        #expect(NotePinning.isPinned(in: session.content))
        session.handleEditorChange(session.latestEditorText + "\nAn edit after pinning")
        session.persistFinalSnapshotIfNeeded(isExternallyDeleting: false)
        #expect(NotePinning.isPinned(in: try String(contentsOf: url, encoding: .utf8)))
        try LibraryNotePinAction.toggle(session: session)
        session.persistFinalSnapshotIfNeeded(isExternallyDeleting: false)
        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(!NotePinning.isPinned(in: saved))
        #expect(saved.contains("An edit after pinning"))
        #expect(session.latestEditorText == session.lastPersistedText)
        session.cancelBackgroundWork()
    }
}
