import SwiftUI

struct NotoSplitView: View {
    var store: MarkdownNoteStore
    var fileWatcher: VaultFileWatcher?

    @Binding var selectedNote: MarkdownNote?
    @Binding var selectedNoteStore: MarkdownNoteStore?
    @Binding var selectedIsNew: Bool
    @Binding var externallyDeletingNoteID: UUID?
    var onOpenTodayNote: (() -> Void)? = nil

    #if os(iOS)
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    #else
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    #endif
    @State private var sidebarSearchText = ""
    @State private var isSearchPresented = false
    @State private var noteHistory = NoteNavigationHistory()
    @State private var isApplyingHistoryNavigation = false
    #if os(iOS)
    @State private var noteStackNavigation = NoteStackNavigationState()
    @State private var isSyncingSelectionFromNativeStack = false
    @FocusState private var isSearchFocused: Bool
    #endif

    var body: some View {
        #if os(iOS)
        iOSSplitView
        #else
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detailView
                .notoBackgroundExtension()
        }
        .navigationSplitViewStyle(.prominentDetail)
        .navigationTitle("Noto")
        .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.toggleSidebar)) { _ in
            toggleSidebar()
        }
        .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.showSearch)) { _ in
            showSearch()
        }
        .onAppear {
            recordCurrentSelectionInHistory()
        }
        .onChange(of: currentStackEntry) { _, _ in
            recordCurrentSelectionInHistory()
        }
        #endif
    }

    private var sidebar: some View {
        NotoSidebarView(
            rootStore: store,
            fileWatcher: fileWatcher,
            selectedNote: $selectedNote,
            selectedNoteStore: $selectedNoteStore,
            selectedIsNew: $selectedIsNew,
            externallyDeletingNoteID: $externallyDeletingNoteID,
            searchText: $sidebarSearchText,
            isSearchPresented: $isSearchPresented,
            onSelectNote: sidebarSelectNoteAction
        )
        #if os(macOS)
        .toolbar(removing: .sidebarToggle)
        #endif
    }

    #if os(iOS)
    private var iOSSplitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 360)
        } detail: {
            NavigationStack(path: $noteStackNavigation.path) {
                iosDetailRoot
                    .navigationDestination(for: NoteStackEntry.self) { entry in
                        splitEditor(for: entry)
                    }
            }
            .background(AppTheme.background)
        }
        .navigationSplitViewStyle(.prominentDetail)
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .notoAppBottomToolbar(
            onOpenTodayNote: onOpenTodayNote,
            onSearch: { isSearchPresented.toggle() },
            onCreateRootNote: createRootNote
        )
        .popover(isPresented: $isSearchPresented, arrowEdge: .bottom) {
            iOSSearchPopover
        }
        .background {
            AppTheme.background
                .ignoresSafeArea(edges: .bottom)
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .onAppear {
            recordCurrentSelectionInHistory()
            syncCurrentSelectionIntoNativeStack()
        }
        .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.toggleSidebar)) { _ in
            toggleSidebar()
        }
        .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.showSearch)) { _ in
            showSearch()
        }
        .onChange(of: currentStackEntry) { _, _ in
            recordCurrentSelectionInHistory()
            syncCurrentSelectionIntoNativeStack()
        }
        .onChange(of: noteStackNavigation.path) { _, _ in
            syncSelectionFromNativeStack()
        }
    }

    @ViewBuilder
    private var iosDetailRoot: some View {
        if let entry = noteStackNavigation.root {
            splitEditor(for: entry)
        } else {
            placeholderView
        }
    }

    private var iOSSearchPopover: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.mutedText)
            TextField("Search", text: $sidebarSearchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .accessibilityIdentifier("sidebar_search_field")
            if !sidebarSearchText.isEmpty {
                Button {
                    sidebarSearchText = ""
                } label: {
                    Label("Clear Search", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .labelStyle(.iconOnly)
                .foregroundStyle(AppTheme.mutedText)
                .accessibilityIdentifier("clear_search_button")
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 240, height: 32)
        .onAppear {
            isSearchFocused = true
        }
    }
    #endif

    @ViewBuilder
    private var detailView: some View {
        if let selectedNote, let selectedNoteStore {
            splitEditor(for: NoteStackEntry(note: selectedNote, store: selectedNoteStore, isNew: selectedIsNew))
        } else {
            placeholderView
        }
    }

    @ViewBuilder
    private func splitEditor(for entry: NoteStackEntry) -> some View {
        NoteEditorScreen(
            store: entry.store,
            note: entry.note,
            isNew: entry.isNew,
            fileWatcher: fileWatcher,
            onDelete: clearSelectedNote,
            onOpenTodayNote: splitEditorOpenTodayAction,
            onCreateRootNote: splitEditorCreateRootAction,
            onNoteUpdated: updateSelectedNote,
            onOpenDocumentLink: openDocumentLink,
            canNavigateBack: noteHistory.canGoBack,
            canNavigateForward: noteHistory.canGoForward,
            onNavigateBack: navigateHistoryBack,
            onNavigateForward: navigateHistoryForward,
            leadingChromeControls: splitEditorLeadingChromeControls,
            externallyDeletingNoteID: $externallyDeletingNoteID,
            chromeMode: splitEditorChromeMode
        )
        .id(entry.note.id)
    }

    @ViewBuilder
    private var placeholderView: some View {
        Text("Select a note")
            .font(.title2)
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background)
    }

    private var splitEditorChromeMode: EditorChromeMode {
        #if os(iOS)
        .compactNavigation(showsInlineBackButton: false)
        #else
        .splitClean
        #endif
    }

    private var splitEditorOpenTodayAction: (() -> Void)? {
        #if os(iOS)
        nil
        #else
        onOpenTodayNote
        #endif
    }

    private var splitEditorCreateRootAction: (() -> Void)? {
        #if os(iOS)
        nil
        #else
        nil
        #endif
    }

    private func updateSelectedNote(_ note: MarkdownNote) {
        guard selectedNote?.id == note.id else { return }
        selectedNote = note
        if let currentStackEntry {
            noteHistory.replaceCurrent(currentStackEntry)
        }
        #if os(iOS)
        if let currentStackEntry {
            noteStackNavigation.replaceVisibleEntry(currentStackEntry)
        }
        #endif
    }

    private func clearSelectedNote() {
        selectedNote = nil
        selectedNoteStore = nil
        selectedIsNew = false
        #if os(iOS)
        noteStackNavigation.clear()
        #endif
        noteHistory.clear()
    }

    private func openDocumentLink(_ relativePath: String) {
        guard let resolved = store.note(atVaultRelativePath: relativePath) else { return }
        selectHistoryEntry(NoteStackEntry(note: resolved.note, store: resolved.store, isNew: false), recordsVisit: true)
    }

    private var currentStackEntry: NoteStackEntry? {
        guard let selectedNote, let selectedNoteStore else { return nil }
        return NoteStackEntry(note: selectedNote, store: selectedNoteStore, isNew: selectedIsNew)
    }

    private func recordCurrentSelectionInHistory() {
        guard !isApplyingHistoryNavigation else { return }
        guard let currentStackEntry else {
            noteHistory.clear()
            return
        }
        noteHistory.visit(currentStackEntry)
    }

    private func navigateHistoryBack() {
        guard let entry = noteHistory.goBack() else { return }
        selectHistoryEntry(entry, recordsVisit: false)
    }

    private func navigateHistoryForward() {
        guard let entry = noteHistory.goForward() else { return }
        selectHistoryEntry(entry, recordsVisit: false)
    }

    private func selectHistoryEntry(_ entry: NoteStackEntry, recordsVisit: Bool) {
        if recordsVisit {
            noteHistory.visit(entry)
            selectedNoteStore = entry.store
            selectedNote = entry.note
            selectedIsNew = entry.isNew
            return
        }
        isApplyingHistoryNavigation = true
        selectedNoteStore = entry.store
        selectedNote = entry.note
        selectedIsNew = entry.isNew
        DispatchQueue.main.async {
            isApplyingHistoryNavigation = false
        }
    }

    private var isSidebarVisible: Bool {
        columnVisibility != .detailOnly
    }

    private func toggleSidebar() {
        if isSidebarVisible {
            columnVisibility = .detailOnly
        } else {
            columnVisibility = .all
        }
    }

    private func showSearch() {
        columnVisibility = .all
        DispatchQueue.main.async {
            isSearchPresented = true
        }
    }

    private var splitEditorLeadingChromeControls: EditorLeadingChromeControls {
        #if os(iOS)
        EditorLeadingChromeControls(
            showsBackButton: canNavigateNativeStackBack,
            onBack: navigateNativeStackBack
        )
        #else
        .none
        #endif
    }

    private var sidebarSelectNoteAction: (() -> Void)? {
        #if os(iOS)
        return {
            columnVisibility = .detailOnly
        }
        #else
        return nil
        #endif
    }

    #if os(iOS)
    private var canNavigateNativeStackBack: Bool {
        !noteStackNavigation.path.isEmpty
    }

    private func navigateNativeStackBack() {
        guard canNavigateNativeStackBack else { return }
        noteStackNavigation.path.removeLast()
    }

    private func createRootNote() {
        let note = store.createNote()
        selectHistoryEntry(NoteStackEntry(note: note, store: store, isNew: true), recordsVisit: true)
    }

    private func syncCurrentSelectionIntoNativeStack() {
        guard !isSyncingSelectionFromNativeStack else { return }

        guard let currentStackEntry else {
            noteStackNavigation.clear()
            return
        }

        if isApplyingHistoryNavigation {
            noteStackNavigation.replaceVisibleEntry(currentStackEntry)
        } else {
            noteStackNavigation.select(currentStackEntry)
        }
    }

    private func syncSelectionFromNativeStack() {
        guard let entry = noteStackNavigation.visibleEntry else {
            clearSelectedNote()
            return
        }

        if currentStackEntry?.hasSameNavigationTarget(as: entry) == true {
            return
        }

        isSyncingSelectionFromNativeStack = true
        if noteHistory.moveToAdjacentEntry(matching: entry) {
            selectHistoryEntry(entry, recordsVisit: false)
        } else {
            selectHistoryEntry(entry, recordsVisit: true)
        }
        DispatchQueue.main.async {
            isSyncingSelectionFromNativeStack = false
        }
    }
    #endif
}

private extension View {
    @ViewBuilder
    func notoBackgroundExtension() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.backgroundExtensionEffect()
        } else {
            self
        }
    }
}
