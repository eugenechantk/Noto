import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NoteEditorScreen")

struct NoteEditorScreen: View {
    var store: MarkdownNoteStore
    var isNew: Bool = false
    var fileWatcher: VaultFileWatcher?
    var onDelete: (() -> Void)? = nil
    private var externallyDeletingNoteID: Binding<UUID?>?

    @State private var note: MarkdownNote
    @State private var content: String = ""
    @State private var latestEditorText: String = ""
    @State private var lastPersistedText: String = ""
    @State private var hasLoaded = false
    @State private var isDownloading = false
    @State private var downloadFailed = false
    @State private var renameTask: Task<Void, Never>?
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var hasPendingLocalEdits = false
    @State private var editorSessionID = UUID()
    @State private var pendingRemoteSnapshot: NoteSyncSnapshot?

    init(
        store: MarkdownNoteStore,
        note: MarkdownNote,
        isNew: Bool = false,
        fileWatcher: VaultFileWatcher? = nil,
        onDelete: (() -> Void)? = nil,
        externallyDeletingNoteID: Binding<UUID?>? = nil
    ) {
        self.store = store
        self.isNew = isNew
        self.fileWatcher = fileWatcher
        self.onDelete = onDelete
        self.externallyDeletingNoteID = externallyDeletingNoteID
        _note = State(initialValue: note)
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if downloadFailed {
                ContentUnavailableView(
                    "Download Failed",
                    systemImage: "exclamationmark.icloud",
                    description: Text("Could not download this note from iCloud. Check your connection and try again.")
                )
            } else if isDownloading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Downloading from iCloud...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 0) {
                    if pendingRemoteSnapshot != nil {
                        remoteUpdateBanner
                    }
                    TextKit2EditorView(text: $content, autoFocus: isNew, onTextChange: handleEditorChange)
                }
            }
        }
        .navigationTitle(MarkdownNote.titleFrom(content))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                }
                .accessibilityIdentifier("back_button")
            }
        }
        #elseif os(macOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                    Label("Delete Note", systemImage: "trash")
                }
                .accessibilityIdentifier("delete_note_button")
                .keyboardShortcut(.delete, modifiers: [.command])
            }
        }
        #endif
        .task {
            guard !hasLoaded else { return }
            await loadNoteContent()
        }
        .onDisappear {
            renameTask?.cancel()
            persistFinalSnapshotIfNeeded()
            if externallyDeletingNoteID?.wrappedValue == note.id {
                externallyDeletingNoteID?.wrappedValue = nil
            }
        }
        .onChange(of: fileWatcher?.changeCount) { _, _ in
            reloadIfChangedExternally()
        }
        .onReceive(NotificationCenter.default.publisher(for: NoteSyncCenter.notificationName)) { notification in
            guard let snapshot = notification.object as? NoteSyncSnapshot else { return }
            handleRemoteSnapshot(snapshot)
        }
        .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirmation) {
            Button("Delete Note", role: .destructive) {
                deleteCurrentNote()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var remoteUpdateBanner: some View {
        HStack(spacing: 12) {
            Label("Updated in another window", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button("Keep Mine") {
                pendingRemoteSnapshot = nil
            }
            Button("Reload") {
                guard let snapshot = pendingRemoteSnapshot else { return }
                applyRemoteSnapshot(snapshot)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    /// Reloads the editor content if the file was changed externally (e.g. iCloud sync).
    /// Compares note bodies (stripped frontmatter) to avoid self-triggered reloads
    /// caused by our own saves updating the `updated:` timestamp.
    private func reloadIfChangedExternally() {
        guard hasLoaded, !isDownloading else { return }
        if let changedURL = fileWatcher?.lastChangedFileURL, changedURL != note.fileURL {
            DebugTrace.record("editor reload skipped other-file changed=\(changedURL.lastPathComponent) note=\(note.fileURL.lastPathComponent)")
            return
        }
        if hasPendingLocalEdits {
            logger.info("Skipped external reload because local edits are pending")
            DebugTrace.record("editor reload skipped pending-edits note=\(note.fileURL.lastPathComponent)")
            return
        }
        let diskContent = store.readContent(of: note)
        guard !diskContent.isEmpty else { return }

        // Compare bodies only — our own saves update the frontmatter timestamp,
        // which would cause a false-positive mismatch on the full content string.
        let diskBody = MarkdownNote.stripFrontmatter(diskContent)
        let editorBody = MarkdownNote.stripFrontmatter(content)
        guard diskBody != editorBody else {
            DebugTrace.record("editor reload skipped same-body note=\(note.fileURL.lastPathComponent)")
            return
        }

        DebugTrace.record("editor reloaded-from-disk note=\(note.fileURL.lastPathComponent) \(DebugTrace.textSummary(diskContent))")
        pendingRemoteSnapshot = nil
        applyLoadedContent(diskContent)
        logger.info("Reloaded note from disk after external change")
    }

    private func loadNoteContent() async {
        if CoordinatedFileManager.isDownloaded(at: note.fileURL) {
            DebugTrace.record("editor load note=\(note.fileURL.lastPathComponent)")
            applyLoadedContent(store.readContent(of: note))
            hasLoaded = true
        } else {
            isDownloading = true
            CoordinatedFileManager.startDownloading(at: note.fileURL)
            // Poll until downloaded, with timeout
            let deadline = Date().addingTimeInterval(30)
            while !CoordinatedFileManager.isDownloaded(at: note.fileURL) {
                if Date() > deadline {
                    downloadFailed = true
                    isDownloading = false
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
                if Task.isCancelled { return }
            }
            applyLoadedContent(store.readContent(of: note))
            hasLoaded = true
            isDownloading = false
        }
    }

    private func handleEditorChange(_ newText: String) {
        guard !isDeleting else { return }
        DebugTrace.record("editor handle change note=\(note.fileURL.lastPathComponent) \(DebugTrace.textSummary(newText))")
        applyEditorText(newText, scheduleRename: true)
    }

    private func scheduleRename() {
        guard !isDeleting else { return }
        renameTask?.cancel()
        renameTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, !isDeleting else { return }
            note = store.renameFileIfNeeded(for: note)
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

    private func persistFinalSnapshotIfNeeded() {
        let isExternallyDeleting = externallyDeletingNoteID?.wrappedValue == note.id
        guard !isDownloading, !downloadFailed, !isDeleting, !isExternallyDeleting else { return }
        guard hasPendingLocalEdits || latestEditorText != lastPersistedText else { return }
        DebugTrace.record("editor final persist note=\(note.fileURL.lastPathComponent) \(DebugTrace.textSummary(latestEditorText))")
        persistEditorText(latestEditorText)
        note = store.renameFileIfNeeded(for: note)
    }

    private func deleteCurrentNote() {
        renameTask?.cancel()
        isDeleting = true
        let noteToDelete = note
        guard store.deleteNote(noteToDelete) else {
            isDeleting = false
            return
        }
        onDelete?()
        dismiss()
    }

    private func applyEditorText(_ newText: String, scheduleRename shouldScheduleRename: Bool) {
        latestEditorText = newText
        content = newText
        hasPendingLocalEdits = true
        DebugTrace.record("editor apply text note=\(note.fileURL.lastPathComponent) scheduleRename=\(shouldScheduleRename)")
        persistEditorText(newText)
        if shouldScheduleRename {
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

    private func handleRemoteSnapshot(_ snapshot: NoteSyncSnapshot) {
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

    private func applyRemoteSnapshot(_ snapshot: NoteSyncSnapshot) {
        DebugTrace.record("editor remote applied note=\(note.fileURL.lastPathComponent) \(DebugTrace.textSummary(snapshot.text))")
        pendingRemoteSnapshot = nil
        applyLoadedContent(snapshot.text)
    }
}
