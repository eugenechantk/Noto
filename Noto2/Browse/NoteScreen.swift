import NotoVault
import SwiftUI

/// Opens one note in the shared TextKit 2 editor with Noto's non-AI More-menu
/// actions: find, properties, move, delete, and live counts.
struct NoteScreen: View {
    let store: MarkdownNoteStore
    let vaultController: VaultController
    var onNoteDeleted: () -> Void

    @State private var session: NoteEditorSession
    @State private var tagController: TagController
    @State private var isFindVisible = false
    @State private var findQuery = ""
    @State private var findNavigationRequest: EditorFindNavigationRequest?
    @State private var findStatus = EditorFindStatus()
    @State private var findRequestCounter = 0
    @State private var statusCount = WordCounter.Count(words: 0, characters: 0)
    @State private var wordCountTask: Task<Void, Never>?
    @State private var showProperties = false
    @State private var pendingMoveAfterProperties = false
    @State private var showMoveSheet = false
    @State private var showDeleteConfirmation = false

    @Environment(\.dismiss) private var dismiss

    private let wordCounter = WordCounter()

    init(
        store: MarkdownNoteStore,
        note: MarkdownNote,
        vaultController: VaultController,
        onNoteDeleted: @escaping () -> Void = {}
    ) {
        self.store = store
        self.vaultController = vaultController
        self.onNoteDeleted = onNoteDeleted
        _session = State(initialValue: NoteEditorSession(store: store, note: note, vaultController: vaultController))
        _tagController = State(initialValue: TagController(vaultURL: vaultController.vaultURL))
    }

    var body: some View {
        EditorContentView(
            session: session,
            isFindVisible: $isFindVisible,
            findQuery: $findQuery,
            findNavigationRequest: $findNavigationRequest,
            findStatus: $findStatus,
            pageMentionProvider: { query in
                vaultController.rootStore.pageMentionDocuments(
                    matching: query,
                    excluding: session.note.fileURL
                )
            },
            onFindNavigate: navigateFind,
            keyboardToolbarStyle: .floating
        )
        .background(NotoTheme.background.ignoresSafeArea())
        .navigationTitle(session.note.title.isEmpty ? "Untitled" : session.note.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NoteEditorActionsMenu(
                    statusCount: statusCount,
                    onSearchRequested: showFind,
                    onShowProperties: presentProperties,
                    propertyCount: propertyCount,
                    onMoveRequested: { showMoveSheet = true },
                    onDeleteRequested: { showDeleteConfirmation = true }
                )
            }
        }
        .task(id: session.note.id) {
            guard !session.hasLoaded else { return }
            await session.loadNoteContent()
        }
        .onChange(of: session.content, initial: true) { _, content in
            scheduleStatusCountUpdate(for: content)
        }
        .onDisappear {
            session.cancelBackgroundWork()
            wordCountTask?.cancel()
            session.persistFinalSnapshotIfNeeded(isExternallyDeleting: false)
        }
        .sheet(isPresented: $showProperties, onDismiss: openPendingMoveIfNeeded) {
            PropertiesSheet(
                session: session,
                onClose: { showProperties = false },
                onMoveFolder: {
                    pendingMoveAfterProperties = true
                    showProperties = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .environment(tagController)
        }
        .sheet(isPresented: $showMoveSheet) {
            MoveNoteDestinationPicker(
                vaultRootURL: store.vaultRootURL,
                currentDirectoryURL: session.note.fileURL.deletingLastPathComponent(),
                directoryLoader: store.directoryLoader,
                onCancel: { showMoveSheet = false },
                onMove: moveCurrentNote
            )
        }
        .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirmation) {
            Button("Delete Note", role: .destructive, action: deleteCurrentNote)
                .accessibilityIdentifier("confirm_delete_note_button")
            Button("Cancel", role: .cancel) {}
        }
    }

    private var propertyCount: Int {
        EditableFrontmatterDocument(markdown: session.content)?.fields.count ?? 0
    }

    private func showFind() {
        withAnimation(.easeOut(duration: 0.16)) {
            isFindVisible = true
        }
    }

    private func navigateFind(_ direction: EditorFindNavigationDirection) {
        guard findStatus.matchCount > 0 else { return }
        findRequestCounter += 1
        findNavigationRequest = EditorFindNavigationRequest(id: findRequestCounter, direction: direction)
    }

    private func presentProperties() {
        tagController.load()
        tagController.rebuildMembership()
        withAnimation(.easeInOut(duration: 0.18)) {
            showProperties = true
        }
    }

    private func openPendingMoveIfNeeded() {
        guard pendingMoveAfterProperties else { return }
        pendingMoveAfterProperties = false
        showMoveSheet = true
    }

    private func moveCurrentNote(to destinationURL: URL) {
        _ = session.moveNote(to: destinationURL)
        showMoveSheet = false
    }

    private func deleteCurrentNote() {
        session.markDeleting()
        guard session.deleteCurrentNote() else {
            session.finishDeleteAttempt()
            return
        }
        onNoteDeleted()
        dismiss()
    }

    private func scheduleStatusCountUpdate(for content: String) {
        wordCountTask?.cancel()
        let wordCounter = wordCounter
        wordCountTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            let count = await Task.detached {
                wordCounter.count(in: content)
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                statusCount = count
            }
        }
    }
}
