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
    var onOpenSearch: (() -> Void)? = nil
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
    // Cross-platform: reveal the note title in the top bar once the document title
    // scrolls out of view (iPad + macOS share this scrolled top-bar behavior).
    @State private var showsScrolledTitle = false
    // Cross-platform: the Properties sheet (and the "move after properties" hand-off) are
    // presented on iPad and macOS alike.
    @State private var showProperties = false
    @State private var pendingMoveAfterProperties = false
    #if os(iOS)
    @State private var dockHiddenByScroll = false
    @State private var showChat = false
    @State private var showChatKeyAlert = false
    @StateObject private var chatStore = ChatSessionStore()
    @State private var lastDockScrollY: CGFloat = 0
    #endif
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
        onOpenSearch: (() -> Void)? = nil,
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
        self.onOpenSearch = onOpenSearch
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
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        EditorContentView(
            session: session,
            isFindVisible: $isFindVisible,
            findQuery: $findQuery,
            findNavigationRequest: $findNavigationRequest,
            findStatus: $findStatus,
            pageMentionProvider: pageMentionDocuments(matching:),
            onOpenDocumentLink: onOpenDocumentLink,
            onOpenDocumentLinkInNewWindow: openDocumentLinkInNewWindow,
            onFindNavigate: navigateFind,
            scrollRestorationID: session.note.fileURL.path,
            initialContentOffsetY: initialEditorContentOffsetY,
            onContentOffsetYChange: persistEditorContentOffsetY
        )
        #if os(iOS)
        .background(NotoTheme.background)
        #else
        .background(NotoTheme.background)
        #endif
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
            onShowProperties: { withAnimation(.easeInOut(duration: 0.18)) { showProperties = true } },
            propertyCount: propertyCount,
            showsScrolledTitle: showsScrolledTitle,
            scrolledTitle: MarkdownNote.titleFrom(session.content),
            canNavigateBack: canNavigateBack,
            canNavigateForward: canNavigateForward,
            onNavigateBack: onNavigateBack,
            onNavigateForward: onNavigateForward,
            onDismiss: { dismiss() }
        ))
        // v2: no note-history edge-swipe — the leading edge swipe / back button does a
        // normal NavigationStack pop back to the file view.
        // iPhone (compact) keeps the native bottom sheet (swipe-to-dismiss). iPad (regular)
        // uses the tap-outside-to-dismiss overlay applied cross-platform below.
        .sheet(isPresented: Binding(
            get: { showProperties && horizontalSizeClass != .regular },
            set: { if !$0 { showProperties = false } }
        ), onDismiss: {
            if pendingMoveAfterProperties {
                pendingMoveAfterProperties = false
                showMoveSheet = true
            }
        }) {
            PropertiesSheet(
                session: session,
                onClose: { showProperties = false },
                onMoveFolder: {
                    pendingMoveAfterProperties = true
                    showProperties = false
                }
            )
            .propertiesSheetPresentation(isRegularWidth: false)
        }
        .notoAppBottomToolbar(
            onOpenTodayNote: showsEditorDock ? onOpenTodayNote : nil,
            onSearch: showsEditorDock ? onOpenSearch : nil,
            onCreateRootNote: showsEditorDock ? onCreateRootNote : nil,
            onOpenChat: showsEditorDock ? { presentChat() } : nil,
            hiddenByScroll: dockHiddenByScroll || isFindVisible
        )
        .sheet(isPresented: $showChat) {
            if let session = chatStore.session {
                ChatSheet(session: session, onOpenNote: { path in
                    showChat = false
                    onOpenDocumentLink?(path)
                })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .alert("Add your OpenRouter API key", isPresented: $showChatKeyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Open Settings to add your OpenRouter API key, then you can chat about this note.")
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
            onSearchRequested: showFind,
            onShowProperties: { withAnimation(.easeInOut(duration: 0.18)) { showProperties = true } },
            propertyCount: propertyCount,
            showsScrolledTitle: showsScrolledTitle,
            scrolledTitle: MarkdownNote.titleFrom(session.content)
        ))
        #endif
        // Tap-outside-to-dismiss Properties panel — used on macOS and iPad (regular width).
        // iPhone keeps the native bottom sheet above. SwiftUI sheets never dismiss on an
        // outside tap, so the panel is a dimmed overlay whose backdrop closes it.
        .overlay {
            if showsPropertiesPanel {
                propertiesPanelOverlay { propertiesPanelContent }
            }
        }
        .task(id: note.id) {
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
            if updatedNote.id == session.note.id {
                session.replaceNoteFromParent(updatedNote)
            } else {
                session.switchTo(note: updatedNote, store: store, isNew: isNew)
            }
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
        .onReceive(NotificationCenter.default.publisher(for: NoteEditorCommands.showMoveNote)) { notification in
            #if os(macOS)
            guard NotoCommandTarget.matches(notification, window: hostingWindow) else { return }
            #endif
            showMoveSheet = true
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

    private func openDocumentLinkInNewWindow(_ relativePath: String) {
        #if os(macOS)
        openWindow(id: "main", value: relativePath)
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
        // Reveal the note title in the top bar once the document title scrolls
        // out of view (v2 scrolled top-bar state — iPad + macOS).
        let shouldShowTitle = offsetY > 48
        if shouldShowTitle != showsScrolledTitle {
            withAnimation(.easeInOut(duration: 0.2)) {
                showsScrolledTitle = shouldShowTitle
            }
        }
        #if os(iOS)
        persistedScrollNotePath = session.note.fileURL.path
        persistedScrollOffsetY = Double(offsetY)
        // Hide the floating dock when scrolling down; reveal it when scrolling up
        // (or near the top). A small threshold avoids jitter.
        let delta = offsetY - lastDockScrollY
        if offsetY <= 0 {
            setDockHidden(false)
            lastDockScrollY = offsetY
        } else if abs(delta) > 6 {
            setDockHidden(delta > 0 && offsetY > 40)
            lastDockScrollY = offsetY
        }
        #endif
    }

    #if os(iOS)
    /// The current note's vault-relative path (pre-attached as chat context).
    private var noteVaultRelativePath: String? {
        let base = store.vaultRootURL.standardizedFileURL.path
        let full = session.note.fileURL.standardizedFileURL.path
        guard full.hasPrefix(base) else { return nil }
        var rel = String(full.dropFirst(base.count))
        if rel.hasPrefix("/") { rel.removeFirst() }
        return rel.isEmpty ? nil : rel
    }

    private func presentChat() {
        guard let apiKey = OpenRouterKeyStore.load(), !apiKey.isEmpty else { showChatKeyAlert = true; return }
        // Reuse the existing session so the conversation persists across dismiss/reopen.
        chatStore.ensure(apiKey: apiKey, vaultURL: store.vaultRootURL, seedMention: noteVaultRelativePath)
        showChat = true
    }

    private var isCompactChrome: Bool {
        if case .compactNavigation = chromeMode { return true }
        return false
    }

    /// The in-editor floating dock belongs to the iPhone (compact width) only. On iPad the
    /// split view (`NotoSplitView`) owns the dock, so don't double it up here.
    private var showsEditorDock: Bool {
        isCompactChrome && horizontalSizeClass == .compact
    }

    private func setDockHidden(_ hidden: Bool) {
        guard hidden != dockHiddenByScroll else { return }
        // Hide quickly (snappy), reveal with a slightly softer curve.
        withAnimation(hidden ? .easeOut(duration: 0.12) : .easeOut(duration: 0.2)) {
            dockHiddenByScroll = hidden
        }
    }
    #endif

    /// Number of YAML frontmatter fields — shown as the "Properties" subtitle in
    /// the More menu (replaces the old inline "Metadata N" block). Cross-platform.
    private var propertyCount: Int {
        EditableFrontmatterDocument(markdown: session.content)?.fields.count ?? 0
    }

    // MARK: Properties panel (tap-outside-to-dismiss) — macOS + iPad

    /// macOS always uses the dismissable overlay; iOS uses it only at regular width
    /// (iPhone/compact keeps the native bottom sheet).
    private var showsPropertiesPanel: Bool {
        #if os(macOS)
        showProperties
        #else
        showProperties && horizontalSizeClass == .regular
        #endif
    }

    @ViewBuilder
    private var propertiesPanelContent: some View {
        #if os(macOS)
        MacPropertiesForm(
            session: session,
            onClose: { dismissProperties() },
            onMoveFolder: { dismissPropertiesThenMove() }
        )
        #else
        PropertiesSheet(
            session: session,
            onClose: { dismissProperties() },
            onMoveFolder: { dismissPropertiesThenMove() }
        )
        #endif
    }

    /// Dimmed backdrop (tap to dismiss) + a centered, clipped panel card.
    @ViewBuilder
    private func propertiesPanelOverlay<Panel: View>(@ViewBuilder _ panel: () -> Panel) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.4))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissProperties() }
            panel()
                .frame(width: 520, height: 580)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 28, y: 14)
                .padding(28)
        }
        .transition(.opacity)
    }

    private func dismissProperties() {
        withAnimation(.easeInOut(duration: 0.18)) { showProperties = false }
    }

    /// Folder row tapped inside the panel: close the panel, then open the move sheet.
    private func dismissPropertiesThenMove() {
        dismissProperties()
        DispatchQueue.main.async { showMoveSheet = true }
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

#if os(iOS)
private extension View {
    /// Properties presentation: a centered FORM SHEET on iPad (regular width) per the v2
    /// design; a bottom sheet with detents on iPhone (compact).
    @ViewBuilder
    func propertiesSheetPresentation(isRegularWidth: Bool) -> some View {
        if isRegularWidth {
            if #available(iOS 18.0, *) {
                self.presentationSizing(.form)
            } else {
                self.presentationDetents([.large])
            }
        } else {
            self.presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}
#endif
