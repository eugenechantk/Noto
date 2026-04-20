import SwiftUI
import NotoVault

struct NoteEditorScreen: View {
    var store: MarkdownNoteStore
    var isNew: Bool = false
    var fileWatcher: VaultFileWatcher?
    var onDelete: (() -> Void)? = nil
    var onOpenTodayNote: (() -> Void)? = nil
    var onCreateRootNote: (() -> Void)? = nil
    var onTapBreadcrumbLevel: ((URL) -> Void)? = nil
    var onNoteUpdated: ((MarkdownNote) -> Void)? = nil
    var chromeMode: EditorChromeMode
    private var externallyDeletingNoteID: Binding<UUID?>?

    @State private var session: NoteEditorSession
    @State private var showDeleteConfirmation = false
    #if os(iOS)
    private let wordCounter = WordCounter()
    #endif

    init(
        store: MarkdownNoteStore,
        note: MarkdownNote,
        isNew: Bool = false,
        fileWatcher: VaultFileWatcher? = nil,
        onDelete: (() -> Void)? = nil,
        onOpenTodayNote: (() -> Void)? = nil,
        onCreateRootNote: (() -> Void)? = nil,
        onTapBreadcrumbLevel: ((URL) -> Void)? = nil,
        onNoteUpdated: ((MarkdownNote) -> Void)? = nil,
        externallyDeletingNoteID: Binding<UUID?>? = nil,
        chromeMode: EditorChromeMode = .platformDefault
    ) {
        self.store = store
        self.isNew = isNew
        self.fileWatcher = fileWatcher
        self.onDelete = onDelete
        self.onOpenTodayNote = onOpenTodayNote
        self.onCreateRootNote = onCreateRootNote
        self.onTapBreadcrumbLevel = onTapBreadcrumbLevel
        self.onNoteUpdated = onNoteUpdated
        self.externallyDeletingNoteID = externallyDeletingNoteID
        self.chromeMode = chromeMode
        _session = State(initialValue: NoteEditorSession(store: store, note: note, isNew: isNew))
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        EditorContentView(session: session)
        .background(AppTheme.background)
        .foregroundStyle(AppTheme.primaryText)
        .tint(AppTheme.primaryText)
        #if os(iOS)
        .modifier(EditorNavigationChrome(
            mode: chromeMode,
            vaultRootURL: store.vaultRootURL,
            noteFileURL: session.note.fileURL,
            statusCount: wordCounter.count(in: session.content),
            onTapBreadcrumbLevel: onTapBreadcrumbLevel,
            onOpenTodayNote: onOpenTodayNote,
            onCreateRootNote: onCreateRootNote,
            onDeleteRequested: { showDeleteConfirmation = true },
            onDismiss: { dismiss() }
        ))
        #elseif os(macOS)
        .modifier(EditorNavigationChrome(
            mode: chromeMode,
            title: MarkdownNote.titleFrom(session.content),
            onDeleteRequested: { showDeleteConfirmation = true }
        ))
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
        .onChange(of: session.note) { _, updatedNote in
            onNoteUpdated?(updatedNote)
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
