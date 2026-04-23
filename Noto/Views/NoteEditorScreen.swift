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
    var onOpenDocumentLink: ((String) -> Void)? = nil
    var canNavigateBack = false
    var canNavigateForward = false
    var onNavigateBack: (() -> Void)? = nil
    var onNavigateForward: (() -> Void)? = nil
    var leadingChromeControls: EditorLeadingChromeControls = .none
    var chromeMode: EditorChromeMode
    private var externallyDeletingNoteID: Binding<UUID?>?

    @State private var session: NoteEditorSession
    @State private var showDeleteConfirmation = false
    @State private var statusCount = WordCounter.Count(words: 0, characters: 0)
    private let wordCounter = WordCounter()

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
        onOpenDocumentLink: ((String) -> Void)? = nil,
        canNavigateBack: Bool = false,
        canNavigateForward: Bool = false,
        onNavigateBack: (() -> Void)? = nil,
        onNavigateForward: (() -> Void)? = nil,
        leadingChromeControls: EditorLeadingChromeControls = .none,
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
        self.onOpenDocumentLink = onOpenDocumentLink
        self.canNavigateBack = canNavigateBack
        self.canNavigateForward = canNavigateForward
        self.onNavigateBack = onNavigateBack
        self.onNavigateForward = onNavigateForward
        self.leadingChromeControls = leadingChromeControls
        self.externallyDeletingNoteID = externallyDeletingNoteID
        self.chromeMode = chromeMode
        _session = State(initialValue: NoteEditorSession(store: store, note: note, isNew: isNew))
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        EditorContentView(
            session: session,
            pageMentionProvider: pageMentionDocuments(matching:),
            onOpenDocumentLink: onOpenDocumentLink
        )
        .background(AppTheme.background)
        .foregroundStyle(AppTheme.primaryText)
        .tint(AppTheme.primaryText)
        #if os(iOS)
        .modifier(EditorNavigationChrome(
            mode: chromeMode,
            vaultRootURL: store.vaultRootURL,
            noteFileURL: session.note.fileURL,
            statusCount: statusCount,
            leadingControls: leadingChromeControls,
            onTapBreadcrumbLevel: onTapBreadcrumbLevel,
            onOpenTodayNote: onOpenTodayNote,
            onCreateRootNote: onCreateRootNote,
            onDeleteRequested: { showDeleteConfirmation = true },
            onDismiss: { dismiss() }
        ))
        .simultaneousGesture(navigationHistorySwipeGesture)
        #elseif os(macOS)
        .modifier(EditorNavigationChrome(
            mode: chromeMode,
            title: MarkdownNote.titleFrom(session.content),
            vaultRootURL: store.vaultRootURL,
            noteFileURL: session.note.fileURL,
            statusCount: statusCount,
            canNavigateBack: canNavigateBack,
            canNavigateForward: canNavigateForward,
            onNavigateBack: onNavigateBack,
            onNavigateForward: onNavigateForward,
            onOpenTodayNote: onOpenTodayNote,
            onTapBreadcrumbLevel: onTapBreadcrumbLevel,
            onDeleteRequested: { showDeleteConfirmation = true }
        ))
        #endif
        .task {
            guard !session.hasLoaded else { return }
            await session.loadNoteContent()
        }
        .onChange(of: session.content, initial: true) { _, updatedContent in
            statusCount = wordCounter.count(in: updatedContent)
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

    private func pageMentionDocuments(matching query: String) -> [PageMentionDocument] {
        #if os(iOS)
        store.pageMentionDocuments(
            matching: query,
            excluding: session.note.fileURL,
            limit: 50
        )
        #else
        store.pageMentionDocuments(matching: query, excluding: session.note.fileURL)
        #endif
    }

    #if os(iOS)
    private var navigationHistorySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 36, coordinateSpace: .local)
            .onEnded { value in
                let horizontalDistance = value.translation.width
                let verticalDistance = value.translation.height
                guard abs(horizontalDistance) >= 80,
                      abs(horizontalDistance) > abs(verticalDistance) * 1.4 else {
                    return
                }

                if horizontalDistance > 0, canNavigateBack {
                    onNavigateBack?()
                } else if horizontalDistance < 0, canNavigateForward {
                    onNavigateForward?()
                }
            }
    }
    #endif
}
