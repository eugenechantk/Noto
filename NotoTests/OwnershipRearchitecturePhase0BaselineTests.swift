import Foundation
import NotoSearch
import Testing
@testable import Noto

@Suite("Ownership Rearchitecture Phase 0 Baseline")
struct OwnershipRearchitecturePhase0BaselineTests {
    @MainActor
    @Test("current behavior: workspace sequence resolves root, nested notes, history, and today note")
    func workspaceNavigationBaseline() throws {
        let vault = try Phase0BaselineFixture.makeTempVault()
        defer { Phase0BaselineFixture.cleanup(vault) }

        let rootID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let nestedID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        try Phase0BaselineFixture.writeMarkdown(
            title: "Root Baseline",
            body: "Root body",
            id: rootID,
            relativePath: "Root Baseline.md",
            in: vault
        )
        try Phase0BaselineFixture.writeMarkdown(
            title: "Nested Baseline",
            body: "Nested body",
            id: nestedID,
            relativePath: "Projects/Nested Baseline.md",
            in: vault
        )

        let rootStore = MarkdownNoteStore(vaultURL: vault, autoload: false)
        rootStore.loadItems()

        #expect(rootStore.folders.map(\.name) == ["Projects"])
        #expect(rootStore.notes.map(\.title) == ["Root Baseline"])

        let rootResolution = try #require(rootStore.note(atVaultRelativePath: "Root%20Baseline.md"))
        let nestedResolution = try #require(rootStore.note(atVaultRelativePath: "Projects/Nested%20Baseline.md"))

        #expect(rootResolution.note.id == rootID)
        #expect(rootResolution.note.title == "Root Baseline")
        #expect(rootResolution.store.directoryURL.standardizedFileURL == vault.standardizedFileURL)
        #expect(nestedResolution.note.id == nestedID)
        #expect(nestedResolution.note.title == "Nested Baseline")
        #expect(nestedResolution.store.directoryURL.lastPathComponent == "Projects")

        var history = NoteNavigationHistory()
        history.visit(NoteStackEntry(note: rootResolution.note, store: rootResolution.store, isNew: false))
        history.visit(NoteStackEntry(note: nestedResolution.note, store: nestedResolution.store, isNew: false))

        #expect(history.currentEntry?.note.title == "Nested Baseline")
        #expect(history.goBack()?.note.title == "Root Baseline")
        #expect(history.goForward()?.note.title == "Nested Baseline")

        let firstToday = rootStore.todayNote()
        let secondToday = rootStore.todayNote()

        #expect(firstToday.note.fileURL == secondToday.note.fileURL)
        #expect(firstToday.note.fileURL.deletingLastPathComponent().lastPathComponent == "Daily Notes")
        #expect(FileManager.default.fileExists(atPath: firstToday.note.fileURL.path))

        let todayContent = CoordinatedFileManager.readString(from: firstToday.note.fileURL) ?? ""
        #expect(todayContent.contains("## What did I do today?"))
        #expect(todayContent.contains("## What's on my mind today?"))
    }

    @MainActor
    @Test("current behavior: note mutation sequence creates, autosaves, renames, reloads, and deletes")
    func noteMutationBaseline() async throws {
        let vault = try Phase0BaselineFixture.makeTempVault()
        defer { Phase0BaselineFixture.cleanup(vault) }

        let store = MarkdownNoteStore(vaultURL: vault)
        let note = store.createNote()
        let editedContent = MarkdownNote.makeFrontmatter(id: note.id) + """
        # Phase Zero Mutation

        Body saved by the current NoteEditorSession autosave path.
        """
        let session = NoteEditorSession(store: store, note: note, isNew: true)

        await session.loadNoteContent()
        session.handleEditorChange(editedContent)

        try? await Task.sleep(for: .milliseconds(950))

        #expect(session.note.title == "Phase Zero Mutation")
        #expect(session.note.fileURL.lastPathComponent == "Phase Zero Mutation.md")
        #expect(FileManager.default.fileExists(atPath: session.note.fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: note.fileURL.path))

        let savedContent = CoordinatedFileManager.readString(from: session.note.fileURL) ?? ""
        #expect(savedContent.contains("Body saved by the current NoteEditorSession autosave path."))

        let reloadedStore = MarkdownNoteStore(vaultURL: vault, autoload: false)
        let resolved = try #require(reloadedStore.note(withID: note.id))
        #expect(resolved.note.title == "Phase Zero Mutation")
        #expect(resolved.note.fileURL.lastPathComponent == "Phase Zero Mutation.md")

        let reloadedSession = NoteEditorSession(store: resolved.store, note: resolved.note)
        await reloadedSession.loadNoteContent()
        #expect(reloadedSession.content.contains("Body saved by the current NoteEditorSession autosave path."))

        reloadedSession.markDeleting()
        #expect(resolved.store.deleteNote(reloadedSession.note))
        #expect(!FileManager.default.fileExists(atPath: reloadedSession.note.fileURL.path))

        session.cancelBackgroundWork()
        reloadedSession.cancelBackgroundWork()
    }

    @MainActor
    @Test("current behavior: search sequence refreshes create, save, rename, and delete changes")
    func searchBaseline() async throws {
        let vault = try Phase0BaselineFixture.makeTempVault()
        defer { Phase0BaselineFixture.cleanup(vault) }
        defer { Phase0BaselineFixture.cleanup(MarkdownSearchIndexer(vaultURL: vault).indexDirectory) }

        let store = MarkdownNoteStore(vaultURL: vault)
        let note = store.createNote()
        let initialContent = MarkdownNote.makeFrontmatter(id: note.id) + """
        # Search Baseline

        Orchard velocity appears in the first saved body.
        """
        var savedNote = store.saveContent(initialContent, for: note).note
        _ = try await SearchIndexController.shared.refreshFile(vaultURL: vault, fileURL: savedNote.fileURL)

        #expect(try Phase0BaselineFixture.search("orchard velocity", in: vault).contains { $0.title == "Search Baseline" })

        let updatedContent = MarkdownNote.makeFrontmatter(id: note.id) + """
        # Search Baseline Renamed

        Phase zero search freshness appears after an edit.
        """
        savedNote = store.saveContent(updatedContent, for: savedNote).note
        _ = try await SearchIndexController.shared.refreshFile(vaultURL: vault, fileURL: savedNote.fileURL)

        #expect(try Phase0BaselineFixture.search("phase zero search freshness", in: vault).contains {
            $0.title == "Search Baseline Renamed"
        })

        let oldURL = savedNote.fileURL
        let renamedNote = store.renameFileIfNeeded(for: savedNote)
        _ = try await SearchIndexController.shared.replaceFile(
            vaultURL: vault,
            oldFileURL: oldURL,
            newFileURL: renamedNote.fileURL
        )

        #expect(renamedNote.fileURL.lastPathComponent == "Search Baseline Renamed.md")
        #expect(try Phase0BaselineFixture.search("Search Baseline Renamed", in: vault, scope: .title).contains {
            $0.fileURL == renamedNote.fileURL
        })

        #expect(store.deleteNote(renamedNote))
        _ = try await SearchIndexController.shared.removeFile(vaultURL: vault, fileURL: renamedNote.fileURL)

        #expect(try Phase0BaselineFixture.search("phase zero search freshness", in: vault).isEmpty)
    }

    @MainActor
    @Test("current behavior: editor interaction sequence resolves mentions, inserts links, transforms text, and autosaves")
    func editorInteractionBaseline() async throws {
        let vault = try Phase0BaselineFixture.makeTempVault()
        defer { Phase0BaselineFixture.cleanup(vault) }

        let targetID = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
        try Phase0BaselineFixture.writeMarkdown(
            title: "Project Brief",
            body: "Mention target",
            id: targetID,
            relativePath: "Projects/Project Brief.md",
            in: vault
        )

        let store = MarkdownNoteStore(vaultURL: vault)
        let note = store.createNote()
        let session = NoteEditorSession(store: store, note: note, isNew: true)
        await session.loadNoteContent()

        let documents = store.pageMentionDocuments(matching: "Project", excluding: note.fileURL, limit: 10)
        let document = try #require(documents.first { $0.relativePath == "Projects/Project Brief.md" })
        let draft = MarkdownNote.makeFrontmatter(id: note.id) + "# Interaction Baseline\n\nSee @Project"
        let query = try #require(PageMentionMarkdown.activeQuery(
            in: draft,
            selection: NSRange(location: (draft as NSString).length, length: 0)
        ))
        let link = PageMentionMarkdown.markdownLink(for: document)
        let linkedDraft = (draft as NSString).replacingCharacters(in: query.range, with: link)

        #expect(link == "[Project Brief](Projects/Project Brief.md)")
        #expect(linkedDraft.contains("See [Project Brief](Projects/Project Brief.md)"))

        let todoDraft = linkedDraft + "\nFollow up"
        let todoTransform = try #require(BlockEditingCommands.toggledTodoLines(
            in: todoDraft,
            selection: NSRange(location: (todoDraft as NSString).length, length: 0)
        ))
        let finalDraft = todoTransform.text

        #expect(finalDraft.contains("- [ ] Follow up"))

        session.handleEditorChange(finalDraft)
        try? await Task.sleep(for: .milliseconds(650))

        let savedContent = CoordinatedFileManager.readString(from: session.note.fileURL) ?? ""
        #expect(savedContent.contains("[Project Brief](Projects/Project Brief.md)"))
        #expect(savedContent.contains("- [ ] Follow up"))

        session.cancelBackgroundWork()
    }

    @MainActor
    @Test("current behavior: current vault snapshot can be loaded and searched without mutating the live vault")
    func currentVaultSnapshotBaseline() throws {
        guard FileManager.default.fileExists(atPath: Phase0BaselineFixture.currentVaultURL.path) else {
            return
        }

        let snapshot = try Phase0BaselineFixture.makeCurrentVaultSnapshot(maxMarkdownFiles: 200)
        defer { Phase0BaselineFixture.cleanup(snapshot) }
        let indexDirectory = try Phase0BaselineFixture.makeTempVault(named: "NotoPhase0CurrentVaultIndex")
        defer { Phase0BaselineFixture.cleanup(indexDirectory) }

        let store = MarkdownNoteStore(vaultURL: snapshot, autoload: false)
        store.loadItems()

        #expect(!store.items.isEmpty)
        #expect(store.folders.contains { $0.name == "Captures" || $0.name == "Projects" || $0.name == "Daily Notes" })

        let indexer = MarkdownSearchIndexer(vaultURL: snapshot, indexDirectory: indexDirectory)
        let refresh = try indexer.refreshChangedFiles()
        let engine = MarkdownSearchEngine(store: try indexer.openStore(), vaultURL: snapshot)
        let results = try engine.search("AI", limit: 20)

        #expect(refresh.stats.noteCount > 0)
        #expect(!results.isEmpty)
    }
}

private enum Phase0BaselineFixture {
    static let currentVaultURL = URL(
        fileURLWithPath: "/Users/eugenechan/Library/Mobile Documents/com~apple~CloudDocs/Noto",
        isDirectory: true
    )

    static func makeTempVault(named prefix: String = "NotoPhase0Baseline") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func writeMarkdown(
        title: String,
        body: String,
        id: UUID = UUID(),
        relativePath: String,
        in vaultURL: URL
    ) throws {
        let fileURL = vaultURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let markdown = MarkdownNote.makeFrontmatter(id: id) + "# \(title)\n\n\(body)\n"
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func search(
        _ query: String,
        in vaultURL: URL,
        scope: SearchScope = .titleAndContent
    ) throws -> [SearchResult] {
        let indexer = MarkdownSearchIndexer(vaultURL: vaultURL)
        let engine = MarkdownSearchEngine(store: try indexer.openStore(), vaultURL: vaultURL)
        return try engine.search(query, scope: scope, limit: 20)
    }

    static func makeCurrentVaultSnapshot(maxMarkdownFiles: Int) throws -> URL {
        let snapshot = try makeTempVault(named: "NotoPhase0CurrentVaultSnapshot")
        var copiedMarkdownFiles = 0

        guard let enumerator = FileManager.default.enumerator(
            at: currentVaultURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return snapshot
        }

        for case let sourceURL as URL in enumerator {
            let relativePath = sourceURL.path.replacingOccurrences(of: currentVaultURL.path + "/", with: "")
            if sourceURL.lastPathComponent.hasPrefix(".") || relativePath.hasPrefix(".noto/") {
                if (try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            let destinationURL = snapshot.appendingPathComponent(relativePath)
            let isDirectory = (try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory {
                try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            } else if sourceURL.pathExtension.localizedCaseInsensitiveCompare("md") == .orderedSame {
                guard copiedMarkdownFiles < maxMarkdownFiles else { continue }
                try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                copiedMarkdownFiles += 1
            }
        }

        return snapshot
    }
}
