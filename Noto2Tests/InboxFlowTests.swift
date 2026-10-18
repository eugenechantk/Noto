import Foundation
import NotoDigest
import NotoSearch
import NotoVault
import Testing
@testable import Noto2

@MainActor
struct InboxFlowTests {
    private func makeVault() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("InboxFlow-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("inbox"), withIntermediateDirectories: true)
        return root
    }
    private func capture(_ text: String, name: String, root: URL) throws -> URL {
        let url = root.appendingPathComponent("inbox/" + name + ".md")
        try ("---\nid: \(UUID())\ncreated: 2026-10-18T09:00:00Z\nstatus: inbox\n---\n\n" + text + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    @Test func listSelectionActsOnSelectedCaptureAndReturnsToList() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try capture("First", name: "a", root: root)
        let second = try capture("Second", name: "b", root: root)
        let model = DigestModel(vaultURL: root, index: { _ in })
        await model.load()
        model.selectedEntryID = model.allEntries.first { $0.fileURL == second.standardizedFileURL }?.id
        #expect(model.current?.body == "Second")
        #expect(await model.discardCurrent())
        #expect(model.entries.map(\.body) == ["First"])
        #expect(model.selectedEntryID == nil)
        #expect(model.counts.discarded == 1)
        #expect(await model.undoLastAction())
        #expect(model.counts.discarded == 0)
        #expect(model.remaining == 2)
    }
    @Test func snoozeStaysInListAndUndoReturnsItToStack() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try capture("Think later", name: "a", root: root)
        let model = DigestModel(vaultURL: root, index: { _ in })
        await model.load()
        #expect(await model.snoozeCurrent())
        #expect(model.remaining == 0)
        #expect(model.allEntries.count == 1)
        #expect(model.sections.first?.kind == .snoozed)
        #expect(model.outcome?.isUndoable == true)
        #expect(await model.undoLastAction())
        #expect(model.current?.body == "Think later")
        #expect(model.counts.total == 0)
    }
    @Test func createAsWrittenUndoAndProgressSurviveModelReload() async throws {
        let root = try makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try capture("A thought", name: "a", root: root)
        let model = DigestModel(vaultURL: root, index: { _ in })
        await model.load()
        #expect(await model.createNoteFromCurrent(inFolderAt: root, body: "Edited thought\n\nDetails"))
        #expect(model.outcome?.text == "Created in Library")
        #expect(model.outcome?.isUndoable == true)
        let reloaded = DigestModel(vaultURL: root, index: { _ in })
        #expect(reloaded.counts.filed == 1)
        #expect(await model.undoLastAction())
        #expect(model.current?.body == "A thought")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Edited thought.md").path))
    }
    @Test func fullContentSearchUsesSnippetAndExcludesInbox() throws {
        let root = URL(fileURLWithPath: "/tmp/InboxSearch")
        let note = AddToCandidate(url: root.appendingPathComponent("Ideas.md"), title: "Ideas", relativePath: "Ideas.md", folderPath: "", modifiedAt: .now)
        let result = SearchResult(id: UUID(), kind: .note, noteID: UUID(), fileURL: note.url,
                                  title: "Ideas", breadcrumb: "", snippet: "Find the body keyword", lineStart: nil, score: 1, updatedAt: .now)
        let matches = AddToCandidates.searchResults([result, result], candidates: [note], vaultURL: root, query: "keyword")
        #expect(matches.count == 1)
        #expect(matches.first?.snippet == "Find the body keyword")
    }
    @Test func recentFolderOrderUsesLastModifiedDestination() {
        let root = URL(fileURLWithPath: "/tmp/Vault")
        let notes = [AddToCandidate(url: root.appendingPathComponent("Old/A.md"), title: "A", relativePath: "Old/A.md", folderPath: "Old", modifiedAt: .distantPast),
                     AddToCandidate(url: root.appendingPathComponent("New/B.md"), title: "B", relativePath: "New/B.md", folderPath: "New", modifiedAt: .now)]
        for directoryHint in [false, true] {
            let folders = [NewNoteFolder(url: root, name: "Library", path: ""),
                           NewNoteFolder(url: root.appendingPathComponent("Old", isDirectory: directoryHint), name: "Old", path: "Old"),
                           NewNoteFolder(url: root.appendingPathComponent("New", isDirectory: directoryHint), name: "New", path: "New")]
            #expect(NewNoteFolder.recent(folders, notes: notes).map(\.name) == ["New", "Old"], "Directory hint: \(directoryHint)")
        }
    }
}
