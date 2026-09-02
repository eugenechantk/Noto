import SwiftUI

/// Opens one note in the shared TextKit 2 editor with autosave, find, and
/// iCloud-download handling — all owned by `NoteEditorSession`/`EditorContentView`.
struct NoteScreen: View {
    let vaultController: VaultController
    @State private var session: NoteEditorSession
    @State private var isFindVisible = false
    @State private var findQuery = ""
    @State private var findNavigationRequest: EditorFindNavigationRequest?
    @State private var findStatus = EditorFindStatus()
    @State private var findRequestCounter = 0

    init(store: MarkdownNoteStore, note: MarkdownNote, vaultController: VaultController) {
        self.vaultController = vaultController
        _session = State(initialValue: NoteEditorSession(store: store, note: note, vaultController: vaultController))
    }

    var body: some View {
        EditorContentView(
            session: session,
            isFindVisible: $isFindVisible,
            findQuery: $findQuery,
            findNavigationRequest: $findNavigationRequest,
            findStatus: $findStatus,
            pageMentionProvider: { query in
                vaultController.rootStore.pageMentionDocuments(matching: query)
            },
            onFindNavigate: { direction in
                findRequestCounter += 1
                findNavigationRequest = EditorFindNavigationRequest(id: findRequestCounter, direction: direction)
            },
            keyboardToolbarStyle: .floating
        )
        .background(NotoTheme.background.ignoresSafeArea())
        .navigationTitle(session.note.title.isEmpty ? "Untitled" : session.note.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Find", systemImage: "magnifyingglass") {
                    withAnimation(.easeInOut(duration: 0.14)) { isFindVisible.toggle() }
                }
                .accessibilityIdentifier("noteFindButton")
            }
        }
        .accessibilityIdentifier("noteScreen")
        .task(id: session.note.id) {
            guard !session.hasLoaded else { return }
            await session.loadNoteContent()
        }
        .onDisappear {
            session.cancelBackgroundWork()
            session.persistFinalSnapshotIfNeeded(isExternallyDeleting: false)
        }
    }
}
