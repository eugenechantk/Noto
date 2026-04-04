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
    @State private var hasLoaded = false
    @State private var isDownloading = false
    @State private var downloadFailed = false
    @State private var renameTask: Task<Void, Never>?
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

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
                TextKit2EditorView(text: $content, autoFocus: isNew, onTextChange: handleEditorChange)
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
        .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirmation) {
            Button("Delete Note", role: .destructive) {
                deleteCurrentNote()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Reloads the editor content if the file was changed externally (e.g. iCloud sync).
    private func reloadIfChangedExternally() {
        guard hasLoaded, !isDownloading else { return }
        let diskContent = store.readContent(of: note)
        if diskContent != content && !diskContent.isEmpty {
            content = diskContent
            latestEditorText = diskContent
            logger.info("Reloaded note from disk after external change")
        }
    }

    private func loadNoteContent() async {
        if CoordinatedFileManager.isDownloaded(at: note.fileURL) {
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
        content = newText
        latestEditorText = newText
        note = store.updateTitleFromContent(newText, for: note)
        note = store.saveContent(newText, for: note)
        scheduleRename()
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
        content = text
        latestEditorText = text
    }

    private func persistFinalSnapshotIfNeeded() {
        let isExternallyDeleting = externallyDeletingNoteID?.wrappedValue == note.id
        guard !isDownloading, !downloadFailed, !isDeleting, !isExternallyDeleting else { return }
        note = store.saveContent(latestEditorText, for: note)
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
}
