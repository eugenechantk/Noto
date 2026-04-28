import Foundation
import NotoSearch
import NotoVault
import Observation

@MainActor
@Observable
final class VaultController {
    let vaultURL: URL
    let directoryLoader: VaultDirectoryLoader

    private(set) var rootStore: MarkdownNoteStore

    var rootItems: [DirectoryItem] {
        rootStore.items
    }

    var isLoadingRoot: Bool {
        rootStore.isLoadingItems
    }

    init(
        vaultURL: URL,
        directoryLoader: VaultDirectoryLoader = VaultDirectoryLoader()
    ) {
        self.vaultURL = vaultURL
        self.directoryLoader = directoryLoader
        self.rootStore = MarkdownNoteStore(
            vaultURL: vaultURL,
            directoryLoader: directoryLoader
        )
    }

    func loadRoot() {
        rootStore.loadItems()
    }

    func refreshRootForForegroundActivation() {
        rootStore.refreshForForegroundActivation()
    }

    func store(for directoryURL: URL, autoload: Bool = true) -> MarkdownNoteStore {
        MarkdownNoteStore(
            directoryURL: directoryURL,
            vaultRootURL: vaultURL,
            autoload: autoload,
            directoryLoader: directoryLoader
        )
    }

    func store(for folder: NotoFolder, autoload: Bool = true) -> MarkdownNoteStore {
        store(for: folder.folderURL, autoload: autoload)
    }

    func loadFolder(_ folder: NotoFolder) -> [DirectoryItem] {
        let folderStore = store(for: folder)
        return folderStore.items
    }

    func openNote(_ note: MarkdownNote, in store: MarkdownNoteStore) -> String {
        store.readContent(of: note)
    }

    func importImageAttachment(data: Data, suggestedFilename: String?, in store: MarkdownNoteStore) throws -> VaultImageAttachment {
        try store.importImageAttachment(data: data, suggestedFilename: suggestedFilename)
    }

    func importImageAttachment(fileURL: URL, in store: MarkdownNoteStore) throws -> VaultImageAttachment {
        try store.importImageAttachment(fileURL: fileURL)
    }

    @discardableResult
    func updateMetadataFromContent(_ content: String, for note: MarkdownNote, in store: MarkdownNoteStore) -> MarkdownNote {
        store.updateMetadataFromContent(content, for: note)
    }

    @discardableResult
    func createNote(in store: MarkdownNoteStore? = nil) -> (store: MarkdownNoteStore, note: MarkdownNote) {
        let targetStore = store ?? rootStore
        return (targetStore, targetStore.createNote())
    }

    @discardableResult
    func save(_ content: String, for note: MarkdownNote, in store: MarkdownNoteStore) -> MarkdownNoteStore.SaveResult {
        store.saveContent(content, for: note)
    }

    @discardableResult
    func renameIfNeeded(_ note: MarkdownNote, in store: MarkdownNoteStore) -> MarkdownNote {
        store.renameFileIfNeeded(for: note)
    }

    @discardableResult
    func move(_ note: MarkdownNote, to destinationDirectory: URL, in store: MarkdownNoteStore) -> MarkdownNote {
        store.moveNote(note, to: destinationDirectory)
    }

    @discardableResult
    func move(_ folder: NotoFolder, to destinationDirectory: URL, in store: MarkdownNoteStore) -> NotoFolder {
        store.moveFolder(folder, to: destinationDirectory)
    }

    @discardableResult
    func delete(_ note: MarkdownNote, in store: MarkdownNoteStore) -> Bool {
        store.deleteNote(note)
    }

    func delete(_ folder: NotoFolder, in store: MarkdownNoteStore) {
        store.deleteFolder(folder)
    }

    func delete(_ item: DirectoryItem, in store: MarkdownNoteStore) {
        store.deleteItem(item)
    }

    @discardableResult
    func createFolder(named name: String, in store: MarkdownNoteStore? = nil) -> NotoFolder {
        let targetStore = store ?? rootStore
        return targetStore.createFolder(name: name)
    }

    func todayNote() -> (store: MarkdownNoteStore, note: MarkdownNote) {
        rootStore.todayNote()
    }

    func note(atVaultRelativePath relativePath: String) -> (store: MarkdownNoteStore, note: MarkdownNote)? {
        rootStore.note(atVaultRelativePath: relativePath)
    }

    func note(withID noteID: UUID) -> (store: MarkdownNoteStore, note: MarkdownNote)? {
        rootStore.note(withID: noteID)
    }

    func vaultRelativePath(for fileURL: URL) -> String? {
        rootStore.vaultRelativePath(for: fileURL)
    }

    func pageMentions(
        matching query: String,
        excluding note: MarkdownNote? = nil,
        limit: Int = 5,
        allowEmptyQuery: Bool = false
    ) -> [PageMentionDocument] {
        rootStore.pageMentionDocuments(
            matching: query,
            excluding: note?.fileURL,
            limit: limit,
            allowEmptyQuery: allowEmptyQuery
        )
    }

    func search(
        query: String,
        scope: SearchScope = .titleAndContent,
        limit: Int = 60
    ) throws -> [SearchResult] {
        let indexer = MarkdownSearchIndexer(vaultURL: vaultURL)
        let engine = MarkdownSearchEngine(store: try indexer.openStore(), vaultURL: vaultURL)
        return try engine.search(query, scope: scope, limit: limit)
    }
}
