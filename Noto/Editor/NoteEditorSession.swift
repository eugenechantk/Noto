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

    private var renameTask: Task<Void, Never>?

    init(store: MarkdownNoteStore, note: MarkdownNote, isNew: Bool = false) {
        self.store = store
        self.note = note
        self.isNew = isNew
    }

    func loadNoteContent() async {
        downloadFailed = false
        isDownloading = false

        // In security-scoped iCloud folders, ubiquitous metadata can lag behind
        // actual file availability. Prefer a real coordinated read first.
        if let readableContent = CoordinatedFileManager.readString(from: note.fileURL) {
            DebugTrace.record("editor load readable note=\(note.fileURL.lastPathComponent)")
            applyLoadedContent(readableContent)
            hasLoaded = true
            return
        }

        guard !CoordinatedFileManager.isDownloaded(at: note.fileURL) else {
            DebugTrace.record("editor load unreadable-current note=\(note.fileURL.lastPathComponent)")
            downloadFailed = true
            return
        }

        isDownloading = true
        CoordinatedFileManager.startDownloading(at: note.fileURL)
        let deadline = Date().addingTimeInterval(30)

        while Date() <= deadline {
            if Task.isCancelled { return }

            if let readableContent = CoordinatedFileManager.readString(from: note.fileURL) {
                DebugTrace.record("editor load downloaded note=\(note.fileURL.lastPathComponent)")
                applyLoadedContent(readableContent)
                hasLoaded = true
                isDownloading = false
                return
            }

            try? await Task.sleep(for: .milliseconds(500))
        }

        DebugTrace.record("editor load download-timeout note=\(note.fileURL.lastPathComponent)")
        downloadFailed = true
        isDownloading = false
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
        if hasPendingLocalEdits || latestEditorText != lastPersistedText {
            DebugTrace.record("editor final persist note=\(note.fileURL.lastPathComponent) \(DebugTrace.textSummary(latestEditorText))")
            persistEditorText(latestEditorText)
        }
    }

    func markDeleting() {
        renameTask?.cancel()
        isDeleting = true
    }

    func finishDeleteAttempt() {
        isDeleting = false
    }

    func cancelBackgroundWork() {
        renameTask?.cancel()
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
        persistEditorText(newText)
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
