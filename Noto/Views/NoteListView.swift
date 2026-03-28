import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NoteListView")

/// Root entry point — wraps FolderContentView in a NavigationStack.
struct NoteListView: View {
    @ObservedObject var store: MarkdownNoteStore
    var locationManager: VaultLocationManager?
    var fileWatcher: VaultFileWatcher?
    @State private var showTodayNote = false
    @State private var todayNoteData: (store: MarkdownNoteStore, note: MarkdownNote)?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            FolderContentView(
                store: store,
                title: "Notes",
                isRoot: true,
                fileWatcher: fileWatcher,
                onTodayTap: openTodayNote,
                onSettingsTap: locationManager != nil ? { showSettings = true } : nil
            )
            .navigationDestination(isPresented: $showTodayNote) {
                if let data = todayNoteData {
                    NoteEditorScreen(store: data.store, note: data.note, fileWatcher: fileWatcher)
                }
            }
            .navigationDestination(isPresented: $showSettings) {
                if let locationManager {
                    SettingsView(locationManager: locationManager)
                }
            }
        }
    }

    private func openTodayNote() {
        todayNoteData = store.todayNote()
        showTodayNote = true
    }
}

/// Reusable view that shows the contents of a directory (folders + notes).
struct FolderContentView: View {
    @ObservedObject var store: MarkdownNoteStore
    let title: String
    var isRoot: Bool = false
    var fileWatcher: VaultFileWatcher?
    var onTodayTap: (() -> Void)?
    var onSettingsTap: (() -> Void)?

    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var navigateToNewNote: MarkdownNote?
    @State private var shouldNavigateToNew = false

    var body: some View {
        List {
            ForEach(store.items) { item in
                switch item {
                case .folder(let folder):
                    NavigationLink {
                        FolderContentView(
                            store: MarkdownNoteStore(
                                directoryURL: folder.folderURL,
                                vaultRootURL: store.vaultRootURL
                            ),
                            title: folder.name,
                            fileWatcher: fileWatcher
                        )
                    } label: {
                        FolderRow(folder: folder)
                    }
                case .note(let note):
                    NavigationLink {
                        NoteEditorScreen(store: store, note: note, fileWatcher: fileWatcher)
                    } label: {
                        MarkdownNoteRow(note: note)
                    }
                }
            }
            .onDelete(perform: deleteItems)
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $shouldNavigateToNew) {
            if let note = navigateToNewNote {
                NoteEditorScreen(store: store, note: note, isNew: true, fileWatcher: fileWatcher)
            }
        }
        .toolbar {
            if isRoot {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { onTodayTap?() }) {
                        Label("Today", systemImage: "calendar")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    if isRoot, let onSettingsTap {
                        Button(action: onSettingsTap) {
                            Image(systemName: "gearshape")
                        }
                    }
                    Menu {
                        Button(action: createNote) {
                            Label("New Note", systemImage: "doc.badge.plus")
                        }
                        Button(action: { showNewFolderAlert = true }) {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Add")
                    }
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
        navigateToNewNote = note
        shouldNavigateToNew = true
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
