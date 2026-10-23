import NotoVault
import SwiftUI

/// Opens one note in the shared TextKit 2 editor with Noto's non-AI More-menu
/// actions: find, properties, move, delete, and live counts.
struct NoteScreen: View {
    let store: MarkdownNoteStore
    let vaultController: VaultController
    var onNoteDeleted: () -> Void

    @State private var session: NoteEditorSession
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
    @State private var pinError: String?
    private let initialFindQuery: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// Set by `RootTabView`; nil in previews and tests.
    @Environment(VaultFileWatcher.self) private var fileWatcher: VaultFileWatcher?

    private let wordCounter = WordCounter()

    init(
        store: MarkdownNoteStore,
        note: MarkdownNote,
        isNew: Bool = false,
        vaultController: VaultController,
        onNoteDeleted: @escaping () -> Void = {},
        initialFindQuery: String? = nil
    ) {
        self.store = store
        self.vaultController = vaultController
        self.onNoteDeleted = onNoteDeleted
        self.initialFindQuery = initialFindQuery
        _session = State(initialValue: NoteEditorSession(
            store: store,
            note: note,
            isNew: isNew,
            vaultController: vaultController
        ))
    }

    var body: some View {
        editorSurface
            .background(NotoTheme.background.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarBackButtonHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Back").accessibilityIdentifier("libraryNoteBack")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NoteMarkdownShareLink(item: session.markdownShare)
                        .accessibilityIdentifier("share_note_button")
                }
                ToolbarItem(placement: .topBarTrailing) { noteActions }
            }
            .task(id: session.note.id) {
                if !session.hasLoaded { await session.loadNoteContent() }
                if let initialFindQuery, !initialFindQuery.isEmpty {
                    findQuery = initialFindQuery
                    isFindVisible = true
                }
            }
            // Pick up changes made outside this editor — another device via iCloud,
            // or Hermes appending a shared post's media. The session skips the
            // reload while local edits are unsaved.
            .onChange(of: fileWatcher?.changeCount) { _, _ in
                session.handleExternalChange(changedURL: fileWatcher?.lastChangedFileURL)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { session.handleExternalChange(changedURL: nil) }
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
                LibraryNoteInfoSheet(session: session, count: statusCount, onClose: { showProperties = false }, onMoveFolder: {
                    pendingMoveAfterProperties = true
                    showProperties = false
                })
                .presentationDetents([.fraction(0.8), .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showMoveSheet) {
                LibraryMoveNoteSheet(vaultController: vaultController, note: session.note, onCancel: { showMoveSheet = false }, onMove: moveCurrentNote)
            }
            .alert("Could not pin note", isPresented: Binding(get: { pinError != nil }, set: { if !$0 { pinError = nil } })) {
                Button("OK", role: .cancel) { pinError = nil }
            } message: { Text(pinError ?? "") }
            .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirmation) {
                Button("Delete Note", role: .destructive, action: deleteCurrentNote)
                    .accessibilityIdentifier("confirm_delete_note_button")
                Button("Cancel", role: .cancel) {}
            }
            .noteSharing()
    }

    private var noteActions: some View {
        Menu {
            Button(NotePinning.isPinned(in: session.content) ? "Unpin from Library" : "Pin to Library", systemImage: NotePinning.isPinned(in: session.content) ? "pin.slash" : "pin") { togglePin() }
                .accessibilityIdentifier("notePinAction")
            Button("Note info", systemImage: "info.circle", action: presentProperties)
                .accessibilityIdentifier("properties_menu_item")
            Button("Move to folder", systemImage: "folder", action: { showMoveSheet = true })
                .accessibilityIdentifier("move_note_menu_item")
            Button("Find in note", systemImage: "magnifyingglass", action: showFind)
                .accessibilityIdentifier("search_in_note_menu_item")
            Button("Copy note link", systemImage: "link", action: copyNoteLink)
                .accessibilityIdentifier("copy_note_link_menu_item")
            NoteMarkdownShareLink(item: session.markdownShare)
                .accessibilityIdentifier("share_note_menu_item")
            Divider()
            Button("Delete note", systemImage: "trash", role: .destructive) { showDeleteConfirmation = true }
                .accessibilityIdentifier("delete_note_menu_item")
        } label: { Image(systemName: "ellipsis") }
        .accessibilityLabel("Note actions")
        .accessibilityIdentifier("noteMoreMenu")
    }

    private func copyNoteLink() {
        guard let path = store.vaultRelativePath(for: session.note.fileURL),
              let url = Noto2LaunchRoute.openNoteURL(relativePath: path) else { return }
        NotePathClipboard.copy(url.absoluteString)
    }

    private func togglePin() {
        do { try LibraryNotePinAction.toggle(session: session) }
        catch { pinError = "The note could not be saved. Try again after it finishes downloading." }
    }

    private var editorSurface: some View { editorContent }

    private var editorContent: some View {
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

/// Pure layout math for the top chrome mask, separated so the transition can
/// be regression-tested without rendering SwiftUI or Liquid Glass.
struct Noto2TopChromeLayout: Equatable {
    static let tail: CGFloat = 36
    static let defaultBarRow: CGFloat = 44

    let totalHeight: CGFloat
    let statusBottom: CGFloat
    let chromeBottom: CGFloat

    init(chromeHeight: CGFloat, barRow: CGFloat = Self.defaultBarRow) {
        let clampedChromeHeight = max(chromeHeight, 0)
        let clampedBarRow = max(barRow, 0)
        totalHeight = clampedChromeHeight + Self.tail
        statusBottom = max(clampedChromeHeight - clampedBarRow, 0) / totalHeight
        chromeBottom = clampedChromeHeight / totalHeight
    }
}

/// LFG's top-scroll treatment, adapted to Noto's dark background: the glass
/// thins as it descends and a background-coloured scrim carries the darkness
/// at the status bar. The oversized glass shape keeps its specular perimeter
/// outside the visible mask, avoiding another hard lower edge.
@available(iOS 26.0, *)
struct Noto2TopChromeFade: View {
    let chromeHeight: CGFloat
    var barRow: CGFloat = Noto2TopChromeLayout.defaultBarRow
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let layout = Noto2TopChromeLayout(chromeHeight: chromeHeight, barRow: barRow)
        let glassMask = LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: layout.statusBottom),
                .init(color: .black.opacity(0.3), location: layout.chromeBottom),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        let scrim = LinearGradient(
            stops: [
                .init(color: NotoTheme.background.opacity(0.9), location: 0),
                .init(color: NotoTheme.background.opacity(0.4), location: layout.statusBottom),
                .init(color: NotoTheme.background.opacity(0.08), location: layout.chromeBottom),
                .init(color: NotoTheme.background.opacity(0), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        ZStack {
            Rectangle()
                .fill(.clear)
                .glassEffect(chromeGlass, in: Rectangle().inset(by: -48))
                .mask(glassMask)
            scrim
        }
        .frame(height: layout.totalHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var chromeGlass: Glass {
        colorScheme == .dark ? .regular.tint(Color.black.opacity(0.30)) : .regular
    }
}

/// The custom full-width fade owns the backdrop on iOS 26; leaving the system
/// navigation material visible underneath would restore the rectangular seam.
struct NoteEditorNavigationBarBackdropVisibility: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.toolbarBackground(.hidden, for: .navigationBar)
        } else {
            content
        }
    }
}
