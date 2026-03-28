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

/// Root entry point — wraps FolderContentView in a NavigationStack.
struct NoteListView: View {
    var store: MarkdownNoteStore
    var locationManager: VaultLocationManager?
    var fileWatcher: VaultFileWatcher?
    @State private var path = NavigationPath()

    var body: some View {
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
    }
}

/// Resolves and displays today's note. Separated to avoid computing todayNote() at route creation time.
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

/// Reusable view that shows the contents of a directory (folders + notes).
struct FolderContentView: View {
    var store: MarkdownNoteStore
    let title: String
    var isRoot: Bool = false
    var fileWatcher: VaultFileWatcher?
    @Binding var path: NavigationPath
    var onTodayTap: (() -> Void)?
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
        .toolbar {
            if isRoot {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { onTodayTap?() }) {
                        Label("Today", systemImage: "calendar")
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("today_button")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    if isRoot, let onSettingsTap {
                        Button(action: onSettingsTap) {
                            Image(systemName: "gearshape")
                        }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("settings_button")
                    }
                    Menu {
                        Button(action: createNote) {
                            Label("New Note", systemImage: "doc.badge.plus")
                        }
                        .accessibilityIdentifier("new_note_button")
                        Button(action: { showNewFolderAlert = true }) {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                        .accessibilityIdentifier("new_folder_button")
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Add")
                    }
                    .buttonStyle(.glass)
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
