import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NoteEditorScreen")

struct NoteEditorScreen: View {
    var store: MarkdownNoteStore
    var isNew: Bool = false
    var fileWatcher: VaultFileWatcher?
    var onDelete: (() -> Void)? = nil
    private var externallyDeletingNoteID: Binding<UUID?>?

    @State private var session: NoteEditorSession
    @State private var showDeleteConfirmation = false

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
        _session = State(initialValue: NoteEditorSession(store: store, note: note, isNew: isNew))
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var session = session
        Group {
            if session.downloadFailed {
                ContentUnavailableView(
                    "Download Failed",
                    systemImage: "exclamationmark.icloud",
                    description: Text("Could not download this note from iCloud. Check your connection and try again.")
                )
            } else if session.isDownloading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Downloading from iCloud...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 0) {
                    if session.pendingRemoteSnapshot != nil {
                        remoteUpdateBanner
                    }
                    TextKit2EditorView(text: $session.content, autoFocus: session.isNew, onTextChange: session.handleEditorChange)
                }
            }
        }
        .navigationTitle(MarkdownNote.titleFrom(session.content))
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
            guard !session.hasLoaded else { return }
            await session.loadNoteContent()
        }
        .onDisappear {
            session.cancelBackgroundWork()
            session.persistFinalSnapshotIfNeeded(isExternallyDeleting: externallyDeletingNoteID?.wrappedValue == session.note.id)
            if externallyDeletingNoteID?.wrappedValue == session.note.id {
                externallyDeletingNoteID?.wrappedValue = nil
            }
        }
        .onChange(of: fileWatcher?.changeCount) { _, _ in
            session.handleExternalChange(changedURL: fileWatcher?.lastChangedFileURL)
        }
        .onReceive(NotificationCenter.default.publisher(for: NoteSyncCenter.notificationName)) { notification in
            guard let snapshot = notification.object as? NoteSyncSnapshot else { return }
            session.handleRemoteSnapshot(snapshot)
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
                session.discardRemoteConflict()
            }
            Button("Reload") {
                session.reloadRemoteSnapshot()
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

    private func deleteCurrentNote() {
        session.markDeleting()
        let noteToDelete = session.note
        guard session.store.deleteNote(noteToDelete) else {
            session.finishDeleteAttempt()
            return
        }
        onDelete?()
        dismiss()
    }
}
