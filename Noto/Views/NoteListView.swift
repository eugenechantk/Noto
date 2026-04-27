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

// MARK: - Root View

/// Root entry point — NavigationStack on iOS, NavigationSplitView on macOS.
struct NoteListView: View {
    var store: MarkdownNoteStore
    var locationManager: VaultLocationManager?
    var fileWatcher: VaultFileWatcher?
    @ObservedObject var readwiseSyncController: ReadwiseSyncController

    #if os(iOS)
    @State private var path = NavigationPath()
    @State private var compactNoteHistory = NoteNavigationHistory()
    @State private var isNoteSearchPresented = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var selectedNote: MarkdownNote?
    @State private var selectedNoteStore: MarkdownNoteStore?
    @State private var selectedNoteIsNew = false
    @State private var externallyDeletingNoteID: UUID?
    @State private var showSettings = false
    @State private var hasRestoredSelection = false
    #if os(macOS)
    @State private var hostingWindow: NSWindow?
    #endif

    private static let lastOpenedNoteKey = "lastOpenedNoteURL"

    var body: some View {
        #if os(iOS)
        if horizontalSizeClass == .regular {
            NotoSplitView(
                store: store,
                fileWatcher: fileWatcher,
                selectedNote: $selectedNote,
                selectedNoteStore: $selectedNoteStore,
                selectedIsNew: $selectedNoteIsNew,
                externallyDeletingNoteID: $externallyDeletingNoteID,
                onOpenTodayNote: openTodayNote
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
                restoreOrOpenToday()
            }
        } else {
            NavigationStack(path: $path) {
                FolderContentView(
                    store: store,
                    title: "Notes",
                    isRoot: true,
                    fileWatcher: fileWatcher,
                    path: $path,
                    onOpenNote: openCompactNote,
                    onTodayTap: { path.append(NoteRoute.todayNote) },
                    onCreateRootNote: createRootNoteAndPush,
                    onSettingsTap: locationManager != nil ? { path.append(NoteRoute.settings) } : nil
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
                            path: $path,
                            onOpenNote: openCompactNote,
                            onTodayTap: { path.append(NoteRoute.todayNote) },
                            onCreateRootNote: createRootNoteAndPush
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
                onOpenTodayNote: { path.append(NoteRoute.todayNote) },
                onSearch: { isNoteSearchPresented = true },
                onCreateRootNote: createRootNoteAndPush
            )
            .sheet(isPresented: $isNoteSearchPresented) {
                NavigationStack {
                    NoteSearchSheet(rootStore: store) { result in
                        openCompactNote(result.note, in: result.store, isNew: false)
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .noteSearchSheetPresentationStyle()
            }
            .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.openToday)) { _ in
                path.append(NoteRoute.todayNote)
            }
            .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.showSearch)) { _ in
                isNoteSearchPresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.openSettings)) { _ in
                if locationManager != nil {
                    path.append(NoteRoute.settings)
                }
            }
        }
        #elseif os(macOS)
        NotoSplitView(
            store: store,
            fileWatcher: fileWatcher,
            selectedNote: $selectedNote,
            selectedNoteStore: $selectedNoteStore,
            selectedIsNew: $selectedNoteIsNew,
            externallyDeletingNoteID: $externallyDeletingNoteID,
            onOpenTodayNote: openTodayNote
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
            restoreOrOpenToday()
        }
        #endif
    }

    private func openTodayNote() {
        let (todayStore, todayNote) = store.todayNote()
        selectNote(todayNote, in: todayStore, isNew: false)
    }

    private func openDocumentLinkInSelection(_ relativePath: String) {
        guard let resolved = store.note(atVaultRelativePath: relativePath) else { return }
        selectNote(resolved.note, in: resolved.store, isNew: false)
    }

    @ViewBuilder
    private var splitDetailView: some View {
        if let selectedNote, let selectedNoteStore {
            NoteEditorScreen(
                store: selectedNoteStore,
                note: selectedNote,
                isNew: selectedNoteIsNew,
                fileWatcher: fileWatcher,
                onDelete: {
                    self.selectedNote = nil
                    self.selectedNoteStore = nil
                    self.selectedNoteIsNew = false
                },
                onOpenTodayNote: { openTodayNote() },
                onCreateRootNote: { createRootNoteAndSelect() },
                onOpenDocumentLink: openDocumentLinkInSelection,
                externallyDeletingNoteID: $externallyDeletingNoteID,
                chromeMode: .compactNavigation(showsInlineBackButton: false)
            )
            .id(selectedNote.id)
        } else {
            Text("Select a note")
                .font(.title2)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.background)
        }
    }

    private func selectNote(_ note: MarkdownNote, in noteStore: MarkdownNoteStore, isNew: Bool) {
        selectedNoteStore = noteStore
        selectedNote = note
        selectedNoteIsNew = isNew
        collapseSidebar()
    }

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
    #endif

    private func createRootNoteAndSelect() {
        let note = store.createNote()
        selectNote(note, in: store, isNew: true)
    }

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
                directoryLoader: store.directoryLoader
            )

            if let note = noteStore.notes.first(where: { $0.fileURL.path == savedPath }) {
                selectNote(note, in: noteStore, isNew: false)
                return
            }
        }

        // Fall back to today's note when there is no saved selection.
        openTodayNote()
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
                    onOpenDocumentLink: onOpenDocumentLink,
                    canNavigateBack: canNavigateBack,
                    canNavigateForward: canNavigateForward,
                    onNavigateBack: onNavigateBack,
                    onNavigateForward: onNavigateForward
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

// MARK: - Shared Sidebar

/// Sidebar with Finder-style folder navigation.
/// - Clicking a folder drills into it (replaces sidebar content with that folder's items)
/// - Back button goes up one level
/// - Clicking a note opens it in the detail pane
struct SidebarView: View {
    var rootStore: MarkdownNoteStore
    var fileWatcher: VaultFileWatcher?
    @Binding var selectedNote: MarkdownNote?
    @Binding var selectedNoteStore: MarkdownNoteStore?
    @Binding var selectedIsNew: Bool
    @Binding var externallyDeletingNoteID: UUID?
    var onNoteActivated: (() -> Void)? = nil
    var onTodayTap: (() -> Void)? = nil
    var onCreateRootNote: (() -> Void)? = nil

    /// Stack of (store, title) for folder navigation. Empty = showing root.
    @State private var folderStack: [(store: MarkdownNoteStore, title: String)] = []
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""

    private var currentStore: MarkdownNoteStore {
        folderStack.last?.store ?? rootStore
    }

    private var currentTitle: String {
        folderStack.last?.title ?? "Notes"
    }

    private var canGoBack: Bool {
        !folderStack.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if canGoBack {
                    Button(action: goBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.caption.weight(.semibold))
                            Text(folderStack.count > 1 ? folderStack[folderStack.count - 2].title : "Notes")
                                .font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("back_button")
                }

                Spacer()

                Button(action: createNote) {
                    Label("New Note", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("new_note_button")
                .accessibilityLabel("New Note")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            List {
                ForEach(currentStore.items) { (item: DirectoryItem) in
                    sidebarRow(for: item)
                }
                .listRowBackground(AppTheme.background)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .contextMenu {
                Button(action: createNote) {
                    Label("New Note", systemImage: "doc.badge.plus")
                }
                Button(action: { showNewFolderAlert = true }) {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
        }
        .background(AppTheme.background)
        .foregroundStyle(AppTheme.primaryText)
        .tint(AppTheme.primaryText)
        .listStyle(.sidebar)
        .navigationTitle(currentTitle)
        .alert("New Folder", isPresented: $showNewFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                let name = newFolderName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    _ = currentStore.createFolder(name: name)
                }
                newFolderName = ""
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
        .onAppear {
            rootStore.loadItemsInBackground()
        }
    }

    @ViewBuilder
    private func sidebarRow(for item: DirectoryItem) -> some View {
        switch item {
        case .folder(let folder):
            SidebarFolderRow(
                folder: folder,
                rootStore: rootStore,
                fileWatcher: fileWatcher,
                selectedNote: $selectedNote,
                selectedNoteStore: $selectedNoteStore,
                selectedIsNew: $selectedIsNew,
                externallyDeletingNoteID: $externallyDeletingNoteID,
                onNoteActivated: onNoteActivated,
                onNavigate: { folder in
                    let subStore = MarkdownNoteStore(
                        directoryURL: folder.folderURL,
                        vaultRootURL: rootStore.vaultRootURL,
                        directoryLoader: rootStore.directoryLoader
                    )
                    folderStack.append((store: subStore, title: folder.name))
                },
                onDelete: {
                    currentStore.deleteFolder(folder)
                }
            )
        case .note(let note):
            Button {
                selectedNote = note
                selectedNoteStore = currentStore
                selectedIsNew = false
                onNoteActivated?()
            } label: {
                Label(note.title, systemImage: "doc.text")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("note_\(note.title)")
            .foregroundStyle(AppTheme.primaryText)
            .listRowBackground(selectedNote?.id == note.id ? AppTheme.selectedRowBackground : AppTheme.background)
            .contextMenu {
                Button(role: .destructive) {
                    externallyDeletingNoteID = note.id
                    if note.id == selectedNote?.id {
                        selectedNote = nil
                        selectedNoteStore = nil
                        selectedIsNew = false
                    }
                    currentStore.deleteNote(note)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func goBack() {
        folderStack.removeLast()
    }

    private func createNote() {
        let note = currentStore.createNote()
        selectedNote = note
        selectedNoteStore = currentStore
        selectedIsNew = true
        onNoteActivated?()
    }

}

/// A folder row with a disclosure triangle (expand in-place) and a clickable label (navigate into).
private struct SidebarFolderRow: View {
    let folder: NotoFolder
    let rootStore: MarkdownNoteStore
    var fileWatcher: VaultFileWatcher?
    @Binding var selectedNote: MarkdownNote?
    @Binding var selectedNoteStore: MarkdownNoteStore?
    @Binding var selectedIsNew: Bool
    @Binding var externallyDeletingNoteID: UUID?
    var onNoteActivated: (() -> Void)? = nil
    var onNavigate: (NotoFolder) -> Void
    var onDelete: () -> Void

    @State private var isExpanded = false
    @State private var childStore: MarkdownNoteStore?

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if let childStore {
                ForEach(childStore.items) { (childItem: DirectoryItem) in
                    switch childItem {
                    case .folder(let subfolder):
                        SidebarFolderRow(
                            folder: subfolder,
                            rootStore: rootStore,
                            fileWatcher: fileWatcher,
                            selectedNote: $selectedNote,
                            selectedNoteStore: $selectedNoteStore,
                            selectedIsNew: $selectedIsNew,
                            externallyDeletingNoteID: $externallyDeletingNoteID,
                            onNoteActivated: onNoteActivated,
                            onNavigate: onNavigate,
                            onDelete: {
                                childStore.deleteFolder(subfolder)
                            }
                        )
                    case .note(let note):
                        Button {
                            selectedNote = note
                            selectedNoteStore = childStore
                            selectedIsNew = false
                            onNoteActivated?()
                        } label: {
                            Label(note.title, systemImage: "doc.text")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("note_\(note.title)")
                        .foregroundStyle(AppTheme.primaryText)
                        .listRowBackground(selectedNote?.id == note.id ? AppTheme.selectedRowBackground : AppTheme.background)
                        .contextMenu {
                            Button(role: .destructive) {
                                externallyDeletingNoteID = note.id
                                if note.id == selectedNote?.id {
                                    selectedNote = nil
                                    selectedNoteStore = nil
                                    selectedIsNew = false
                                }
                                childStore.deleteNote(note)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        } label: {
            Button(action: { onNavigate(folder) }) {
                Label(folder.name, systemImage: "folder.fill")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("folder_\(folder.name)")
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded, childStore == nil {
                childStore = MarkdownNoteStore(
                    directoryURL: folder.folderURL,
                    vaultRootURL: rootStore.vaultRootURL,
                    directoryLoader: rootStore.directoryLoader
                )
            }
        }
    }
}

// MARK: - iOS Folder Content View

#if os(iOS)
/// Reusable view that shows the contents of a directory (folders + notes).
struct FolderContentView: View {
    var store: MarkdownNoteStore
    let title: String
    var isRoot: Bool = false
    var fileWatcher: VaultFileWatcher?
    @Binding var path: NavigationPath
    var onOpenNote: ((MarkdownNote, MarkdownNoteStore, Bool) -> Void)?
    var onTodayTap: (() -> Void)?
    var onCreateRootNote: (() -> Void)?
    var onSettingsTap: (() -> Void)?

    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""

    var body: some View {
        List {
            ForEach(store.items) { item in
                switch item {
                case .folder(let folder):
                    Button {
                        path.append(NoteRoute.folder(
                            folderURL: folder.folderURL,
                            name: folder.name,
                            vaultRootURL: store.vaultRootURL
                        ))
                    } label: {
                        FolderRow(folder: folder)
                    }
                    .accessibilityIdentifier("folder_\(folder.name)")
                case .note(let note):
                    Button {
                        openNote(note, isNew: false)
                    } label: {
                        MarkdownNoteRow(note: note)
                    }
                    .accessibilityIdentifier("note_\(note.title)")
                }
            }
            .onDelete(perform: deleteItems)
            .listRowBackground(AppTheme.background)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .foregroundStyle(AppTheme.primaryText)
        .tint(AppTheme.primaryText)
        .accessibilityIdentifier("note_list")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isRoot, let onSettingsTap {
                    Button(action: onSettingsTap) {
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
                    _ = store.createFolder(name: name)
                }
                newFolderName = ""
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
        .onAppear {
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
                    description: Text("Tap + to create a note or folder")
                )
                .allowsHitTesting(false)
            }
        }
    }

    private func createNote() {
        let note = store.createNote()
        openNote(note, isNew: true)
    }

    private func openNote(_ note: MarkdownNote, isNew: Bool) {
        if let onOpenNote {
            onOpenNote(note, store, isNew)
        } else {
            path.append(NoteRoute.note(
                note,
                directoryURL: store.directoryURL,
                vaultRootURL: store.vaultRootURL,
                isNew: isNew
            ))
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            store.deleteItem(store.items[index])
        }
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

struct NoteSearchSheet: View {
    var rootStore: MarkdownNoteStore
    var onClose: (() -> Void)? = nil
    var onSelect: (NoteSearchResult) -> Void

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
        .frame(width: 620, height: 560)
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
        Picker("Search Scope", selection: $scope) {
            Text("Title + Content").tag(SearchScope.titleAndContent)
            Text("Title").tag(SearchScope.title)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("note_search_scope_picker")
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            searchScopePicker
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            #endif

            ScrollViewReader { proxy in
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
                        #if os(macOS)
                        .contentShape(Rectangle())
                        .onHover { isHovering in
                            if isHovering {
                                selectedResultIndex = index
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        .listRowBackground(index == selectedResultIndex ? AppTheme.selectedRowBackground : AppTheme.background)
                        #else
                        .listRowBackground(AppTheme.background)
                        #endif
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(AppTheme.background)
                .foregroundStyle(AppTheme.primaryText)
                .tint(AppTheme.primaryText)
                .accessibilityIdentifier("note_search_results_list")
                #if os(macOS)
                .onChange(of: selectedResultIndex) { _, selectedResultIndex in
                    guard let selectedResultIndex, results.indices.contains(selectedResultIndex) else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(results[selectedResultIndex].id, anchor: .center)
                    }
                }
                #endif
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
            let result = try await SearchIndexRefreshCoordinator.shared.refresh(vaultURL: rootURL)
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
        self.frame(minWidth: 620, minHeight: 560)
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
    }
}
