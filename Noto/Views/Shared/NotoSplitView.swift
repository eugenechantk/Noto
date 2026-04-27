import SwiftUI

#if os(macOS)
import AppKit
#endif

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
    #if os(macOS)
    @State private var hostingWindow: NSWindow?
    #endif
    #if os(iOS)
    @State private var noteStackNavigation = NoteStackNavigationState()
    @State private var isSyncingSelectionFromNativeStack = false
    #endif

    var body: some View {
        #if os(iOS)
        iOSSplitView
        #else
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
            } detail: {
                detailView
                    .notoBackgroundExtension()
            }
            .navigationSplitViewStyle(.prominentDetail)
            .navigationTitle("Noto")

            if isSearchPresented {
                macOSSearchOverlay
            }
        }
        .background {
            #if os(macOS)
            WindowReader(window: $hostingWindow)
                .frame(width: 0, height: 0)
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.toggleSidebar)) { notification in
            #if os(macOS)
            guard handlesWindowScopedCommand(notification) else { return }
            #endif
            toggleSidebar()
        }
        .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.showSearch)) { notification in
            #if os(macOS)
            guard handlesWindowScopedCommand(notification) else { return }
            #endif
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

    #if os(macOS)
    private var macOSSearchOverlay: some View {
        ZStack {
            MacSearchDismissBackdrop {
                isSearchPresented = false
            }
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("note_search_dismiss_overlay")

            NoteSearchSheet(
                rootStore: store,
                onClose: {
                    isSearchPresented = false
                }
            ) { result in
                selectSearchResult(result)
            }
            .transition(.scale(scale: 0.98).combined(with: .opacity))
        }
        .zIndex(10)
    }
    #endif

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
            onSelectNote: sidebarSelectNoteAction,
            onToggleSidebar: {
                toggleSidebar()
            }
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
        .sheet(isPresented: $isSearchPresented) {
            NavigationStack {
                NoteSearchSheet(rootStore: store) { result in
                    selectSearchResult(result)
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .noteSearchSheetPresentationStyle()
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
        noteHistory.replaceEntries(for: note)
        #if os(iOS)
        noteStackNavigation.replaceEntries(for: note)
        #endif

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
        let entry = resolvedHistoryEntry(entry)
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

    private func resolvedHistoryEntry(_ entry: NoteStackEntry) -> NoteStackEntry {
        // Fast path: file still exists where the entry says it should — no need
        // to walk the vault. Without this, every search-result tap triggers a
        // full-vault content scan on the main thread (sluggish, can hit the
        // iOS watchdog and crash on large/iCloud-backed vaults).
        if FileManager.default.fileExists(atPath: entry.note.fileURL.standardizedFileURL.path) {
            return entry
        }
        guard let resolved = store.note(withID: entry.note.id) else { return entry }
        return NoteStackEntry(note: resolved.note, store: resolved.store, isNew: entry.isNew)
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
        guard !isSearchPresented else { return }
        #if os(iOS)
        isSearchPresented = true
        #else
        columnVisibility = .all
        DispatchQueue.main.async {
            isSearchPresented = true
        }
        #endif
    }

    #if os(macOS)
    private func handlesWindowScopedCommand(_ notification: Notification) -> Bool {
        NotoCommandTarget.matches(notification, window: hostingWindow)
    }
    #endif

    private var splitEditorLeadingChromeControls: EditorLeadingChromeControls {
        #if os(iOS)
        .none
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

    private func selectSearchResult(_ result: NoteSearchResult) {
        selectHistoryEntry(NoteStackEntry(note: result.note, store: result.store, isNew: false), recordsVisit: true)
        #if os(iOS)
        columnVisibility = .detailOnly
        #endif
    }

    #if os(iOS)
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

#if os(macOS)
private struct MacSearchDismissBackdrop: NSViewRepresentable {
    var onDismiss: () -> Void

    func makeNSView(context: Context) -> DismissBackdropView {
        let view = DismissBackdropView(frame: .zero)
        view.onDismiss = onDismiss
        view.setAccessibilityIdentifier("note_search_dismiss_overlay")
        return view
    }

    func updateNSView(_ view: DismissBackdropView, context: Context) {
        view.onDismiss = onDismiss
    }

    final class DismissBackdropView: NSView {
        var onDismiss: (() -> Void)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.withAlphaComponent(0.30).cgColor
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func mouseDown(with event: NSEvent) {
            onDismiss?()
        }
    }
}

private struct WindowReader: NSViewRepresentable {
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
