import Foundation
import NotoVault
import os.log

private let sessionLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NoteEditorSession")

@MainActor
@Observable
final class NoteEditorSession {
    var store: MarkdownNoteStore
    let vaultController: VaultController
    var isNew: Bool

    var note: MarkdownNote
    var content: String = ""
    var latestEditorText: String = ""
    var lastPersistedText: String = ""
    var hasLoaded = false
    var isDownloading = false
    var downloadFailed = false
    var isDeleting = false
    var hasPendingLocalEdits = false
    var pendingRemoteSnapshot: NoteSyncSnapshot?

    let editorSessionID = UUID()

    private static let titleRenameDebounce: Duration = .milliseconds(800)
    private static let autosaveDebounce: Duration = .milliseconds(500)

    private var renameTask: Task<Void, Never>?
    private var autosaveTask: Task<Void, Never>?

    init(
        store: MarkdownNoteStore,
        note: MarkdownNote,
        isNew: Bool = false,
        vaultController: VaultController? = nil
    ) {
        self.store = store
        self.vaultController = vaultController ?? VaultController(
            vaultURL: store.vaultRootURL,
            directoryLoader: store.directoryLoader
        )
        self.note = note
        self.isNew = isNew
        if let cached = NoteContentCache.get(note.id) {
            self.content = cached
            self.latestEditorText = cached
            self.lastPersistedText = cached
            self.hasLoaded = true
        }
    }

    /// Reuses this session for a different note without tearing down the view.
    /// Persists pending edits for the outgoing note, then loads cached content
    /// for the incoming note (or marks it unloaded if no cache hit).
    func switchTo(note newNote: MarkdownNote, store newStore: MarkdownNoteStore, isNew newIsNew: Bool) {
        guard newNote.id != note.id else {
            DebugTrace.record("session switchTo same-id id=\(note.id) file=\(newNote.fileURL.lastPathComponent) oldFile=\(note.fileURL.lastPathComponent)")
            store = newStore
            isNew = newIsNew
            return
        }
        DebugTrace.record("session switchTo new-id old=\(note.id) new=\(newNote.id) file=\(newNote.fileURL.lastPathComponent)")
        persistFinalSnapshotIfNeeded(isExternallyDeleting: false)
        renameTask?.cancel()
        autosaveTask?.cancel()
        renameTask = nil
        autosaveTask = nil

        NoteContentCache.set(note.id, content: latestEditorText)

        store = newStore
        isNew = newIsNew
        note = newNote

        if let cached = NoteContentCache.get(newNote.id) {
            DebugTrace.record("session switchTo cache-hit id=\(newNote.id) \(DebugTrace.textSummary(cached))")
            content = cached
            latestEditorText = cached
            lastPersistedText = cached
            hasLoaded = true
        } else {
            DebugTrace.record("session switchTo cache-miss id=\(newNote.id)")
            content = ""
            latestEditorText = ""
            lastPersistedText = ""
            hasLoaded = false
        }
        hasPendingLocalEdits = false
        downloadFailed = false
        isDownloading = false
        pendingRemoteSnapshot = nil
        isDeleting = false
    }

    func loadNoteContent() async {
        downloadFailed = false
        isDownloading = false

        let fileURL = note.fileURL
        switch await Self.loadReadableContent(from: fileURL) {
        case .readable(let readableContent):
            DebugTrace.record("editor load readable note=\(fileURL.lastPathComponent)")
            applyLoadedContent(readableContent)
            hasLoaded = true
        case .unreadableCurrent:
            DebugTrace.record("editor load unreadable-current note=\(note.fileURL.lastPathComponent)")
            downloadFailed = true
        case .needsDownload:
            isDownloading = true
            let downloadedContent = await Self.downloadReadableContent(from: fileURL)
            guard !Task.isCancelled else { return }

            if let downloadedContent {
                DebugTrace.record("editor load downloaded note=\(fileURL.lastPathComponent)")
                applyLoadedContent(downloadedContent)
                hasLoaded = true
                isDownloading = false
            } else {
                DebugTrace.record("editor load download-timeout note=\(fileURL.lastPathComponent)")
                downloadFailed = true
                isDownloading = false
            }
        }
    }

    func handleEditorChange(_ newText: String) {
        guard !isDeleting else { return }
        DebugTrace.record("editor handle change note=\(note.fileURL.lastPathComponent) \(DebugTrace.textSummary(newText))")
        applyEditorText(newText, scheduleRename: true)
    }

    /// Apply a structured edit made OUTSIDE the text view (e.g. the Properties
    /// sheet editing frontmatter). Updates `content` so the bound editor text view
    /// adopts the change, and persists synchronously so the edit survives even if
    /// the editor never refocuses. Use for programmatic markdown replacement, not
    /// for keystroke-driven edits (those go through `handleEditorChange`).
    func applyExternalContentEdit(_ newMarkdown: String) {
        guard !isDeleting, newMarkdown != content else { return }
        DebugTrace.record("editor external edit note=\(note.fileURL.lastPathComponent) \(DebugTrace.textSummary(newMarkdown))")
        autosaveTask?.cancel()
        autosaveTask = nil
        latestEditorText = newMarkdown
        hasPendingLocalEdits = true
        persistEditorText(newMarkdown, force: true)
    }

    func importImageAttachment(data: Data, suggestedFilename: String?) throws -> VaultImageAttachment {
        try vaultController.importImageAttachment(data: data, suggestedFilename: suggestedFilename, in: store)
    }

    func importImageAttachment(fileURL: URL) throws -> VaultImageAttachment {
        try vaultController.importImageAttachment(fileURL: fileURL, in: store)
    }

    func handleExternalChange(changedURL: URL?) {
        guard hasLoaded, !isDownloading else { return }
        if let changedURL, changedURL != note.fileURL {
            DebugTrace.record("editor reload skipped other-file changed=\(changedURL.lastPathComponent) note=\(note.fileURL.lastPathComponent)")
            return
        }
        if hasPendingLocalEdits {
            sessionLogger.info("Skipped external reload because local edits are pending")
            DebugTrace.record("editor reload skipped pending-edits note=\(note.fileURL.lastPathComponent)")
            return
        }

        let diskContent = vaultController.openNote(note, in: store)
        guard !diskContent.isEmpty else { return }

        let diskBody = MarkdownNote.stripFrontmatter(diskContent)
        let editorBody = MarkdownNote.stripFrontmatter(content)
        guard diskBody != editorBody else {
            DebugTrace.record("editor reload skipped same-body note=\(note.fileURL.lastPathComponent)")
            return
        }

        DebugTrace.record("editor reloaded-from-disk note=\(note.fileURL.lastPathComponent) \(DebugTrace.textSummary(diskContent))")
        pendingRemoteSnapshot = nil
        applyLoadedContent(diskContent)
        sessionLogger.info("Reloaded note from disk after external change")
    }

    func handleRemoteSnapshot(_ snapshot: NoteSyncSnapshot) {
        guard hasLoaded, !isDownloading, !downloadFailed else { return }
        guard snapshot.sourceEditorID != editorSessionID else { return }
        guard snapshot.fileURL == note.fileURL else { return }
        guard snapshot.text != content else { return }

        if hasPendingLocalEdits {
            if pendingRemoteSnapshot?.savedAt ?? .distantPast <= snapshot.savedAt {
                pendingRemoteSnapshot = snapshot
            }
            DebugTrace.record("editor remote pending-conflict note=\(note.fileURL.lastPathComponent)")
            return
        }

        applyRemoteSnapshot(snapshot)
    }

    func reloadRemoteSnapshot() {
        guard let snapshot = pendingRemoteSnapshot else { return }
        applyRemoteSnapshot(snapshot)
    }

    func discardRemoteConflict() {
        pendingRemoteSnapshot = nil
    }

    func persistFinalSnapshotIfNeeded(isExternallyDeleting: Bool) {
        guard !isDownloading, !downloadFailed, !isDeleting, !isExternallyDeleting else { return }
        autosaveTask?.cancel()
        autosaveTask = nil
        if hasPendingLocalEdits || latestEditorText != lastPersistedText {
            DebugTrace.record("editor final persist note=\(note.fileURL.lastPathComponent) \(DebugTrace.textSummary(latestEditorText))")
            persistEditorText(latestEditorText)
        }
    }

    func markDeleting() {
        renameTask?.cancel()
        autosaveTask?.cancel()
        isDeleting = true
    }

    func finishDeleteAttempt() {
        isDeleting = false
    }

    @discardableResult
    func moveNote(to destinationDirectory: URL) -> MarkdownNote {
        renameTask?.cancel()
        autosaveTask?.cancel()
        autosaveTask = nil

        if hasPendingLocalEdits || latestEditorText != lastPersistedText {
            persistEditorText(latestEditorText)
        }

        let moved = vaultController.move(note, to: destinationDirectory, in: store)
        note = moved
        return moved
    }

    func deleteCurrentNote() -> Bool {
        let deleted = vaultController.delete(note, in: store)
        if deleted {
            NoteContentCache.invalidate(note.id)
        }
        return deleted
    }

    func replaceNoteFromParent(_ updatedNote: MarkdownNote) {
        guard updatedNote.id == note.id else { return }
        guard updatedNote.fileURL.standardizedFileURL != note.fileURL.standardizedFileURL ||
            updatedNote.title != note.title ||
            updatedNote.modifiedDate != note.modifiedDate else {
            return
        }
        note = updatedNote
    }

    func cancelBackgroundWork() {
        renameTask?.cancel()
        autosaveTask?.cancel()
    }

    private func scheduleRename() {
        guard !isDeleting else { return }
        renameTask?.cancel()
        renameTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.titleRenameDebounce)
            guard let self else { return }
            guard !Task.isCancelled, !self.isDeleting else { return }
            self.note = self.vaultController.renameIfNeeded(self.note, in: self.store)
        }
    }

    private func scheduleAutosave() {
        guard !isDeleting else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.autosaveDebounce)
            guard let self else { return }
            guard !Task.isCancelled, !self.isDeleting else { return }
            self.persistEditorText(self.latestEditorText)
            self.autosaveTask = nil
        }
    }

    private func applyLoadedContent(_ text: String) {
        DebugTrace.record("editor apply loaded note=\(note.fileURL.lastPathComponent) \(DebugTrace.textSummary(text))")
        content = text
        latestEditorText = text
        lastPersistedText = text
        hasPendingLocalEdits = false
        note = vaultController.updateMetadataFromContent(text, for: note, in: store)
        NoteContentCache.set(note.id, content: text)
    }

    private func applyEditorText(_ newText: String, scheduleRename shouldScheduleRename: Bool) {
        let previousTitle = note.title
        latestEditorText = newText
        hasPendingLocalEdits = true
        DebugTrace.record("editor apply text note=\(note.fileURL.lastPathComponent) scheduleRename=\(shouldScheduleRename)")
        note = vaultController.updateMetadataFromContent(newText, for: note, in: store)
        NoteContentCache.set(note.id, content: newText)
        scheduleAutosave()
        if shouldScheduleRename, note.title != previousTitle {
            scheduleRename()
        }
    }

    private func persistEditorText(_ text: String, force: Bool = false) {
        DebugTrace.record("editor persist start note=\(note.fileURL.lastPathComponent) \(DebugTrace.textSummary(text))")
        note = vaultController.updateMetadataFromContent(text, for: note, in: store)
        let saveResult = vaultController.save(text, for: note, in: store, force: force)
        content = text
        note = saveResult.note
        NoteContentCache.set(note.id, content: text)
        if saveResult.didWrite {
            lastPersistedText = text
            hasPendingLocalEdits = false
            pendingRemoteSnapshot = nil
            NoteSyncCenter.publish(
                NoteSyncSnapshot(
                    noteID: note.id,
                    fileURL: note.fileURL,
                    text: text,
                    sourceEditorID: editorSessionID,
                    savedAt: Date()
                )
            )
        }
        DebugTrace.record("editor persist end note=\(note.fileURL.lastPathComponent)")
    }

    private func applyRemoteSnapshot(_ snapshot: NoteSyncSnapshot) {
        DebugTrace.record("editor remote applied note=\(note.fileURL.lastPathComponent) \(DebugTrace.textSummary(snapshot.text))")
        pendingRemoteSnapshot = nil
        applyLoadedContent(snapshot.text)
    }
}

private extension NoteEditorSession {
    enum ContentLoadProbe: Sendable {
        case readable(String)
        case unreadableCurrent
        case needsDownload
    }

    /// How long the "just try reading it" probe may block before we assume the file
    /// still has to come down from iCloud. A materialized file reads in well under a
    /// millisecond; a `dataless` one blocks in the kernel until the file provider
    /// materializes it, which can take minutes or never finish.
    static let probeReadTimeout: TimeInterval = 2

    /// Per-attempt budget while polling for a file we asked iCloud to download. Each
    /// poll must be bounded too — otherwise the very first one blocks past the overall
    /// download deadline and the poll loop never gets to give up.
    static let downloadPollReadTimeout: TimeInterval = 3

    static let downloadDeadline: TimeInterval = 30

    static nonisolated func loadReadableContent(from fileURL: URL) async -> ContentLoadProbe {
        // In security-scoped iCloud folders, ubiquitous metadata can lag behind actual
        // file availability, so prefer a real read over `isDownloaded` — but bound it,
        // because on an evicted file that read never returns.
        switch await BoundedFileRead.run(timeout: probeReadTimeout, work: {
            CoordinatedFileManager.readString(from: fileURL)
        }) {
        case .value(let readableContent):
            return .readable(readableContent)
        case .timedOut:
            // Blocked in the kernel — the file is not locally available whatever the
            // metadata claims. Treat it as needing a download so the UI can say so.
            return .needsDownload
        case .failed:
            return CoordinatedFileManager.isDownloaded(at: fileURL)
                ? .unreadableCurrent
                : .needsDownload
        }
    }

    static nonisolated func downloadReadableContent(from fileURL: URL) async -> String? {
        CoordinatedFileManager.startDownloading(at: fileURL)
        let deadline = Date().addingTimeInterval(downloadDeadline)

        while Date() <= deadline {
            if Task.isCancelled { return nil }

            if case .value(let readableContent) = await BoundedFileRead.run(
                timeout: downloadPollReadTimeout,
                work: { CoordinatedFileManager.readString(from: fileURL) }
            ) {
                return readableContent
            }

            try? await Task.sleep(for: .milliseconds(500))
        }

        return nil
    }
}
