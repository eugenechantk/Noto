import SwiftUI
import NotoVault
#if os(macOS)
import AppKit
#endif

struct NoteEditorScreen: View {
    var store: MarkdownNoteStore
    var note: MarkdownNote
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
    @State private var showMoveSheet = false
    @State private var statusCount = WordCounter.Count(words: 0, characters: 0)
    @State private var isFindVisible = false
    @State private var findQuery = ""
    @State private var findStatus = EditorFindStatus()
    @State private var findNavigationRequest: EditorFindNavigationRequest?
    @State private var findNavigationRequestID = 0
    @State private var wordCountTask: Task<Void, Never>?
    #if os(iOS)
    @SceneStorage("noto.editorScrollNotePath") private var persistedScrollNotePath = ""
    @SceneStorage("noto.editorScrollOffsetY") private var persistedScrollOffsetY = 0.0
    #endif
    #if os(macOS)
    @State private var hostingWindow: NSWindow?
    #endif
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
        self.note = note
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
            isFindVisible: $isFindVisible,
            findQuery: $findQuery,
            findNavigationRequest: $findNavigationRequest,
            findStatus: $findStatus,
            pageMentionProvider: pageMentionDocuments(matching:),
            onOpenDocumentLink: onOpenDocumentLink,
            onFindNavigate: navigateFind,
            scrollRestorationID: session.note.fileURL.path,
            initialContentOffsetY: initialEditorContentOffsetY,
            onContentOffsetYChange: persistEditorContentOffsetY
        )
        .background(AppTheme.background)
        #if os(macOS)
        .background {
            NoteEditorWindowReader(window: $hostingWindow)
                .frame(width: 0, height: 0)
        }
        #endif
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
            onMoveRequested: { showMoveSheet = true },
            onDeleteRequested: { showDeleteConfirmation = true },
            onSearchRequested: showFind,
            canNavigateBack: canNavigateBack,
            canNavigateForward: canNavigateForward,
            onNavigateBack: onNavigateBack,
            onNavigateForward: onNavigateForward,
            onDismiss: { dismiss() }
        ))
        .overlay {
            navigationHistorySwipeEdges
        }
        #elseif os(macOS)
        .modifier(EditorNavigationChrome(
            mode: chromeMode,
            title: MarkdownNote.titleFrom(session.content),
            vaultRootURL: store.vaultRootURL,
            noteFileURL: session.note.fileURL,
            statusCount: statusCount,
            leadingControls: leadingChromeControls,
            canNavigateBack: canNavigateBack,
            canNavigateForward: canNavigateForward,
            onNavigateBack: onNavigateBack,
            onNavigateForward: onNavigateForward,
            onOpenTodayNote: onOpenTodayNote,
            onTapBreadcrumbLevel: onTapBreadcrumbLevel,
            onMoveRequested: { showMoveSheet = true },
            onDeleteRequested: { showDeleteConfirmation = true },
            onSearchRequested: showFind
        ))
        #endif
        .task {
            guard !session.hasLoaded else { return }
            await session.loadNoteContent()
        }
        .onChange(of: session.content, initial: true) { _, updatedContent in
            scheduleStatusCountUpdate(for: updatedContent)
        }
        .onDisappear {
            session.cancelBackgroundWork()
            wordCountTask?.cancel()
            session.persistFinalSnapshotIfNeeded(isExternallyDeleting: externallyDeletingNoteID?.wrappedValue == session.note.id)
            onNoteUpdated?(session.note)
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
        .onChange(of: note) { _, updatedNote in
            session.replaceNoteFromParent(updatedNote)
        }
        .onReceive(NotificationCenter.default.publisher(for: NoteSyncCenter.notificationName)) { notification in
            guard let snapshot = notification.object as? NoteSyncSnapshot else { return }
            session.handleRemoteSnapshot(snapshot)
        }
        .onReceive(NotificationCenter.default.publisher(for: NoteEditorCommands.showFind)) { notification in
            #if os(macOS)
            guard NotoCommandTarget.matches(notification, window: hostingWindow) else { return }
            #endif
            showFind()
        }
        .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirmation) {
            Button("Delete Note", role: .destructive) {
                deleteCurrentNote()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showMoveSheet) {
            MoveNoteDestinationPicker(
                vaultRootURL: store.vaultRootURL,
                currentDirectoryURL: session.note.fileURL.deletingLastPathComponent(),
                directoryLoader: store.directoryLoader,
                onCancel: {
                    showMoveSheet = false
                },
                onMove: { destinationURL in
                    moveCurrentNote(to: destinationURL)
                }
            )
        }
    }

    private func deleteCurrentNote() {
        session.markDeleting()
        guard session.deleteCurrentNote() else {
            session.finishDeleteAttempt()
            return
        }
        onDelete?()
        dismiss()
    }

    private func moveCurrentNote(to destinationURL: URL) {
        let movedNote = session.moveNote(to: destinationURL)
        onNoteUpdated?(movedNote)
        showMoveSheet = false
    }

    private func showFind() {
        withAnimation(.easeOut(duration: 0.16)) {
            isFindVisible = true
        }
    }

    private func navigateFind(_ direction: EditorFindNavigationDirection) {
        guard findStatus.matchCount > 0 else { return }
        findNavigationRequestID += 1
        findNavigationRequest = EditorFindNavigationRequest(
            id: findNavigationRequestID,
            direction: direction
        )
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

    private var initialEditorContentOffsetY: CGFloat? {
        #if os(iOS)
        persistedScrollNotePath == session.note.fileURL.path
            ? CGFloat(persistedScrollOffsetY)
            : nil
        #else
        nil
        #endif
    }

    private func persistEditorContentOffsetY(_ offsetY: CGFloat) {
        #if os(iOS)
        persistedScrollNotePath = session.note.fileURL.path
        persistedScrollOffsetY = Double(offsetY)
        #endif
    }

    #if os(iOS)
    private var navigationHistorySwipeEdges: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                navigationHistorySwipeEdge(direction: .back, width: edgeSwipeWidth(for: geometry.size.width))
                Spacer(minLength: 0)
                navigationHistorySwipeEdge(direction: .forward, width: edgeSwipeWidth(for: geometry.size.width))
            }
        }
        .allowsHitTesting(canNavigateBack || canNavigateForward)
    }

    private func edgeSwipeWidth(for containerWidth: CGFloat) -> CGFloat {
        min(28, max(20, containerWidth * 0.045))
    }

    private func navigationHistorySwipeEdge(direction: NavigationHistorySwipeDirection, width: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: width)
            .gesture(
                DragGesture(minimumDistance: 44, coordinateSpace: .local)
                    .onEnded { value in
                        handleNavigationHistoryEdgeSwipe(value, direction: direction)
                    }
            )
            .allowsHitTesting(direction.isAvailable(canNavigateBack: canNavigateBack, canNavigateForward: canNavigateForward))
    }

    private func handleNavigationHistoryEdgeSwipe(_ value: DragGesture.Value, direction: NavigationHistorySwipeDirection) {
        let horizontalDistance = value.translation.width
        let verticalDistance = value.translation.height
        guard abs(horizontalDistance) >= 96,
              abs(horizontalDistance) > abs(verticalDistance) * 1.8 else {
            return
        }

        switch direction {
        case .back where horizontalDistance > 0 && canNavigateBack:
            onNavigateBack?()
        case .forward where horizontalDistance < 0 && canNavigateForward:
            onNavigateForward?()
        default:
            break
        }
    }
#endif
}

private struct MoveNoteDestination: Identifiable, Equatable {
    let url: URL
    let name: String
    let depth: Int

    var id: String {
        url.standardizedFileURL.path
    }
}

private struct MoveNoteDestinationPicker: View {
    let vaultRootURL: URL
    let currentDirectoryURL: URL
    let directoryLoader: VaultDirectoryLoader
    var onCancel: () -> Void
    var onMove: (URL) -> Void

    @State private var destinations: [MoveNoteDestination] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List(destinations) { destination in
                Button {
                    onMove(destination.url)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: destination.url.standardizedFileURL == vaultRootURL.standardizedFileURL ? "tray.full" : "folder")
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(destination.name)
                                .foregroundStyle(AppTheme.primaryText)
                            if destination.url.standardizedFileURL == currentDirectoryURL.standardizedFileURL {
                                Text("Current location")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, CGFloat(destination.depth) * 16)
                    .contentShape(Rectangle())
                }
                .disabled(destination.url.standardizedFileURL == currentDirectoryURL.standardizedFileURL)
                .accessibilityIdentifier("move_destination_\(destination.name)")
            }
            .overlay {
                if isLoading {
                    ProgressView()
                } else if destinations.isEmpty {
                    ContentUnavailableView("No folders", systemImage: "folder")
                }
            }
            .navigationTitle("Move Note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier("move_note_cancel_button")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 420)
        #endif
        .task {
            loadDestinations()
        }
    }

    private func loadDestinations() {
        isLoading = true
        let rootDestination = MoveNoteDestination(
            url: vaultRootURL.standardizedFileURL,
            name: "Vault Root",
            depth: 0
        )

        let folderRows = (try? SidebarTreeLoader(directoryLoader: directoryLoader)
            .loadRows(rootURL: vaultRootURL)
            .compactMap { row -> MoveNoteDestination? in
                guard case .folder = row.kind else { return nil }
                return MoveNoteDestination(
                    url: row.url,
                    name: row.name,
                    depth: row.depth + 1
                )
            }) ?? []

        destinations = [rootDestination] + folderRows
        isLoading = false
    }
}

#if os(iOS)
private enum NavigationHistorySwipeDirection {
    case back
    case forward

    func isAvailable(canNavigateBack: Bool, canNavigateForward: Bool) -> Bool {
        switch self {
        case .back:
            canNavigateBack
        case .forward:
            canNavigateForward
        }
    }
}
#endif

#if os(macOS)
private struct NoteEditorWindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            window = view.window
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            if window !== view.window {
                window = view.window
            }
        }
    }
}
#endif
