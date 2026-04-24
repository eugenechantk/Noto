import SwiftUI
import os.log

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
        note.fileURL.standardizedFileURL == other.note.fileURL.standardizedFileURL &&
            directoryURL.standardizedFileURL == other.directoryURL.standardizedFileURL &&
            vaultRootURL.standardizedFileURL == other.vaultRootURL.standardizedFileURL
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var selectedNote: MarkdownNote?
    @State private var selectedNoteStore: MarkdownNoteStore?
    @State private var selectedNoteIsNew = false
    @State private var externallyDeletingNoteID: UUID?
    @State private var showSettings = false
    @State private var hasRestoredSelection = false

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
                            store: MarkdownNoteStore(directoryURL: directoryURL, vaultRootURL: vaultRootURL, autoload: false),
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
                            store: MarkdownNoteStore(directoryURL: folderURL, vaultRootURL: vaultRootURL, autoload: false),
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
                onSearch: {},
                onCreateRootNote: createRootNoteAndPush
            )
            .onReceive(NotificationCenter.default.publisher(for: NotoAppCommands.openToday)) { _ in
                path.append(NoteRoute.todayNote)
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
        .sheet(isPresented: $showSettings) {
            if let locationManager {
                SettingsView(locationManager: locationManager, readwiseSyncController: readwiseSyncController)
                    .frame(minWidth: 400, minHeight: 200)
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
            let noteStore = MarkdownNoteStore(directoryURL: directoryURL, vaultRootURL: store.vaultRootURL)

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
                        vaultRootURL: rootStore.vaultRootURL
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
                    vaultRootURL: rootStore.vaultRootURL
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
private struct NotoAppBottomToolbarModifier: ViewModifier {
    var onOpenTodayNote: (() -> Void)?
    var onSearch: (() -> Void)?
    var onCreateRootNote: (() -> Void)?

    func body(content: Content) -> some View {
        if onOpenTodayNote == nil && onSearch == nil && onCreateRootNote == nil {
            content
        } else {
            content.overlay(alignment: .bottom) {
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
