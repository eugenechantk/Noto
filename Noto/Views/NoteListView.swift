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

// MARK: - Root View

/// Root entry point — NavigationStack on iOS, NavigationSplitView on macOS.
struct NoteListView: View {
    var store: MarkdownNoteStore
    var locationManager: VaultLocationManager?
    var fileWatcher: VaultFileWatcher?

    #if os(iOS)
    @State private var path = NavigationPath()
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
                externallyDeletingNoteID: $externallyDeletingNoteID
            )
            .sheet(isPresented: $showSettings) {
                if let locationManager {
                    NavigationStack {
                        SettingsView(locationManager: locationManager)
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
                    onTodayTap: { path.append(NoteRoute.todayNote) },
                    onCreateRootNote: createRootNoteAndPush,
                    onSettingsTap: locationManager != nil ? { path.append(NoteRoute.settings) } : nil
                )
                .navigationDestination(for: NoteRoute.self) { route in
                    switch route {
                    case .note(let note, let directoryURL, let vaultRootURL, let isNew):
                        NoteEditorScreen(
                            store: MarkdownNoteStore(directoryURL: directoryURL, vaultRootURL: vaultRootURL),
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
                            }
                        )
                    case .folder(let folderURL, let name, let vaultRootURL):
                        FolderContentView(
                            store: MarkdownNoteStore(directoryURL: folderURL, vaultRootURL: vaultRootURL),
                            title: name,
                            fileWatcher: fileWatcher,
                            path: $path,
                            onTodayTap: { path.append(NoteRoute.todayNote) },
                            onCreateRootNote: createRootNoteAndPush
                        )
                    case .settings:
                        if let locationManager {
                            SettingsView(locationManager: locationManager)
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
                            }
                        )
                    }
                }
            }
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
            externallyDeletingNoteID: $externallyDeletingNoteID
        )
        .sheet(isPresented: $showSettings) {
            if let locationManager {
                SettingsView(locationManager: locationManager)
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
                externallyDeletingNoteID: $externallyDeletingNoteID,
                showsInlineBackButton: false
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
        path = NavigationPath()
        path.append(NoteRoute.note(
            note,
            directoryURL: store.vaultRootURL,
            vaultRootURL: store.vaultRootURL,
            isNew: true
        ))
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
                    onTapBreadcrumbLevel: onTapBreadcrumbLevel
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
            rootStore.loadItems()
        }
        #if os(iOS)
        .notoAppBottomToolbar(
            onOpenTodayNote: onTodayTap,
            onCreateRootNote: onCreateRootNote
        )
        #endif
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
    var onTodayTap: (() -> Void)?
    var onCreateRootNote: (() -> Void)?
    var onSettingsTap: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
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
                        path.append(NoteRoute.note(
                            note,
                            directoryURL: store.directoryURL,
                            vaultRootURL: store.vaultRootURL
                        ))
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
        .navigationBarBackButtonHidden(!isRoot)
        .toolbar {
            if !isRoot {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityIdentifier("back_button")
                }
            }
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
        .notoAppBottomToolbar(
            onOpenTodayNote: onTodayTap,
            onCreateRootNote: onCreateRootNote
        )
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
            store.loadItems()
        }
        .overlay {
            if store.items.isEmpty {
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
        path.append(NoteRoute.note(
            note,
            directoryURL: store.directoryURL,
            vaultRootURL: store.vaultRootURL,
            isNew: true
        ))
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
    var onCreateRootNote: (() -> Void)?

    func body(content: Content) -> some View {
        if onOpenTodayNote == nil && onCreateRootNote == nil {
            content
        } else {
            content.toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(action: { onOpenTodayNote?() }) {
                        Label("Today", systemImage: "calendar")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("today_button")
                    .accessibilityLabel("Today")

                    Button(action: {}) {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("search_button")
                    .accessibilityLabel("Search")

                    Button(action: { onCreateRootNote?() }) {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("new_root_note_button")
                    .accessibilityLabel("New Note")
                }
            }
        }
    }
}

extension View {
    func notoAppBottomToolbar(
        onOpenTodayNote: (() -> Void)?,
        onCreateRootNote: (() -> Void)?
    ) -> some View {
        modifier(NotoAppBottomToolbarModifier(
            onOpenTodayNote: onOpenTodayNote,
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
                Text(folder.modifiedDate, style: .relative)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(.vertical, 4)
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
