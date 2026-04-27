import Foundation
import os.log

private let sessionLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NoteEditorSession")

@MainActor
@Observable
final class NoteEditorSession {
    let store: MarkdownNoteStore
    let isNew: Bool

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

    init(store: MarkdownNoteStore, note: MarkdownNote, isNew: Bool = false) {
        self.store = store
        self.note = note
        self.isNew = isNew
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

    func importImageAttachment(data: Data, suggestedFilename: String?) throws -> VaultImageAttachment {
        try store.importImageAttachment(data: data, suggestedFilename: suggestedFilename)
    }

    func importImageAttachment(fileURL: URL) throws -> VaultImageAttachment {
        try store.importImageAttachment(fileURL: fileURL)
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

        let diskContent = store.readContent(of: note)
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

        let moved = store.moveNote(note, to: destinationDirectory)
        note = moved
        return moved
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
            self.note = self.store.renameFileIfNeeded(for: self.note)
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
        note = store.updateTitleFromContent(text, for: note)
    }

    private func applyEditorText(_ newText: String, scheduleRename shouldScheduleRename: Bool) {
        let previousTitle = note.title
        latestEditorText = newText
        content = newText
        hasPendingLocalEdits = true
        DebugTrace.record("editor apply text note=\(note.fileURL.lastPathComponent) scheduleRename=\(shouldScheduleRename)")
        note = store.updateTitleFromContent(newText, for: note)
        scheduleAutosave()
        if shouldScheduleRename, note.title != previousTitle {
            scheduleRename()
        }
    }

    private func persistEditorText(_ text: String) {
        DebugTrace.record("editor persist start note=\(note.fileURL.lastPathComponent) \(DebugTrace.textSummary(text))")
        note = store.updateTitleFromContent(text, for: note)
        let saveResult = store.saveContent(text, for: note)
        note = saveResult.note
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

    static nonisolated func loadReadableContent(from fileURL: URL) async -> ContentLoadProbe {
        let task = Task<ContentLoadProbe, Never>.detached(priority: .userInitiated) {
            // In security-scoped iCloud folders, ubiquitous metadata can lag
            // behind actual file availability. Prefer a real read first.
            if let readableContent = CoordinatedFileManager.readString(from: fileURL) {
                return ContentLoadProbe.readable(readableContent)
            }
            return CoordinatedFileManager.isDownloaded(at: fileURL)
                ? ContentLoadProbe.unreadableCurrent
                : ContentLoadProbe.needsDownload
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    static nonisolated func downloadReadableContent(from fileURL: URL) async -> String? {
        let task = Task<String?, Never>.detached(priority: .userInitiated) {
            CoordinatedFileManager.startDownloading(at: fileURL)
            let deadline = Date().addingTimeInterval(30)

            while Date() <= deadline {
                if Task.isCancelled { return nil }

                if let readableContent = CoordinatedFileManager.readString(from: fileURL) {
                    return readableContent
                }

                try? await Task.sleep(for: .milliseconds(500))
            }

            return nil
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
