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
    #endif

    #if os(macOS)
    @State private var selectedNote: MarkdownNote?
    @State private var selectedNoteStore: MarkdownNoteStore?
    @State private var selectedNoteIsNew = false
    @State private var externallyDeletingNoteID: UUID?
    @State private var showSettings = false
    @State private var hasRestoredSelection = false

    private static let lastOpenedNoteKey = "lastOpenedNoteURL"
    #endif

    var body: some View {
        #if os(iOS)
        NavigationStack(path: $path) {
            FolderContentView(
                store: store,
                title: "Notes",
                isRoot: true,
                fileWatcher: fileWatcher,
                path: $path,
                onTodayTap: { path.append(NoteRoute.todayNote) },
                onSettingsTap: locationManager != nil ? { path.append(NoteRoute.settings) } : nil
            )
            .navigationDestination(for: NoteRoute.self) { route in
                switch route {
                case .note(let note, let directoryURL, let vaultRootURL, let isNew):
                    NoteEditorScreen(
                        store: MarkdownNoteStore(directoryURL: directoryURL, vaultRootURL: vaultRootURL),
                        note: note,
                        isNew: isNew,
                        fileWatcher: fileWatcher
                    )
                case .folder(let folderURL, let name, let vaultRootURL):
                    FolderContentView(
                        store: MarkdownNoteStore(directoryURL: folderURL, vaultRootURL: vaultRootURL),
                        title: name,
                        fileWatcher: fileWatcher,
                        path: $path
                    )
                case .settings:
                    if let locationManager {
                        SettingsView(locationManager: locationManager)
                    }
                case .todayNote:
                    TodayNoteDestination(store: store, fileWatcher: fileWatcher)
                }
            }
        }
        #elseif os(macOS)
        NavigationSplitView {
            SidebarView(
                rootStore: store,
                fileWatcher: fileWatcher,
                selectedNote: $selectedNote,
                selectedNoteStore: $selectedNoteStore,
                selectedIsNew: $selectedNoteIsNew,
                externallyDeletingNoteID: $externallyDeletingNoteID
            )
        } detail: {
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
                    externallyDeletingNoteID: $externallyDeletingNoteID
                )
                .id(selectedNote.id)
            } else {
                Text("Select a note")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: openTodayNote) {
                    Label("Today", systemImage: "calendar")
                }
                .accessibilityIdentifier("today_button")
            }
            if locationManager != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showSettings = true }) {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("settings_button")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            if let locationManager {
                SettingsView(locationManager: locationManager)
                    .frame(minWidth: 400, minHeight: 200)
            }
        }
        .onChange(of: selectedNote?.fileURL) { _, newURL in
            // Persist the selected note's file path
            if let path = newURL?.path {
                UserDefaults.standard.set(path, forKey: Self.lastOpenedNoteKey)
            }
        }
        .onAppear {
            guard !hasRestoredSelection else { return }
            hasRestoredSelection = true
            restoreOrOpenToday()
        }
        #endif
    }

    #if os(macOS)
    private func openTodayNote() {
        let (todayStore, todayNote) = store.todayNote()
        selectedNoteStore = todayStore
        selectedNote = todayNote
        selectedNoteIsNew = false
    }

    private func restoreOrOpenToday() {
        // Try to restore the last opened note
        if let savedPath = UserDefaults.standard.string(forKey: Self.lastOpenedNoteKey) {
            let fileURL = URL(fileURLWithPath: savedPath)
            if FileManager.default.fileExists(atPath: savedPath) {
                let dirURL = fileURL.deletingLastPathComponent()
                let noteStore = MarkdownNoteStore(directoryURL: dirURL, vaultRootURL: store.vaultRootURL)
                if let note = noteStore.notes.first(where: { $0.fileURL.path == savedPath }) {
                    selectedNoteStore = noteStore
                    selectedNote = note
                    selectedNoteIsNew = false
                    return
                }
            }
        }
        // Default to today's note
        openTodayNote()
    }
    #endif
}

/// Resolves and displays today's note (iOS only — macOS opens inline).
private struct TodayNoteDestination: View {
    var store: MarkdownNoteStore
    var fileWatcher: VaultFileWatcher?
    @State private var data: (store: MarkdownNoteStore, note: MarkdownNote)?

    var body: some View {
        Group {
            if let data {
                NoteEditorScreen(store: data.store, note: data.note, fileWatcher: fileWatcher)
            } else {
                ProgressView()
            }
        }
        .task {
            data = store.todayNote()
        }
    }
}

// MARK: - macOS Sidebar

#if os(macOS)
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
            }
            .contextMenu {
                Button(action: createNote) {
                    Label("New Note", systemImage: "doc.badge.plus")
                }
                Button(action: { showNewFolderAlert = true }) {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
        }
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
                onNavigate: {
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
            } label: {
                Label(note.title, systemImage: "doc.text")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("note_\(note.title)")
            .listRowBackground(selectedNote?.id == note.id ? Color.accentColor.opacity(0.2) : nil)
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
    var onNavigate: () -> Void
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
                            onNavigate: {
                                let subStore = MarkdownNoteStore(
                                    directoryURL: subfolder.folderURL,
                                    vaultRootURL: rootStore.vaultRootURL
                                )
                                // Navigate: push parent folder first, then this subfolder
                                onNavigate()
                            },
                            onDelete: {
                                childStore.deleteFolder(subfolder)
                            }
                        )
                    case .note(let note):
                        Button {
                            selectedNote = note
                            selectedNoteStore = childStore
                            selectedIsNew = false
                        } label: {
                            Label(note.title, systemImage: "doc.text")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("note_\(note.title)")
                        .listRowBackground(selectedNote?.id == note.id ? Color.accentColor.opacity(0.2) : nil)
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
            Button(action: onNavigate) {
                Label(folder.name, systemImage: "folder.fill")
            }
            .buttonStyle(.plain)
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
#endif

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
        }
        .listStyle(.plain)
        .accessibilityIdentifier("note_list")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(!isRoot)
        .toolbar {
            if isRoot {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { onTodayTap?() }) {
                        Label("Today", systemImage: "calendar")
                    }
                    .accessibilityIdentifier("today_button")
                }
            } else {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityIdentifier("back_button")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    if isRoot, let onSettingsTap {
                        Button(action: onSettingsTap) {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityIdentifier("settings_button")
                    }
                    Button(action: createNote) {
                        Image(systemName: "doc.badge.plus")
                            .accessibilityLabel("New Note")
                    }
                    .accessibilityIdentifier("new_note_button")
                    Menu {
                        Button(action: { showNewFolderAlert = true }) {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                        .accessibilityIdentifier("new_folder_button")
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("More")
                    }
                    .accessibilityIdentifier("add_menu")
                }
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

// MARK: - Row Views

struct FolderRow: View {
    let folder: NotoFolder

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(folder.modifiedDate, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(note.modifiedDate, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
