import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NoteEditorScreen")

struct NoteEditorScreen: View {
    @ObservedObject var store: MarkdownNoteStore
    var isNew: Bool = false
    var fileWatcher: VaultFileWatcher?

    @State private var note: MarkdownNote
    @State private var content: String = ""
    @State private var hasLoaded = false
    @State private var isDownloading = false
    @State private var saveTask: Task<Void, Never>?
    @State private var renameTask: Task<Void, Never>?

    init(store: MarkdownNoteStore, note: MarkdownNote, isNew: Bool = false, fileWatcher: VaultFileWatcher? = nil) {
        self.store = store
        self.isNew = isNew
        self.fileWatcher = fileWatcher
        _note = State(initialValue: note)
    }

    var body: some View {
        Group {
            if isDownloading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Downloading from iCloud...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                MarkdownEditorView(text: $content, autoFocus: isNew) { _ in
                    scheduleSave()
                    scheduleRename()
                }
            }
        }
        .navigationTitle(MarkdownNote.titleFrom(content))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !hasLoaded {
                loadNoteContent()
            }
        }
        .onDisappear {
            saveTask?.cancel()
            renameTask?.cancel()
            if !isDownloading {
                note = store.saveContent(content, for: note)
                note = store.renameFileIfNeeded(for: note)
            }
        }
        .onChange(of: fileWatcher?.changeCount) { _, _ in
            reloadIfChangedExternally()
        }
    }

    /// Reloads the editor content if the file was changed externally (e.g. iCloud sync).
    /// Only reloads if the on-disk content differs from what's in the editor.
    private func reloadIfChangedExternally() {
        guard hasLoaded, !isDownloading else { return }
        let diskContent = store.readContent(of: note)
        if diskContent != content && !diskContent.isEmpty {
            content = diskContent
            logger.info("Reloaded note from disk after external change")
        }
    }

    private func loadNoteContent() {
        if CoordinatedFileManager.isDownloaded(at: note.fileURL) {
            content = store.readContent(of: note)
            hasLoaded = true
        } else {
            isDownloading = true
            CoordinatedFileManager.startDownloading(at: note.fileURL)
            // Poll until downloaded
            Task { @MainActor in
                while !CoordinatedFileManager.isDownloaded(at: note.fileURL) {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                content = store.readContent(of: note)
                hasLoaded = true
                isDownloading = false
            }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            note = store.saveContent(content, for: note)
        }
    }

    private func scheduleRename() {
        renameTask?.cancel()
        renameTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            note = store.renameFileIfNeeded(for: note)
        }
    }
}
