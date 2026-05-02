import SwiftUI
import os.log
import NotoSearch
import NotoVault
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NoteListView")

// MARK: - Navigation Route

enum NoteRoute: Hashable {
    case note(MarkdownNote, directoryURL: URL, vaultRootURL: URL, isNew: Bool = false)
    case folder(folderURL: URL, name: String, vaultRootURL: URL)
    case settings
    case todayNote
}

enum VaultWorkspaceSidebarItemKind {
    case note
    case folder
}

enum VaultWorkspaceIntent {
    case openNote(MarkdownNote, store: MarkdownNoteStore, isNew: Bool)
    case openSidebarNote(fileURL: URL, noteID: UUID?, title: String, modifiedAt: Date, isNew: Bool)
    case openFolder(NotoFolder, parentStore: MarkdownNoteStore)
    case openFolderURL(URL, name: String, vaultRootURL: URL)
    case openToday
    case openSearch
    case closeSearch
    case openSettings
    case createNote(in: MarkdownNoteStore)
    case createNoteInDirectory(URL)
    case createFolder(named: String, in: MarkdownNoteStore)
    case createFolderInDirectory(named: String, parentURL: URL)
    case deleteItem(DirectoryItem, in: MarkdownNoteStore)
    case deleteNote(MarkdownNote, in: MarkdownNoteStore)
    case deleteFolder(NotoFolder, in: MarkdownNoteStore)
    case deleteSidebarItem(fileURL: URL, kind: VaultWorkspaceSidebarItemKind, noteID: UUID?, title: String, modifiedAt: Date)
    case moveNote(MarkdownNote, from: MarkdownNoteStore, to: URL)
    case moveNoteURL(URL, to: URL)
    case openDocumentLink(String)
    case updateSelectedNote(MarkdownNote)
    case clearSelection
}

// MARK: - Stack History

struct NoteStackEntry: Equatable, Hashable {
    var note: MarkdownNote
    var directoryURL: URL
    var vaultRootURL: URL
    var isNew: Bool

    init(note: MarkdownNote, directoryURL: URL, vaultRootURL: URL, isNew: Bool) {
        self.note = note
        self.directoryURL = directoryURL
        self.vaultRootURL = vaultRootURL
        self.isNew = isNew
    }

    init(note: MarkdownNote, store: MarkdownNoteStore, isNew: Bool) {
        self.note = note
        self.directoryURL = store.directoryURL
        self.vaultRootURL = store.vaultRootURL
        self.isNew = isNew
    }

    @MainActor
    var store: MarkdownNoteStore {
        MarkdownNoteStore(directoryURL: directoryURL, vaultRootURL: vaultRootURL, autoload: false)
    }

    func hasSameNavigationTarget(as other: NoteStackEntry) -> Bool {
        if note.id == other.note.id &&
            vaultRootURL.standardizedFileURL == other.vaultRootURL.standardizedFileURL {
            return true
        }

        return note.fileURL.standardizedFileURL == other.note.fileURL.standardizedFileURL &&
            directoryURL.standardizedFileURL == other.directoryURL.standardizedFileURL &&
            vaultRootURL.standardizedFileURL == other.vaultRootURL.standardizedFileURL
    }

    func replacingNote(_ updatedNote: MarkdownNote) -> NoteStackEntry {
        NoteStackEntry(
            note: updatedNote,
            directoryURL: updatedNote.fileURL.deletingLastPathComponent(),
            vaultRootURL: vaultRootURL,
            isNew: isNew
        )
    }

    static func == (lhs: NoteStackEntry, rhs: NoteStackEntry) -> Bool {
        lhs.note.fileURL.standardizedFileURL == rhs.note.fileURL.standardizedFileURL &&
            lhs.directoryURL.standardizedFileURL == rhs.directoryURL.standardizedFileURL &&
            lhs.vaultRootURL.standardizedFileURL == rhs.vaultRootURL.standardizedFileURL &&
            lhs.isNew == rhs.isNew
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(note.fileURL.standardizedFileURL.path)
        hasher.combine(directoryURL.standardizedFileURL.path)
        hasher.combine(vaultRootURL.standardizedFileURL.path)
        hasher.combine(isNew)
    }
}

struct NoteStackNavigationState: Equatable {
    private(set) var root: NoteStackEntry?
    var path: [NoteStackEntry] = []

    var visibleEntry: NoteStackEntry? {
        path.last ?? root
    }

    mutating func select(_ entry: NoteStackEntry) {
        guard let visibleEntry else {
            root = entry
            return
        }

        if visibleEntry.hasSameNavigationTarget(as: entry) {
            replaceVisibleEntry(entry)
        } else {
            path.append(entry)
        }
    }

    mutating func replaceVisibleEntry(_ entry: NoteStackEntry) {
        if path.isEmpty {
            root = entry
        } else {
            path[path.index(before: path.endIndex)] = entry
        }
    }

    mutating func replaceEntries(for updatedNote: MarkdownNote) {
        if let currentRoot = root, currentRoot.note.id == updatedNote.id {
            root = currentRoot.replacingNote(updatedNote)
        }

        path = path.map { entry in
            entry.note.id == updatedNote.id ? entry.replacingNote(updatedNote) : entry
        }
    }

    mutating func clear() {
        root = nil
        path.removeAll()
    }
}

struct NoteNavigationHistory: Equatable {
    private(set) var entries: [NoteStackEntry] = []
    private(set) var currentIndex: Int?

    var currentEntry: NoteStackEntry? {
        guard let currentIndex, entries.indices.contains(currentIndex) else { return nil }
        return entries[currentIndex]
    }

    var canGoBack: Bool {
        guard let currentIndex else { return false }
        return currentIndex > 0
    }

    var canGoForward: Bool {
        guard let currentIndex else { return false }
        return currentIndex < entries.index(before: entries.endIndex)
    }

    mutating func visit(_ entry: NoteStackEntry) {
        guard let currentIndex else {
            entries = [entry]
            self.currentIndex = 0
            return
        }

        if entries[currentIndex].hasSameNavigationTarget(as: entry) {
            entries[currentIndex] = entry
            return
        }

        entries.removeSubrange(entries.index(after: currentIndex)..<entries.endIndex)
        entries.append(entry)
        self.currentIndex = entries.index(before: entries.endIndex)
    }

    mutating func replaceCurrent(_ entry: NoteStackEntry) {
        guard let currentIndex, entries.indices.contains(currentIndex) else {
            visit(entry)
            return
        }
        entries[currentIndex] = entry
    }

    mutating func replaceEntries(for updatedNote: MarkdownNote) {
        entries = entries.map { entry in
            entry.note.id == updatedNote.id ? entry.replacingNote(updatedNote) : entry
        }
    }

    mutating func goBack() -> NoteStackEntry? {
        guard canGoBack, let currentIndex else { return nil }
        let newIndex = entries.index(before: currentIndex)
        self.currentIndex = newIndex
        return entries[newIndex]
    }

    mutating func goForward() -> NoteStackEntry? {
        guard canGoForward, let currentIndex else { return nil }
        let newIndex = entries.index(after: currentIndex)
        self.currentIndex = newIndex
        return entries[newIndex]
    }

    mutating func moveToAdjacentEntry(matching entry: NoteStackEntry) -> Bool {
        guard let currentIndex else { return false }

        if currentIndex > entries.startIndex {
            let previousIndex = entries.index(before: currentIndex)
            if entries[previousIndex].hasSameNavigationTarget(as: entry) {
                entries[previousIndex] = entry
                self.currentIndex = previousIndex
                return true
            }
        }

        if currentIndex < entries.index(before: entries.endIndex) {
            let nextIndex = entries.index(after: currentIndex)
            if entries[nextIndex].hasSameNavigationTarget(as: entry) {
                entries[nextIndex] = entry
                self.currentIndex = nextIndex
                return true
            }
        }

        return false
    }

    mutating func clear() {
        entries.removeAll()
        currentIndex = nil
    }
}

// MARK: - Workspace View

/// Workspace entry point — NavigationStack on compact iOS, split view on iPadOS/macOS.
struct VaultWorkspaceView: View {
    var store: MarkdownNoteStore
    var locationManager: VaultLocationManager?
    var fileWatcher: VaultFileWatcher?
    @ObservedObject var readwiseSyncController: ReadwiseSyncController
    var initialDocumentLink: String?

    #if os(iOS)
    @State private var path = NavigationPath()
    @State private var compactNoteHistory = NoteNavigationHistory()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var isSearchPresented = false
    @State private var selectedNote: MarkdownNote?
    @State private var selectedNoteStore: MarkdownNoteStore?
    @State private var selectedNoteIsNew = false
    @State private var externallyDeletingNoteID: UUID?
    @State private var splitNoteHistory = NoteNavigationHistory()
    @State private var isApplyingSplitHistoryNavigation = false
    @State private var showSettings = false
    @State private var hasRestoredSelection = false
    #if os(iOS)
    @State private var splitNoteStackNavigation = NoteStackNavigationState()
    @State private var isSyncingSplitSelectionFromNativeStack = false
    #endif
    #if os(macOS)
    @State private var hostingWindow: NSWindow?
    #endif

    private static let lastOpenedNoteKey = "lastOpenedNoteURL"

    var body: some View {
        #if os(iOS)
        if horizontalSizeClass == .regular {
            NotoSplitView(
                store: store,
                isSearchPresented: $isSearchPresented,
                noteStackPath: $splitNoteStackNavigation.path,
                onSearchResult: { result in
                    handleWorkspaceIntent(.openNote(result.note, store: result.store, isNew: false))
                },
                onOpenTodayNote: {
                    handleWorkspaceIntent(.openToday)
                },
                onCreateRootNote: {
                    handleWorkspaceIntent(.createNote(in: store))
                },
                onNativeStackChanged: syncSplitSelectionFromNativeStack,
                sidebar: { searchText, onToggleSidebar in
                    NotoSidebarView(
                        rootStore: store,
                        fileWatcher: fileWatcher,
                        selectedNote: selectedNote,
                        searchText: searchText,
                        onIntent: handleWorkspaceIntent,
                        onToggleSidebar: onToggleSidebar
                    )
                    .toolbar(.hidden, for: .navigationBar)
                },
                detail: { onToggleSidebar in
                    splitDetailView(onToggleSidebar: onToggleSidebar)
                },
                iosDetailRoot: { onToggleSidebar in
                    splitIOSDetailRoot(onToggleSidebar: onToggleSidebar)
                },
                iosDestination: { entry, onToggleSidebar in
                    splitEditor(for: entry, onToggleSidebar: onToggleSidebar)
                }
            )
            .sheet(isPresented: $showSettings) {
                if let locationManager {
                    NavigationStack {
                        SettingsView(locationManager: locationManager, readwiseSyncController: readwiseSyncController)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.openToday)) { _ in
                openTodayNote()
            }
            .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.openSettings)) { _ in
                if locationManager != nil {
                    showSettings = true
                }
            }
            .onChange(of: selectedNote?.fileURL) { _, newURL in
                persistLastOpenedNoteURL(newURL)
            }
            .onAppear {
                guard !hasRestoredSelection else { return }
                hasRestoredSelection = true
                openInitialDocumentLinkOrRestore()
            }
        } else {
            NavigationStack(path: $path) {
                FolderContentView(
                    store: store,
                    title: "Notes",
                    isRoot: true,
                    fileWatcher: fileWatcher,
                    onIntent: handleWorkspaceIntent,
                    canOpenSettings: locationManager != nil
                )
                .navigationDestination(for: NoteRoute.self) { route in
                    switch route {
                    case .note(let note, let directoryURL, let vaultRootURL, let isNew):
                        NoteEditorScreen(
                            store: MarkdownNoteStore(
                                directoryURL: directoryURL,
                                vaultRootURL: vaultRootURL,
                                autoload: false,
                                directoryLoader: store.directoryLoader
                            ),
                            note: note,
                            isNew: isNew,
                            fileWatcher: fileWatcher,
                            onOpenTodayNote: { path.append(NoteRoute.todayNote) },
                            onCreateRootNote: createRootNoteAndPush,
                            onTapBreadcrumbLevel: { folderURL in
                                path = NavigationPath()
                                if folderURL.standardizedFileURL != vaultRootURL.standardizedFileURL {
                                    path.append(NoteRoute.folder(
                                        folderURL: folderURL,
                                        name: folderURL.lastPathComponent,
                                        vaultRootURL: vaultRootURL
                                    ))
                                }
                            },
                            onNoteUpdated: updateCompactHistory,
                            onOpenDocumentLink: { relativePath in
                                openDocumentLink(relativePath, vaultRootURL: vaultRootURL)
                            },
                            canNavigateBack: compactNoteHistory.canGoBack,
                            canNavigateForward: compactNoteHistory.canGoForward,
                            onNavigateBack: navigateCompactHistoryBack,
                            onNavigateForward: navigateCompactHistoryForward
                        )
                    case .folder(let folderURL, let name, let vaultRootURL):
                        FolderContentView(
                            store: MarkdownNoteStore(
                                directoryURL: folderURL,
                                vaultRootURL: vaultRootURL,
                                autoload: false,
                                directoryLoader: store.directoryLoader
                            ),
                            title: name,
                            fileWatcher: fileWatcher,
                            onIntent: handleWorkspaceIntent
                        )
                    case .settings:
                        if let locationManager {
                            SettingsView(locationManager: locationManager, readwiseSyncController: readwiseSyncController)
                        }
                    case .todayNote:
                        TodayNoteDestination(
                            store: store,
                            fileWatcher: fileWatcher,
                            onOpenTodayNote: { path.append(NoteRoute.todayNote) },
                            onCreateRootNote: createRootNoteAndPush,
                            onTapBreadcrumbLevel: { folderURL in
                                path = NavigationPath()
                                if folderURL.standardizedFileURL != store.vaultRootURL.standardizedFileURL {
                                    path.append(NoteRoute.folder(
                                        folderURL: folderURL,
                                        name: folderURL.lastPathComponent,
                                        vaultRootURL: store.vaultRootURL
                                    ))
                                }
                            },
                            onNoteUpdated: updateCompactHistory,
                            onOpenDocumentLink: { relativePath in
                                openDocumentLink(relativePath, vaultRootURL: store.vaultRootURL)
                            },
                            canNavigateBack: compactNoteHistory.canGoBack,
                            canNavigateForward: compactNoteHistory.canGoForward,
                            onNavigateBack: navigateCompactHistoryBack,
                            onNavigateForward: navigateCompactHistoryForward
                        )
                    }
                }
            }
            .notoAppBottomToolbar(
                onOpenTodayNote: { handleWorkspaceIntent(.openToday) },
                onSearch: { handleWorkspaceIntent(.openSearch) },
                onCreateRootNote: { handleWorkspaceIntent(.createNote(in: store)) }
            )
            .sheet(isPresented: $isSearchPresented) {
                NavigationStack {
                    NoteSearchSheet(rootStore: store) { result in
                        handleWorkspaceIntent(.openNote(result.note, store: result.store, isNew: false))
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .noteSearchSheetPresentationStyle()
            }
            .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.openToday)) { _ in
                handleWorkspaceIntent(.openToday)
            }
            .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.showSearch)) { _ in
                handleWorkspaceIntent(.openSearch)
            }
            .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.openSettings)) { _ in
                if locationManager != nil {
                    handleWorkspaceIntent(.openSettings)
                }
            }
        }
        #elseif os(macOS)
            NotoSplitView(
                store: store,
                isSearchPresented: $isSearchPresented,
                noteStackPath: .constant([]),
                onSearchResult: { result in
                    handleWorkspaceIntent(.openNote(result.note, store: result.store, isNew: false))
                },
                onOpenTodayNote: {
                    handleWorkspaceIntent(.openToday)
                },
                onToggleSidebarCommand: {},
                onShowSearchCommand: {
                    handleWorkspaceIntent(.openSearch)
                },
                sidebar: { searchText, onToggleSidebar in
                    NotoSidebarView(
                        rootStore: store,
                        fileWatcher: fileWatcher,
                        selectedNote: selectedNote,
                        searchText: searchText,
                        onIntent: handleWorkspaceIntent,
                        onToggleSidebar: onToggleSidebar
                    )
                    .toolbar(removing: .sidebarToggle)
                },
                detail: { onToggleSidebar in
                    splitDetailView(onToggleSidebar: onToggleSidebar)
                },
                iosDetailRoot: { _ in
                    EmptyView()
                },
                iosDestination: { _, _ in
                    EmptyView()
                }
            )
        .background {
            WindowCommandReader(window: $hostingWindow)
                .frame(width: 0, height: 0)
        }
        .sheet(isPresented: $showSettings) {
            if let locationManager {
                SettingsView(locationManager: locationManager, readwiseSyncController: readwiseSyncController)
                    .frame(minWidth: 400, minHeight: 200)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.openToday)) { notification in
            guard NotoCommandTarget.matches(notification, window: hostingWindow) else { return }
            openTodayNote()
        }
        .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.createNote)) { notification in
            guard NotoCommandTarget.matches(notification, window: hostingWindow) else { return }
            handleWorkspaceIntent(.createNote(in: store))
        }
        .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.openSettings)) { notification in
            guard NotoCommandTarget.matches(notification, window: hostingWindow) else { return }
            if locationManager != nil {
                showSettings = true
            }
        }
        .onChange(of: selectedNote?.fileURL) { _, newURL in
            persistLastOpenedNoteURL(newURL)
        }
        .onAppear {
            guard !hasRestoredSelection else { return }
            hasRestoredSelection = true
            openInitialDocumentLinkOrRestore()
        }
        #endif
    }

    private func handleWorkspaceIntent(_ intent: VaultWorkspaceIntent) {
        switch intent {
        case .openNote(let note, let noteStore, let isNew):
            openNoteFromWorkspace(note, in: noteStore, isNew: isNew)
        case .openSidebarNote(let fileURL, let noteID, let title, let modifiedAt, let isNew):
            let noteStore = storeForDirectory(fileURL.deletingLastPathComponent())
            let note = MarkdownNote(
                id: noteID ?? VaultDirectoryLoader.stableID(for: fileURL),
                fileURL: fileURL,
                title: title,
                modifiedDate: modifiedAt
            )
            openNoteFromWorkspace(note, in: noteStore, isNew: isNew)
        case .openFolder(let folder, let parentStore):
            handleWorkspaceIntent(.openFolderURL(
                folder.folderURL,
                name: folder.name,
                vaultRootURL: parentStore.vaultRootURL
            ))
        case .openFolderURL(let folderURL, let name, let vaultRootURL):
            #if os(iOS)
            path.append(NoteRoute.folder(folderURL: folderURL, name: name, vaultRootURL: vaultRootURL))
            #endif
        case .openToday:
            openTodayFromWorkspace()
        case .openSearch:
            isSearchPresented = true
        case .closeSearch:
            isSearchPresented = false
        case .openSettings:
            guard locationManager != nil else { return }
            #if os(iOS)
            if horizontalSizeClass == .regular {
                showSettings = true
            } else {
                path.append(NoteRoute.settings)
            }
            #else
            showSettings = true
            #endif
        case .createNote(let noteStore):
            let note = noteStore.createNote()
            openNoteFromWorkspace(note, in: noteStore, isNew: true)
        case .createNoteInDirectory(let directoryURL):
            let noteStore = storeForDirectory(directoryURL)
            let note = noteStore.createNote()
            openNoteFromWorkspace(note, in: noteStore, isNew: true)
        case .createFolder(let name, let noteStore):
            _ = noteStore.createFolder(name: name)
        case .createFolderInDirectory(let name, let parentURL):
            _ = storeForDirectory(parentURL).createFolder(name: name)
        case .deleteItem(let item, let noteStore):
            clearSelectionIfNeeded(for: item)
            noteStore.deleteItem(item)
        case .deleteNote(let note, let noteStore):
            externallyDeletingNoteID = note.id
            clearSelectionIfNeeded(noteFileURL: note.fileURL)
            noteStore.deleteNote(note)
        case .deleteFolder(let folder, let noteStore):
            clearSelectionIfNeeded(folderURL: folder.folderURL)
            noteStore.deleteFolder(folder)
        case .deleteSidebarItem(let fileURL, let kind, let noteID, let title, let modifiedAt):
            let parentStore = storeForDirectory(fileURL.deletingLastPathComponent())
            switch kind {
            case .note:
                let note = MarkdownNote(
                    id: noteID ?? VaultDirectoryLoader.stableID(for: fileURL),
                    fileURL: fileURL,
                    title: title,
                    modifiedDate: modifiedAt
                )
                handleWorkspaceIntent(.deleteNote(note, in: parentStore))
            case .folder:
                let folder = NotoFolder(
                    id: VaultDirectoryLoader.stableID(for: fileURL),
                    folderURL: fileURL,
                    name: title,
                    modifiedDate: modifiedAt,
                    folderCount: 0,
                    itemCount: 0
                )
                handleWorkspaceIntent(.deleteFolder(folder, in: parentStore))
            }
        case .moveNote(let note, let sourceStore, let destinationURL):
            let movedNote = sourceStore.moveNote(note, to: destinationURL)
            updateSelectionAfterMove(from: note.fileURL, to: movedNote)
        case .moveNoteURL(let sourceURL, let destinationURL):
            let sourceStore = storeForDirectory(sourceURL.deletingLastPathComponent())
            let note = markdownNote(for: sourceURL)
            handleWorkspaceIntent(.moveNote(note, from: sourceStore, to: destinationURL))
        case .openDocumentLink(let relativePath):
            guard let resolved = store.note(atVaultRelativePath: relativePath) else { return }
            openNoteFromWorkspace(resolved.note, in: resolved.store, isNew: false)
        case .updateSelectedNote(let note):
            updateSelectedNote(note)
        case .clearSelection:
            clearSplitSelection()
        }
    }

    private func openTodayFromWorkspace() {
        #if os(iOS)
        if horizontalSizeClass != .regular {
            path.append(NoteRoute.todayNote)
            return
        }
        #endif
        openTodayNote()
    }

    private func openTodayNote() {
        let (todayStore, todayNote) = store.todayNote()
        selectNote(todayNote, in: todayStore, isNew: false)
    }

    private func openNoteFromWorkspace(_ note: MarkdownNote, in noteStore: MarkdownNoteStore, isNew: Bool) {
        #if os(iOS)
        if horizontalSizeClass != .regular {
            openCompactNote(note, in: noteStore, isNew: isNew)
            return
        }
        #endif
        selectNote(note, in: noteStore, isNew: isNew)
    }

    private func storeForDirectory(_ directoryURL: URL, autoload: Bool = false) -> MarkdownNoteStore {
        MarkdownNoteStore(
            directoryURL: directoryURL,
            vaultRootURL: store.vaultRootURL,
            autoload: autoload,
            directoryLoader: store.directoryLoader
        )
    }

    private func markdownNote(for fileURL: URL) -> MarkdownNote {
        let content = CoordinatedFileManager.readString(from: fileURL) ?? ""
        let titleResolver = NoteTitleResolver()
        let modifiedAt = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return MarkdownNote(
            id: MarkdownNote.idFromFrontmatter(content) ?? VaultDirectoryLoader.stableID(for: fileURL),
            fileURL: fileURL,
            title: titleResolver.title(from: content, fallbackTitle: titleResolver.fallbackTitle(for: fileURL)),
            modifiedDate: modifiedAt
        )
    }

    @ViewBuilder
    private func splitDetailView(onToggleSidebar: @escaping () -> Void) -> some View {
        if let entry = currentSplitStackEntry {
            splitEditor(for: entry, onToggleSidebar: onToggleSidebar)
        } else {
            Text("Select a note")
                .font(.title2)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.background)
        }
    }

    #if os(iOS)
    @ViewBuilder
    private func splitIOSDetailRoot(onToggleSidebar: @escaping () -> Void) -> some View {
        if let entry = splitNoteStackNavigation.root {
            splitEditor(for: entry, onToggleSidebar: onToggleSidebar)
        } else {
            splitDetailView(onToggleSidebar: onToggleSidebar)
        }
    }
    #endif

    private var currentSplitStackEntry: NoteStackEntry? {
        guard let selectedNote, let selectedNoteStore else { return nil }
        return NoteStackEntry(note: selectedNote, store: selectedNoteStore, isNew: selectedNoteIsNew)
    }

    @ViewBuilder
    private func splitEditor(for entry: NoteStackEntry, onToggleSidebar: @escaping () -> Void) -> some View {
        NoteEditorScreen(
            store: entry.store,
            note: entry.note,
            isNew: entry.isNew,
            fileWatcher: fileWatcher,
            onDelete: {
                handleWorkspaceIntent(.clearSelection)
            },
            onOpenTodayNote: {
                handleWorkspaceIntent(.openToday)
            },
            onCreateRootNote: {
                handleWorkspaceIntent(.createNote(in: store))
            },
            onNoteUpdated: { updatedNote in
                handleWorkspaceIntent(.updateSelectedNote(updatedNote))
            },
            onOpenDocumentLink: { relativePath in
                handleWorkspaceIntent(.openDocumentLink(relativePath))
            },
            canNavigateBack: splitNoteHistory.canGoBack,
            canNavigateForward: splitNoteHistory.canGoForward,
            onNavigateBack: navigateSplitHistoryBack,
            onNavigateForward: navigateSplitHistoryForward,
            leadingChromeControls: splitEditorLeadingControls(onToggleSidebar: onToggleSidebar),
            externallyDeletingNoteID: $externallyDeletingNoteID,
            chromeMode: splitEditorChromeMode
        )
        .id(entry.note.id)
    }

    private var splitEditorChromeMode: EditorChromeMode {
        #if os(macOS)
        .macToolbar
        #else
        .compactNavigation(showsInlineBackButton: false)
        #endif
    }

    private func splitEditorLeadingControls(onToggleSidebar: @escaping () -> Void) -> EditorLeadingChromeControls {
        #if os(macOS)
        EditorLeadingChromeControls(
            sidebarSystemImage: "sidebar.left",
            sidebarAccessibilityLabel: "Toggle Sidebar",
            onToggleSidebar: onToggleSidebar
        )
        #else
        .none
        #endif
    }

    private func selectNote(_ note: MarkdownNote, in noteStore: MarkdownNoteStore, isNew: Bool) {
        selectedNoteStore = noteStore
        selectedNote = note
        selectedNoteIsNew = isNew
        let entry = NoteStackEntry(note: note, store: noteStore, isNew: isNew)
        if !isApplyingSplitHistoryNavigation {
            splitNoteHistory.visit(entry)
        }
        #if os(iOS)
        isSyncingSplitSelectionFromNativeStack = true
        splitNoteStackNavigation.select(entry)
        DispatchQueue.main.async {
            isSyncingSplitSelectionFromNativeStack = false
        }
        #endif
        collapseSidebar()
    }

    private func updateSelectedNote(_ note: MarkdownNote) {
        guard selectedNote?.id == note.id ||
            selectedNote?.fileURL.standardizedFileURL == note.fileURL.standardizedFileURL else {
            return
        }

        selectedNote = note
        selectedNoteStore = storeForDirectory(note.fileURL.deletingLastPathComponent())
        splitNoteHistory.replaceEntries(for: note)
        if let currentEntry = currentSplitStackEntry {
            splitNoteHistory.replaceCurrent(currentEntry)
        }
        #if os(iOS)
        splitNoteStackNavigation.replaceEntries(for: note)
        #endif
    }

    private func clearSplitSelection() {
        selectedNote = nil
        selectedNoteStore = nil
        selectedNoteIsNew = false
        splitNoteHistory.clear()
        #if os(iOS)
        splitNoteStackNavigation.clear()
        #endif
    }

    private func clearSelectionIfNeeded(for item: DirectoryItem) {
        switch item {
        case .note(let note):
            externallyDeletingNoteID = note.id
            clearSelectionIfNeeded(noteFileURL: note.fileURL)
        case .folder(let folder):
            clearSelectionIfNeeded(folderURL: folder.folderURL)
        }
    }

    private func clearSelectionIfNeeded(noteFileURL: URL) {
        guard selectedNote?.fileURL.standardizedFileURL == noteFileURL.standardizedFileURL else { return }
        clearSplitSelection()
    }

    private func clearSelectionIfNeeded(folderURL: URL) {
        guard let selectedNoteURL = selectedNote?.fileURL.standardizedFileURL else { return }
        let folderPath = folderURL.standardizedFileURL.path
        guard selectedNoteURL.path == folderPath || selectedNoteURL.path.hasPrefix(folderPath + "/") else { return }
        clearSplitSelection()
    }

    private func updateSelectionAfterMove(from sourceURL: URL, to movedNote: MarkdownNote) {
        guard selectedNote?.id == movedNote.id ||
            selectedNote?.fileURL.standardizedFileURL == sourceURL.standardizedFileURL else {
            return
        }
        selectNote(movedNote, in: storeForDirectory(movedNote.fileURL.deletingLastPathComponent()), isNew: false)
    }

    private func navigateSplitHistoryBack() {
        guard let entry = splitNoteHistory.goBack() else { return }
        selectSplitHistoryEntry(entry)
    }

    private func navigateSplitHistoryForward() {
        guard let entry = splitNoteHistory.goForward() else { return }
        selectSplitHistoryEntry(entry)
    }

    private func selectSplitHistoryEntry(_ entry: NoteStackEntry) {
        isApplyingSplitHistoryNavigation = true
        selectedNote = entry.note
        selectedNoteStore = entry.store
        selectedNoteIsNew = entry.isNew
        #if os(iOS)
        isSyncingSplitSelectionFromNativeStack = true
        splitNoteStackNavigation.replaceVisibleEntry(entry)
        DispatchQueue.main.async {
            isSyncingSplitSelectionFromNativeStack = false
        }
        #endif
        isApplyingSplitHistoryNavigation = false
    }

    #if os(iOS)
    private func syncSplitSelectionFromNativeStack() {
        guard !isSyncingSplitSelectionFromNativeStack,
              let visibleEntry = splitNoteStackNavigation.visibleEntry else {
            return
        }
        isApplyingSplitHistoryNavigation = true
        selectedNote = visibleEntry.note
        selectedNoteStore = visibleEntry.store
        selectedNoteIsNew = visibleEntry.isNew
        if !splitNoteHistory.moveToAdjacentEntry(matching: visibleEntry) {
            splitNoteHistory.visit(visibleEntry)
        }
        isApplyingSplitHistoryNavigation = false
    }
    #endif

    #if os(iOS)
    private func createRootNoteAndPush() {
        let note = store.createNote()
        let entry = NoteStackEntry(note: note, store: store, isNew: true)
        compactNoteHistory.visit(entry)
        path = NavigationPath()
        path.append(noteRoute(for: entry))
    }

    private func openDocumentLink(_ relativePath: String, vaultRootURL: URL) {
        guard let resolved = store.note(atVaultRelativePath: relativePath) else { return }
        openCompactNote(resolved.note, in: resolved.store, isNew: false)
    }

    private func openCompactNote(_ note: MarkdownNote, in noteStore: MarkdownNoteStore, isNew: Bool) {
        let entry = NoteStackEntry(note: note, store: noteStore, isNew: isNew)
        compactNoteHistory.visit(entry)
        path.append(noteRoute(for: entry))
    }

    private func navigateCompactHistoryBack() {
        guard let entry = compactNoteHistory.goBack() else { return }
        replaceCompactVisibleNote(with: entry)
    }

    private func navigateCompactHistoryForward() {
        guard let entry = compactNoteHistory.goForward() else { return }
        replaceCompactVisibleNote(with: entry)
    }

    private func replaceCompactVisibleNote(with entry: NoteStackEntry) {
        path = NavigationPath()
        path.append(noteRoute(for: entry))
    }

    private func noteRoute(for entry: NoteStackEntry) -> NoteRoute {
        .note(
            entry.note,
            directoryURL: entry.directoryURL,
            vaultRootURL: entry.vaultRootURL,
            isNew: entry.isNew
        )
    }

    private func updateCompactHistory(_ note: MarkdownNote) {
        compactNoteHistory.replaceEntries(for: note)
        if let currentEntry = compactNoteHistory.currentEntry, currentEntry.note.id == note.id {
            compactNoteHistory.replaceCurrent(currentEntry.replacingNote(note))
        }
    }
    #endif

    private func persistLastOpenedNoteURL(_ url: URL?) {
        if let path = url?.path {
            UserDefaults.standard.set(path, forKey: Self.lastOpenedNoteKey)
        }
    }

    private func restoreOrOpenToday() {
        // Try to restore the last opened note first.
        if let savedPath = UserDefaults.standard.string(forKey: Self.lastOpenedNoteKey),
           FileManager.default.fileExists(atPath: savedPath) {
            let fileURL = URL(fileURLWithPath: savedPath)
            let directoryURL = fileURL.deletingLastPathComponent()
            let noteStore = MarkdownNoteStore(
                directoryURL: directoryURL,
                vaultRootURL: store.vaultRootURL,
                autoload: false,
                directoryLoader: store.directoryLoader
            )

            selectNote(restoredNote(for: fileURL), in: noteStore, isNew: false)
            return
        }

        // Fall back to today's note when there is no saved selection.
        openTodayNote()
    }

    private func openInitialDocumentLinkOrRestore() {
        if let initialDocumentLink,
           let resolved = store.note(atVaultRelativePath: initialDocumentLink) {
            openNoteFromWorkspace(resolved.note, in: resolved.store, isNew: false)
            return
        }

        restoreOrOpenToday()
    }

    private func restoredNote(for fileURL: URL) -> MarkdownNote {
        let modifiedAt = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        let titleResolver = NoteTitleResolver()
        return MarkdownNote(
            id: VaultDirectoryLoader.stableID(for: fileURL),
            fileURL: fileURL,
            title: titleResolver.fallbackTitle(for: fileURL),
            modifiedDate: modifiedAt
        )
    }

    #if os(iOS)
    private func collapseSidebar() {
    }
    #else
    private func collapseSidebar() {}
    #endif
}

/// Resolves and displays today's note (iOS only — macOS opens inline).
private struct TodayNoteDestination: View {
    var store: MarkdownNoteStore
    var fileWatcher: VaultFileWatcher?
    var onOpenTodayNote: (() -> Void)?
    var onCreateRootNote: (() -> Void)?
    var onTapBreadcrumbLevel: ((URL) -> Void)?
    var onNoteUpdated: ((MarkdownNote) -> Void)?
    var onOpenDocumentLink: ((String) -> Void)?
    var canNavigateBack: Bool = false
    var canNavigateForward: Bool = false
    var onNavigateBack: (() -> Void)?
    var onNavigateForward: (() -> Void)?
    @State private var data: (store: MarkdownNoteStore, note: MarkdownNote)?

    var body: some View {
        Group {
            if let data {
                NoteEditorScreen(
                    store: data.store,
                    note: data.note,
                    fileWatcher: fileWatcher,
                    onOpenTodayNote: onOpenTodayNote,
                    onCreateRootNote: onCreateRootNote,
                    onTapBreadcrumbLevel: onTapBreadcrumbLevel,
                    onNoteUpdated: onNoteUpdated,
                    onOpenDocumentLink: onOpenDocumentLink,
                    canNavigateBack: canNavigateBack,
                    canNavigateForward: canNavigateForward,
                    onNavigateBack: onNavigateBack,
                    onNavigateForward: onNavigateForward,
                    chromeMode: .compactNavigation(showsInlineBackButton: true)
                )
            } else {
                ProgressView()
            }
        }
        .task {
            data = store.todayNote()
        }
    }
}

// MARK: - Directory Content

enum DirectoryContentListPresentation {
    case content
    case sidebar
}

/// Shared directory page body that shows one directory's direct folders and notes.
struct DirectoryContentListView: View {
    var store: MarkdownNoteStore
    var fileWatcher: VaultFileWatcher?
    var selectedNote: MarkdownNote?
    var presentation: DirectoryContentListPresentation = .content
    var onOpenFolder: (NotoFolder, MarkdownNoteStore) -> Void
    var onOpenNote: (MarkdownNote, MarkdownNoteStore, Bool) -> Void
    var onDeleteItem: (DirectoryItem, MarkdownNoteStore) -> Void
    #if os(macOS)
    var onNoteDrag: ((MarkdownNote) -> NSItemProvider)? = nil
    #endif

    var body: some View {
        List {
            ForEach(store.items) { item in
                switch item {
                case .folder(let folder):
                    folderButton(folder)
                case .note(let note):
                    noteButton(note)
                }
            }
            .onDelete(perform: deleteItems)
            .listRowBackground(rowBackground)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(listBackground)
        .foregroundStyle(AppTheme.primaryText)
        .tint(AppTheme.primaryText)
        .fileExplorerBottomToolbarInset()
        .accessibilityIdentifier("note_list")
        .task(id: store.directoryURL.standardizedFileURL.path) {
            store.loadItemsInBackground()
        }
        .onChange(of: fileWatcher?.changeCount) { _, _ in
            store.loadItemsInBackground()
        }
        .onReceive(NotificationCenter.default.publisher(for: NoteSyncCenter.notificationName)) { notification in
            guard let snapshot = notification.object as? NoteSyncSnapshot else { return }
            guard snapshot.fileURL.deletingLastPathComponent().standardizedFileURL == store.directoryURL.standardizedFileURL else {
                return
            }
            store.loadItemsInBackground()
        }
        .overlay {
            if store.isLoadingItems {
                ProgressView()
                    .allowsHitTesting(false)
            } else if store.items.isEmpty {
                ContentUnavailableView(
                    "Empty",
                    systemImage: "folder",
                    description: Text(emptyDirectoryDescription)
                )
                .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func folderButton(_ folder: NotoFolder) -> some View {
        Button {
            onOpenFolder(folder, store)
        } label: {
            switch presentation {
            case .content:
                FolderRow(folder: folder)
            case .sidebar:
                SidebarDirectoryRow(
                    systemImage: "folder.fill",
                    title: folder.name,
                    subtitle: folder.contentsSummary,
                    isSelected: false
                )
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier("folder_\(folder.name)")
    }

    @ViewBuilder
    private func noteButton(_ note: MarkdownNote) -> some View {
        let isSelected = selectedNote?.fileURL.standardizedFileURL == note.fileURL.standardizedFileURL
        let button = Button {
            onOpenNote(note, store, false)
        } label: {
            switch presentation {
            case .content:
                MarkdownNoteRow(note: note)
            case .sidebar:
                SidebarDirectoryRow(
                    systemImage: "doc",
                    title: note.title,
                    subtitle: note.modifiedDate.formatted(.relative(presentation: .numeric)),
                    isSelected: isSelected
                )
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier("note_\(note.title)")

        #if os(macOS)
        if let onNoteDrag {
            button.onDrag {
                onNoteDrag(note)
            }
        } else {
            button
        }
        #else
        button
        #endif
    }

    private var rowBackground: some View {
        switch presentation {
        case .content:
            AppTheme.background
        case .sidebar:
            Color.clear
        }
    }

    private var listBackground: some View {
        switch presentation {
        case .content:
            AppTheme.background
        case .sidebar:
            AppTheme.sidebarBackground
        }
    }

    private var emptyDirectoryDescription: String {
        switch presentation {
        case .content:
            "Tap + to create a note or folder"
        case .sidebar:
            "Secondary-click to create a note or folder"
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            onDeleteItem(store.items[index], store)
        }
    }
}

private extension View {
    @ViewBuilder
    func fileExplorerBottomToolbarInset() -> some View {
        #if os(iOS)
        self.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: 80)
                .allowsHitTesting(false)
        }
        #else
        self
        #endif
    }
}

private struct SidebarDirectoryRow: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.body.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AppTheme.primaryText : AppTheme.secondaryText)
                .frame(width: 18, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AppTheme.primaryText : AppTheme.secondaryText)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isSelected ? AppTheme.selectedRowBackground : Color.clear)
        }
    }
}

#if os(iOS)
struct FolderContentView: View {
    @State private var store: MarkdownNoteStore
    let title: String
    var isRoot: Bool = false
    var fileWatcher: VaultFileWatcher?
    var onIntent: (VaultWorkspaceIntent) -> Void
    var canOpenSettings = false

    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""

    init(
        store: MarkdownNoteStore,
        title: String,
        isRoot: Bool = false,
        fileWatcher: VaultFileWatcher? = nil,
        onIntent: @escaping (VaultWorkspaceIntent) -> Void,
        canOpenSettings: Bool = false
    ) {
        _store = State(wrappedValue: store)
        self.title = title
        self.isRoot = isRoot
        self.fileWatcher = fileWatcher
        self.onIntent = onIntent
        self.canOpenSettings = canOpenSettings
    }

    var body: some View {
        DirectoryContentListView(
            store: store,
            fileWatcher: fileWatcher,
            presentation: .content,
            onOpenFolder: { folder, parentStore in
                onIntent(.openFolder(folder, parentStore: parentStore))
            },
            onOpenNote: { note, noteStore, isNew in
                onIntent(.openNote(note, store: noteStore, isNew: isNew))
            },
            onDeleteItem: { item, noteStore in
                onIntent(.deleteItem(item, in: noteStore))
            }
        )
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isRoot, canOpenSettings {
                    Button {
                        onIntent(.openSettings)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("settings_button")
                }
                Button(action: createNote) {
                    Label("New Note", systemImage: "doc.badge.plus")
                }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("new_note_button")
                Menu {
                    Button(action: { showNewFolderAlert = true }) {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    .accessibilityIdentifier("new_folder_button")
                } label: {
                    Label("More", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("add_menu")
            }
        }
        .alert("New Folder", isPresented: $showNewFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                let name = newFolderName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    onIntent(.createFolder(named: name, in: store))
                }
                newFolderName = ""
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
    }

    private func createNote() {
        onIntent(.createNote(in: store))
    }

}
#endif

// MARK: - Shared iOS Bottom Toolbar

#if os(iOS)
enum NotoAppBottomToolbarKeyboardVisibility {
    static let minimumVisibleHeight: CGFloat = 100

    static func isSoftwareKeyboardVisible(frameInScreen: CGRect?, screenBounds: CGRect) -> Bool {
        guard let frameInScreen, !frameInScreen.isNull, !frameInScreen.isEmpty else {
            return false
        }

        let visibleFrame = frameInScreen.intersection(screenBounds)
        guard !visibleFrame.isNull, !visibleFrame.isEmpty else {
            return false
        }

        return visibleFrame.height > minimumVisibleHeight
    }
}

private struct NotoAppBottomToolbarModifier: ViewModifier {
    var onOpenTodayNote: (() -> Void)?
    var onSearch: (() -> Void)?
    var onCreateRootNote: (() -> Void)?
    @State private var isSoftwareKeyboardVisible = false

    func body(content: Content) -> some View {
        if !showsToolbar {
            content
        } else {
            content.overlay(alignment: .bottom) {
                if !isSoftwareKeyboardVisible {
                    HStack {
                        Spacer(minLength: 0)
                        NotoAppBottomToolbar(
                            onOpenTodayNote: onOpenTodayNote,
                            onSearch: onSearch,
                            onCreateRootNote: onCreateRootNote
                        )
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                updateKeyboardVisibility(from: notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
                updateKeyboardVisibility(from: notification)
            }
        }
    }

    private var showsToolbar: Bool {
        onOpenTodayNote != nil || onSearch != nil || onCreateRootNote != nil
    }

    private func updateKeyboardVisibility(from notification: Notification) {
        let frameInScreen = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let isVisible = NotoAppBottomToolbarKeyboardVisibility.isSoftwareKeyboardVisible(
            frameInScreen: frameInScreen,
            screenBounds: UIScreen.main.bounds
        )

        withAnimation(.easeOut(duration: duration)) {
            isSoftwareKeyboardVisible = isVisible
        }
    }
}

private struct NotoAppBottomToolbar: View {
    var onOpenTodayNote: (() -> Void)?
    var onSearch: (() -> Void)?
    var onCreateRootNote: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            Button {
                onOpenTodayNote?()
            } label: {
                toolbarLabel("Today", systemImage: "calendar")
            }
            .accessibilityIdentifier("today_button")
            .accessibilityLabel("Today")

            Button {
                onSearch?()
            } label: {
                toolbarLabel("Search", systemImage: "magnifyingglass")
            }
            .accessibilityIdentifier("search_button")
            .accessibilityLabel("Search")

            Button {
                onCreateRootNote?()
            } label: {
                toolbarLabel("New Note", systemImage: "square.and.pencil")
            }
            .accessibilityIdentifier("new_root_note_button")
            .accessibilityLabel("New Note")
        }
        .buttonStyle(.plain)
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(AppTheme.primaryText)
        .padding(.horizontal, 8)
        .frame(height: 48)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(AppTheme.primaryText.opacity(0.08), lineWidth: 0.5)
        }
    }

    private func toolbarLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
    }
}

extension View {
    func notoAppBottomToolbar(
        onOpenTodayNote: (() -> Void)?,
        onSearch: (() -> Void)?,
        onCreateRootNote: (() -> Void)?
    ) -> some View {
        modifier(NotoAppBottomToolbarModifier(
            onOpenTodayNote: onOpenTodayNote,
            onSearch: onSearch,
            onCreateRootNote: onCreateRootNote
        ))
    }
}
#endif

// MARK: - Note Search Sheet

struct NoteSearchResult: Identifiable {
    let id: String
    let note: MarkdownNote
    let store: MarkdownNoteStore
    let relativePath: String
    let title: String
    let breadcrumb: String
    let snippet: String
    let kind: SearchResultKind
}

#if DEBUG
private struct NoteSearchDebugEvent: Identifiable {
    let id = UUID()
    let message: String
}
#endif

private struct NoteSearchExecutionResult {
    let results: [SearchResult]
    let path: String
    let debugMessages: [String]
}

private extension SearchScope {
    var segmentTitle: String {
        switch self {
        case .titleAndContent:
            "Title + Content"
        case .title:
            "Title"
        }
    }

    var shortcutCaption: String {
        switch self {
        case .titleAndContent:
            "⌘1"
        case .title:
            "⌘2"
        }
    }

    var shortcutKey: KeyEquivalent {
        switch self {
        case .titleAndContent:
            "1"
        case .title:
            "2"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .titleAndContent:
            "Search title and content"
        case .title:
            "Search title only"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .titleAndContent:
            "note_search_scope_title_and_content"
        case .title:
            "note_search_scope_title_only"
        }
    }
}

struct NoteSearchSheet: View {
    var rootStore: MarkdownNoteStore
    var onClose: (() -> Void)? = nil
    var onSelect: (NoteSearchResult) -> Void

    #if os(macOS)
    private static let macOSPanelPreferredWidth: CGFloat = 620
    private static let macOSPanelHeight: CGFloat = 560
    #endif

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFocused: Bool
    @State private var query = ""
    @State private var scope: SearchScope = .titleAndContent
    @State private var results: [NoteSearchResult] = []
    @State private var isPreparingIndex = false
    @State private var isSearching = false
    @State private var didFail = false
    @State private var searchTask: Task<Void, Never>?
    #if os(macOS)
    @State private var selectedResultIndex: Int?
    #endif
    #if DEBUG
    @State private var debugPath = "Idle"
    @State private var debugEvents: [NoteSearchDebugEvent] = [
        NoteSearchDebugEvent(message: "Search sheet opened")
    ]
    #endif

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        #if os(macOS)
        macOSSearchPanel
        #else
        Group {
            if didFail {
                ContentUnavailableView(
                    "Search Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Noto could not load notes from this vault.")
                )
            } else {
                resultsList
            }
        }
        .background(AppTheme.background)
        .navigationTitle("Search")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                closeButton
            }
            #else
            ToolbarItem(placement: .cancellationAction) {
                closeButton
            }
            #endif
        }
        .noteSearchField(text: $query)
        .noteSearchFocused($isSearchFocused)
        .accessibilityIdentifier("note_search_sheet")
        .task {
            isSearchFocused = true
            await prepareIndex()
        }
        .onChange(of: query) { _, _ in
            scheduleSearch()
        }
        .onChange(of: scope) { _, _ in
            scheduleSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notoSearchIndexDidChange)) { notification in
            handleSearchIndexDidChange(notification)
        }
        .onDisappear {
            searchTask?.cancel()
        }
        #endif
    }

    private var closeButton: some View {
        Button {
            closeSearch()
        } label: {
            Label("Close", systemImage: "xmark")
        }
        .labelStyle(.iconOnly)
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("note_search_cancel_button")
        .accessibilityLabel("Close")
    }

    private func closeSearch() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    #if os(macOS)
    private var macOSSearchPanel: some View {
        VStack(spacing: 0) {
            macOSTopBar
            macOSSearchControls
            resultsList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(maxWidth: Self.macOSPanelPreferredWidth, maxHeight: Self.macOSPanelHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.primaryText.opacity(0.12), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 28, y: 18)
        .foregroundStyle(AppTheme.primaryText)
        .tint(AppTheme.primaryText)
        .accessibilityIdentifier("note_search_sheet")
        .background {
            MacSearchKeyHandler(
                onMoveSelection: moveSelection,
                onOpenSelection: openSelectedResult,
                onDismiss: {
                    closeSearch()
                }
            )
            .frame(width: 0, height: 0)
        }
        .task {
            isSearchFocused = true
            await prepareIndex()
        }
        .onChange(of: query) { _, _ in
            scheduleSearch()
        }
        .onChange(of: scope) { _, _ in
            scheduleSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notoSearchIndexDidChange)) { notification in
            handleSearchIndexDidChange(notification)
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private var macOSTopBar: some View {
        ZStack {
            Text("Search")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            HStack {
                Spacer()
                closeButton
                    .buttonStyle(.borderless)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.trailing, 16)
            }
        }
        .frame(height: 48)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.separator)
                .frame(height: 1)
        }
    }

    private var macOSSearchControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.secondaryText)
                    .font(.system(size: 14, weight: .medium))

                TextField("Search notes", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .font(.body)
                    .accessibilityIdentifier("note_search_query_field")

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Label("Clear Search", systemImage: "xmark.circle.fill")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityIdentifier("note_search_clear_button")
                    .accessibilityLabel("Clear Search Text")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(AppTheme.primaryText.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.primaryText.opacity(0.10), lineWidth: 0.5)
            }

            searchScopePicker
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.background.opacity(0.78))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.separator)
                .frame(height: 1)
        }
    }
    #endif

    private var searchScopePicker: some View {
        HStack(spacing: 0) {
            searchScopeSegment(for: .titleAndContent)
            searchScopeSegment(for: .title)
        }
        .padding(2)
        .background(AppTheme.primaryText.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.primaryText.opacity(0.10), lineWidth: 0.5)
        }
        .accessibilityIdentifier("note_search_scope_picker")
    }

    private func searchScopeSegment(for candidate: SearchScope) -> some View {
        let isSelected = scope == candidate

        return Button {
            scope = candidate
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(candidate.segmentTitle)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                Text(candidate.shortcutCaption)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? AppTheme.primaryText.opacity(0.72) : AppTheme.secondaryText)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.86)
            .frame(maxWidth: .infinity, minHeight: 34)
            .padding(.horizontal, 8)
            .foregroundStyle(isSelected ? AppTheme.primaryText : AppTheme.secondaryText)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AppTheme.primaryText.opacity(0.14))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(candidate.shortcutKey, modifiers: [.command])
        .accessibilityLabel(candidate.accessibilityLabel)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier(candidate.accessibilityIdentifier)
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            searchScopePicker
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            #endif

            ScrollViewReader { proxy in
                Group {
                #if os(macOS)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            Button {
                                onSelect(result)
                                closeSearch()
                            } label: {
                                NoteSearchResultRow(result: result)
                                    .padding(.horizontal, 12)
                                    .background(index == selectedResultIndex ? AppTheme.selectedRowBackground : AppTheme.background)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("note_search_result_\(index)")
                            .accessibilityLabel(result.title)
                            .id(result.id)
                            .onHover { isHovering in
                                if isHovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                        }
                    }
                }
                .background(AppTheme.background)
                .foregroundStyle(AppTheme.primaryText)
                .tint(AppTheme.primaryText)
                .accessibilityIdentifier("note_search_results_list")
                .onChange(of: selectedResultIndex) { _, selectedResultIndex in
                    guard let selectedResultIndex, results.indices.contains(selectedResultIndex) else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(results[selectedResultIndex].id, anchor: .center)
                    }
                }
                #else
                List {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        Button {
                            onSelect(result)
                            closeSearch()
                        } label: {
                            NoteSearchResultRow(result: result)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("note_search_result_\(index)")
                        .accessibilityLabel(result.title)
                        .listRowBackground(AppTheme.background)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(AppTheme.background)
                .foregroundStyle(AppTheme.primaryText)
                .tint(AppTheme.primaryText)
                .accessibilityIdentifier("note_search_results_list")
                #endif
                }
                .overlay {
                    if isPreparingIndex && results.isEmpty {
                        searchProgressIndicator(
                            title: "Indexing notes",
                            message: "Checking this vault for new, edited, moved, or deleted notes.",
                            accessibilityIdentifier: "note_search_indexing_indicator"
                        )
                    } else if isSearching && results.isEmpty {
                        searchProgressIndicator(
                            title: "Searching notes",
                            message: "Looking through the search index.",
                            accessibilityIdentifier: "note_search_loading_indicator"
                        )
                    } else if results.isEmpty {
                        ContentUnavailableView(
                            emptyTitle,
                            systemImage: "magnifyingglass",
                            description: Text(emptyDescription)
                        )
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("note_search_empty_state")
                    }
                }
            }

        }
    }

    #if DEBUG
    private func updateDebug(path: String? = nil, _ messages: [String]) {
        if let path {
            debugPath = path
        }
        guard !messages.isEmpty else { return }
        debugEvents.append(contentsOf: messages.map(NoteSearchDebugEvent.init(message:)))
        if debugEvents.count > 20 {
            debugEvents.removeFirst(debugEvents.count - 20)
        }
    }
    #endif

    private func searchProgressIndicator(
        title: String,
        message: String,
        accessibilityIdentifier: String
    ) -> some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
            Text(message)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var emptyTitle: String {
        trimmedQuery.isEmpty ? "Search Notes" : "No Matching Notes"
    }

    private var emptyDescription: String {
        if trimmedQuery.isEmpty {
            return scope == .title
                ? "Type a note title to search this vault."
                : "Type to search note titles and content."
        }
        return scope == .title
            ? "Try another title."
            : "Try another title or keyword."
    }

    private func prepareIndex() async {
        didFail = false
        let rootURL = rootStore.vaultRootURL
        #if DEBUG
        updateDebug(path: "Opening", ["checking existing index"])
        #endif
        let indexStatus = await Task.detached(priority: .userInitiated) {
            Self.existingSearchIndexStatus(for: rootURL)
        }.value
        if indexStatus.hasIndex {
            isPreparingIndex = false
            #if DEBUG
            updateDebug(
                path: "Index ready",
                [indexStatus.message, "sheet open refresh skipped; using existing index"]
            )
            #endif
            scheduleSearch()
            return
        }

        isPreparingIndex = true
        #if DEBUG
        updateDebug(
            path: "No index",
            [indexStatus.message, "building first index"]
        )
        #endif

        do {
            let result = try await SearchIndexController.shared.refresh(vaultURL: rootURL)
            #if DEBUG
            updateDebug(
                path: "Refreshed",
                ["refresh scanned=\(result.scanned) upserted=\(result.upserted) deleted=\(result.deleted) notes=\(result.stats.noteCount)"]
            )
            #endif
        } catch {
            logger.error("Search index refresh failed: \(error.localizedDescription)")
            #if DEBUG
            updateDebug(path: "Refresh failed", ["refresh error=\(String(describing: error))"])
            #endif
        }
        isPreparingIndex = false
        scheduleSearch()
    }

    nonisolated private static func hasExistingSearchIndex(for rootURL: URL) -> Bool {
        existingSearchIndexStatus(for: rootURL).hasIndex
    }

    nonisolated private static func existingSearchIndexStatus(for rootURL: URL) -> (hasIndex: Bool, message: String) {
        let indexer = MarkdownSearchIndexer(vaultURL: rootURL)
        let databaseURL = indexer.indexDirectory.appendingPathComponent("search.sqlite")
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return (false, "index missing path=\(databaseURL.path)")
        }

        do {
            let stats = try indexer.openStore().stats()
            return (stats.noteCount > 0, "index notes=\(stats.noteCount) sections=\(stats.sectionCount)")
        } catch {
            return (false, "index probe error=\(String(describing: error))")
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        guard !didFail else { return }
        guard !trimmedQuery.isEmpty else {
            results = []
            isSearching = false
            #if os(macOS)
            selectedResultIndex = nil
            #endif
            #if DEBUG
            updateDebug(path: "Idle", ["query empty"])
            #endif
            return
        }

        let requestQuery = trimmedQuery
        let requestScope = scope
        let rootURL = rootStore.vaultRootURL
        let rootStore = rootStore
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }

            let searchResult = await Task.detached(priority: .userInitiated) {
                Result {
                    try Self.searchNotes(
                        query: requestQuery,
                        scope: requestScope,
                        rootURL: rootURL
                    )
                }
            }.value

            guard !Task.isCancelled else { return }
            switch searchResult {
            case .success(let execution):
                let displayResults = SearchResultDisplayPolicy.hidingNoteMatchesCoveredBySections(execution.results)
                results = displayResults.map { result in
                    appResult(for: result, rootStore: rootStore)
                }
                #if os(macOS)
                selectedResultIndex = results.isEmpty ? nil : 0
                #endif
                didFail = false
                #if DEBUG
                updateDebug(path: execution.path, execution.debugMessages)
                #endif
            case .failure:
                results = []
                #if os(macOS)
                selectedResultIndex = nil
                #endif
                didFail = true
                #if DEBUG
                updateDebug(path: "Unavailable", ["search task failed"])
                #endif
            }
            isSearching = false
        }
    }

    private func handleSearchIndexDidChange(_ notification: Notification) {
        guard let vaultPath = notification.userInfo?["vaultPath"] as? String,
              vaultPath == rootStore.vaultRootURL.standardizedFileURL.path else {
            return
        }

        #if DEBUG
        updateDebug(path: debugPath, ["index changed for current vault"])
        #endif
        scheduleSearch()
    }

    nonisolated private static func searchNotes(query: String, scope: SearchScope, rootURL: URL) throws -> NoteSearchExecutionResult {
        let indexer = MarkdownSearchIndexer(vaultURL: rootURL)
        var debugMessages = ["query=\(query)"]
        do {
            let results = try searchNotes(query: query, scope: scope, rootURL: rootURL, indexer: indexer)
            debugMessages.append("sqlite results=\(results.count)")
            return NoteSearchExecutionResult(results: results, path: "SQLite", debugMessages: debugMessages)
        } catch {
            DebugTrace.record("search sqlite failed query=\(query) error=\(String(describing: error))")
            debugMessages.append("sqlite error=\(String(describing: error))")
            do {
                let store = try indexer.openStore()
                try store.destroy()
                let refresh = try indexer.refreshChangedFiles()
                debugMessages.append("rebuild scanned=\(refresh.scanned) upserted=\(refresh.upserted) deleted=\(refresh.deleted)")
                let results = try searchNotes(query: query, scope: scope, rootURL: rootURL, indexer: indexer)
                debugMessages.append("sqlite retry results=\(results.count)")
                return NoteSearchExecutionResult(results: results, path: "SQLite retry", debugMessages: debugMessages)
            } catch {
                DebugTrace.record("search sqlite retry failed query=\(query) error=\(String(describing: error))")
                debugMessages.append("sqlite retry error=\(String(describing: error))")
                do {
                    let results = try fallbackSearchNotes(query: query, scope: scope, rootURL: rootURL, indexer: indexer)
                    debugMessages.append("vault scan results=\(results.count)")
                    return NoteSearchExecutionResult(results: results, path: "Vault scan", debugMessages: debugMessages)
                } catch {
                    debugMessages.append("vault scan error=\(String(describing: error))")
                    return NoteSearchExecutionResult(results: [], path: "Failed empty", debugMessages: debugMessages)
                }
            }
        }
    }

    nonisolated private static func searchNotes(
        query: String,
        scope: SearchScope,
        rootURL: URL,
        indexer: MarkdownSearchIndexer
    ) throws -> [SearchResult] {
        let engine = MarkdownSearchEngine(store: try indexer.openStore(), vaultURL: rootURL)
        return try engine.search(query, scope: scope, limit: 60)
    }

    nonisolated private static func fallbackSearchNotes(
        query: String,
        scope: SearchScope,
        rootURL: URL,
        indexer: MarkdownSearchIndexer
    ) throws -> [SearchResult] {
        let terms = MarkdownSearchEngine.boostTerms(for: query)
        guard !terms.isEmpty else { return [] }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let documents = try indexer.scanDocuments()
        var results: [SearchResult] = []

        for entry in documents {
            let document = entry.document
            let normalizedTitle = document.title.lowercased()
            let normalizedContent = document.plainText.lowercased()
            let titleMatches = matchesSearchText(normalizedTitle, terms: terms, phrase: normalizedQuery)
            let contentMatches = scope == .titleAndContent
                && matchesSearchText(normalizedContent, terms: terms, phrase: normalizedQuery)

            if titleMatches || contentMatches {
                results.append(
                    SearchResult(
                        id: document.id,
                        kind: .note,
                        noteID: document.id,
                        fileURL: rootURL.appendingPathComponent(document.relativePath),
                        title: document.title,
                        breadcrumb: document.folderPath,
                        snippet: fallbackSnippet(
                            title: document.title,
                            content: document.plainText,
                            terms: terms
                        ),
                        lineStart: nil,
                        score: fallbackScore(titleMatches: titleMatches, updatedAt: entry.fileModifiedAt),
                        updatedAt: entry.fileModifiedAt
                    )
                )
            }
        }

        return results
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .prefix(60)
            .map { $0 }
    }

    nonisolated private static func matchesSearchText(_ text: String, terms: [String], phrase: String) -> Bool {
        if terms.count > 1, text.contains(phrase) {
            return true
        }
        return terms.allSatisfy { text.contains($0) }
    }

    nonisolated private static func fallbackSnippet(title: String, content: String, terms: [String]) -> String {
        guard let firstTerm = terms.first,
              let range = content.range(of: firstTerm, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return title
        }

        let lowerBound = content.index(range.lowerBound, offsetBy: -80, limitedBy: content.startIndex) ?? content.startIndex
        let upperBound = content.index(range.upperBound, offsetBy: 120, limitedBy: content.endIndex) ?? content.endIndex
        return String(content[lowerBound..<upperBound])
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func fallbackScore(titleMatches: Bool, updatedAt: Date) -> Double {
        let age = max(0, Date().timeIntervalSince(updatedAt))
        let ageInDays = age / 86_400
        return (titleMatches ? 10 : 0) + exp(-ageInDays / 30)
    }

    private func appResult(for result: SearchResult, rootStore: MarkdownNoteStore) -> NoteSearchResult {
        let relativePath = rootStore.vaultRelativePath(for: result.fileURL) ?? result.fileURL.lastPathComponent
        let resolved = rootStore.note(atVaultRelativePath: relativePath)
        let note = resolved?.note ?? MarkdownNote(
            id: result.noteID,
            fileURL: result.fileURL,
            title: result.fileURL.deletingPathExtension().lastPathComponent,
            modifiedDate: result.updatedAt ?? Date()
        )
        let store = resolved?.store ?? MarkdownNoteStore(
            directoryURL: result.fileURL.deletingLastPathComponent(),
            vaultRootURL: rootStore.vaultRootURL,
            autoload: false,
            directoryLoader: rootStore.directoryLoader
        )

        return NoteSearchResult(
            id: "\(result.id.uuidString)-\(result.lineStart ?? 0)",
            note: note,
            store: store,
            relativePath: relativePath,
            title: result.title,
            breadcrumb: result.breadcrumb.isEmpty ? relativePath : result.breadcrumb,
            snippet: result.snippet,
            kind: result.kind
        )
    }

    #if os(macOS)
    private func moveSelection(_ direction: SearchResultSelectionDirection) {
        guard !results.isEmpty else { return }
        let currentIndex = selectedResultIndex ?? 0
        switch direction {
        case .up:
            selectedResultIndex = max(0, currentIndex - 1)
        case .down:
            selectedResultIndex = min(results.count - 1, currentIndex + 1)
        }
    }

    private func openSelectedResult() {
        guard let selectedResultIndex, results.indices.contains(selectedResultIndex) else { return }
        onSelect(results[selectedResultIndex])
        closeSearch()
    }
    #endif
}

private struct NoteSearchResultRow: View {
    let result: NoteSearchResult

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: result.kind == .section ? "text.alignleft" : "doc.text")
                .foregroundStyle(AppTheme.secondaryText)
                .font(.title3)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                if !result.breadcrumb.isEmpty {
                    Text(result.breadcrumb)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }
                if !result.snippet.isEmpty, result.snippet != result.title {
                    Text(result.snippet)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private extension View {
    @ViewBuilder
    func noteSearchField(text: Binding<String>) -> some View {
        #if os(iOS)
        self.searchable(
            text: text,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search notes"
        )
        #else
        self.searchable(
            text: text,
            prompt: "Search notes"
        )
        #endif
    }

    @ViewBuilder
    func noteSearchFocused(_ isFocused: FocusState<Bool>.Binding) -> some View {
        #if os(iOS)
        self.searchFocused(isFocused)
        #else
        self
        #endif
    }
}

extension View {
    @ViewBuilder
    func noteSearchSheetPresentationStyle() -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            self.presentationSizing(.page)
        } else {
            self
        }
        #else
        self.frame(minHeight: 560)
        #endif
    }
}

#if os(macOS)
private enum SearchResultSelectionDirection {
    case up
    case down
}

private struct MacSearchKeyHandler: NSViewRepresentable {
    var onMoveSelection: (SearchResultSelectionDirection) -> Void
    var onOpenSelection: () -> Void
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onMoveSelection: onMoveSelection,
            onOpenSelection: onOpenSelection,
            onDismiss: onDismiss
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install()
        DispatchQueue.main.async {
            context.coordinator.window = view.window
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onMoveSelection = onMoveSelection
        context.coordinator.onOpenSelection = onOpenSelection
        context.coordinator.onDismiss = onDismiss
        DispatchQueue.main.async {
            context.coordinator.window = view.window
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var onMoveSelection: (SearchResultSelectionDirection) -> Void
        var onOpenSelection: () -> Void
        var onDismiss: () -> Void
        weak var window: NSWindow?
        private var monitor: Any?

        init(
            onMoveSelection: @escaping (SearchResultSelectionDirection) -> Void,
            onOpenSelection: @escaping () -> Void,
            onDismiss: @escaping () -> Void
        ) {
            self.onMoveSelection = onMoveSelection
            self.onOpenSelection = onOpenSelection
            self.onDismiss = onDismiss
        }

        deinit {
            removeMonitor()
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                guard let window = self.window, event.window === window else { return event }
                switch event.keyCode {
                case 126:
                    self.onMoveSelection(.up)
                    return nil
                case 125:
                    self.onMoveSelection(.down)
                    return nil
                case 36, 76:
                    self.onOpenSelection()
                    return nil
                case 53:
                    self.onDismiss()
                    return nil
                default:
                    if event.charactersIgnoringModifiers == "\u{1B}" {
                        self.onDismiss()
                        return nil
                    }
                    return event
                }
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

private struct WindowCommandReader: NSViewRepresentable {
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

// MARK: - Row Views

struct FolderRow: View {
    let folder: NotoFolder

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(AppTheme.secondaryText)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                Text(folder.contentsSummary)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private extension NotoFolder {
    var contentsSummary: String {
        "\(itemCount) \(itemCount == 1 ? "file" : "files"), \(folderCount) \(folderCount == 1 ? "folder" : "folders")"
    }
}

struct MarkdownNoteRow: View {
    let note: MarkdownNote

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(AppTheme.secondaryText)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                Text(note.modifiedDate, style: .relative)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
