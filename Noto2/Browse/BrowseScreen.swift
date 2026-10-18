import NotoVault
import SwiftUI
import os.log

private let browseLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto2", category: "BrowseScreen")

/// Navigation targets shared by Browse and Search (a search hit opens the same
/// note screen the explorer does).
enum BrowseDestination: Hashable {
    case folder(NotoFolder)
    case note(MarkdownNote, directoryURL: URL, isNew: Bool)

    /// The editor target for a note at `fileURL`, or `nil` when the URL is not
    /// a note inside this vault. Shared by every entry point that opens a note
    /// from a bare file URL — a search hit and a freshly filed capture — so the
    /// two cannot drift. The note's own directory is carried through: an
    /// `inbox/` note must be edited through the `inbox/` store, not the root.
    @MainActor
    static func note(at fileURL: URL, in vaultController: VaultController) -> BrowseDestination? {
        guard let relative = vaultController.vaultRelativePath(for: fileURL),
              let located = vaultController.note(atVaultRelativePath: relative) else { return nil }
        return .note(located.note, directoryURL: located.store.directoryURL, isNew: false)
    }
}

/// Testable mutation seam for the actions attached to one visible directory.
/// Holding the exact store rendered by `FolderListView` guarantees that newly
/// created items land in that directory rather than falling back to the vault root.
@MainActor
struct ExplorerDirectoryActions {
    let vaultController: VaultController
    let store: MarkdownNoteStore

    static func normalizedFolderName(_ name: String) -> String? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    func createNoteDestination() -> BrowseDestination {
        let created = vaultController.createNote(in: store)
        return .note(created.note, directoryURL: created.store.directoryURL, isNew: true)
    }

    @discardableResult
    func createFolder(named name: String) -> NotoFolder? {
        guard let normalizedName = Self.normalizedFolderName(name) else { return nil }
        return vaultController.createFolder(named: normalizedName, in: store)
    }
}

/// Library owns its navigation stack; Search and Capture reuse the destination contract.
struct BrowseScreen: View {
    let vaultController: VaultController
    var locationManager: VaultLocationManager
    @Binding var pendingNoteURL: URL?
    @State private var path: [BrowseDestination] = []
    @State private var showSettings = false

    init(vaultController: VaultController, locationManager: VaultLocationManager, pendingNoteURL: Binding<URL?> = .constant(nil)) {
        self.vaultController = vaultController
        self.locationManager = locationManager
        _pendingNoteURL = pendingNoteURL
    }

    var body: some View {
        NavigationStack(path: $path) {
            LibraryHome(vaultController: vaultController, onOpen: { path.append($0) }, onOpenSettings: { showSettings = true })
                .navigationDestination(isPresented: $showSettings) {
                    LibrarySettingsScreen(locationManager: locationManager)
                }
                .navigationDestination(for: BrowseDestination.self) { destination in
                    BrowseDestinationView(destination: destination, vaultController: vaultController, onOpen: { path.append($0) })
                        .id(destination)
                }
        }
        .onAppear { consumePendingNote() }
        .onChange(of: pendingNoteURL) { _, _ in consumePendingNote() }
    }

    private func consumePendingNote() {
        guard let url = pendingNoteURL else { return }
        pendingNoteURL = nil
        guard let destination = BrowseDestination.note(at: url, in: vaultController) else {
            browseLogger.error("pending note did not resolve: \(url.lastPathComponent, privacy: .public)")
            return
        }
        path = [destination]
    }
}

struct BrowseDestinationView: View {
    let destination: BrowseDestination
    let vaultController: VaultController
    var onOpen: (BrowseDestination) -> Void
    var initialFindQuery: String? = nil

    var body: some View {
        switch destination {
        case .folder(let folder):
            FolderListView(store: vaultController.store(for: folder), title: folder.name, vaultController: vaultController, onOpen: onOpen, showsBackButton: true)
        case .note(let note, let directoryURL, let isNew):
            NoteScreen(store: vaultController.store(for: directoryURL), note: note, isNew: isNew, vaultController: vaultController, onNoteDeleted: {
                vaultController.refreshRootForForegroundActivation()
            }, initialFindQuery: initialFindQuery)
            .toolbar(.visible, for: .navigationBar)
        }
    }
}

struct LibraryHome: View {
    let vaultController: VaultController
    let onOpen: (BrowseDestination) -> Void
    let onOpenSettings: () -> Void
    @State private var showNewFolder = false
    @State private var folderName = ""
    @State private var revision = 0
    @Environment(VaultFileWatcher.self) private var fileWatcher: VaultFileWatcher?
    /// Cache-first: the last saved snapshot shows at once; scans refresh it silently.
    @Environment(LibraryModel.self) private var library: LibraryModel?

    private var actions: ExplorerDirectoryActions { .init(vaultController: vaultController, store: vaultController.rootStore) }

    var body: some View {
        List {
            if let snapshot = library?.snapshot {
                if !snapshot.pinned.isEmpty {
                    Section {
                        ForEach(snapshot.pinned) { entry in noteRow(entry, pinned: true) }
                    } header: { LibrarySectionHeading("Pinned") }
                    .listRowBackground(NotoTheme.card)
                }
                if !snapshot.recent().isEmpty {
                    Section {
                        ForEach(snapshot.recent()) { entry in noteRow(entry, pinned: false) }
                    } header: { LibrarySectionHeading("Recent") }
                    .listRowBackground(NotoTheme.card)
                }
                if !snapshot.folders.isEmpty {
                    Section {
                        ForEach(snapshot.folders) { folder in
                            Button { onOpen(.folder(NotoFolder(summary: folder))) } label: {
                                LibraryFolderRow(name: folder.name, count: folder.itemCount + folder.folderCount)
                            }
                            .accessibilityIdentifier("libraryFolder_\(folder.name)")
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    } header: { LibrarySectionHeading("Folders") }
                    .listRowBackground(NotoTheme.card)
                }
                if snapshot.notes.isEmpty && snapshot.folders.isEmpty {
                    ContentUnavailableView("Your Library is empty", systemImage: "books.vertical", description: Text("Create a note or file a capture to get started."))
                        .accessibilityIdentifier("libraryEmptyState")
                        .listRowBackground(Color.clear)
                }
            } else if let errorMessage = library?.errorMessage {
                Text(errorMessage).foregroundStyle(NotoTheme.muted).accessibilityIdentifier("libraryLoadError")
            } else if library?.isFirstLoad ?? true {
                // Only before the first scan on this device; afterwards the saved
                // snapshot shows while scans run silently.
                ProgressView().accessibilityIdentifier("libraryLoading")
            }
        }
        .modifier(LibraryListStyle())
        .navigationTitle("Library")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("New note", systemImage: "square.and.pencil") { onOpen(actions.createNoteDestination()) }
                        .accessibilityIdentifier("browse_new_note_action")
                    Button("New folder", systemImage: "folder.badge.plus") { showNewFolder = true }
                        .accessibilityIdentifier("browse_new_folder_action")
                    Button("Settings", systemImage: "gearshape") { onOpenSettings() }
                        .accessibilityIdentifier("browseSettingsButton")
                } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("Library actions")
                .accessibilityIdentifier("browse_more_actions_menu")
            }
        }
        .sheet(isPresented: $showNewFolder) {
            LibraryNewFolderSheet(name: $folderName) {
                _ = actions.createFolder(named: folderName)
                folderName = ""
                revision += 1
            }
        }
        .task(id: revision) { await library?.refresh() }
        .onChange(of: fileWatcher?.changeCount) { _, _ in revision += 1 }
        .onReceive(NotificationCenter.default.publisher(for: NoteSyncCenter.notificationName)) { _ in revision += 1 }
        .refreshable { await library?.refresh() }
        .accessibilityIdentifier("libraryHome")
    }

    private func noteRow(_ entry: LibraryNote, pinned: Bool) -> some View {
        Button {
            onOpen(.note(MarkdownNote(record: entry.note), directoryURL: entry.note.fileURL.deletingLastPathComponent(), isNew: false))
        } label: {
            LibraryNoteRow(entry: entry, pinned: pinned)
        }
        .accessibilityIdentifier("libraryNote_\(entry.note.fileURL.lastPathComponent)")
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
}

struct FolderListView: View {
    let store: MarkdownNoteStore
    let title: String
    let vaultController: VaultController
    var onOpen: (BrowseDestination) -> Void
    var showsBackButton = false
    var onOpenSettings: (() -> Void)?
    @State private var sort: LibraryNoteSort = .recent
    @State private var revision = 0
    @State private var showNewFolder = false
    @State private var folderName = ""
    @Environment(VaultFileWatcher.self) private var fileWatcher: VaultFileWatcher?
    @Environment(LibraryModel.self) private var library: LibraryModel?

    /// This folder's notes from the shared Library snapshot, so a folder opens
    /// without its own vault scan.
    private var notes: [LibraryNote] { library?.snapshot?.notes(inDirectory: store.directoryURL) ?? [] }

    private var folders: [NotoFolder] {
        store.items.compactMap { item in
            guard case .folder(let folder) = item, LibraryCatalog.isVisible(folder.folderURL, in: vaultController.vaultURL) else { return nil }
            return folder
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var actions: ExplorerDirectoryActions { .init(vaultController: vaultController, store: store) }

    var body: some View {
        List {
            if !folders.isEmpty {
                Section {
                    ForEach(folders) { folder in
                        Button { onOpen(.folder(folder)) } label: {
                            LibraryFolderRow(name: folder.name, count: folder.itemCount + folder.folderCount)
                        }
                        .accessibilityIdentifier("libraryFolder_\(folder.name)")
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }.listRowBackground(NotoTheme.card)
            }
            ForEach(LibraryCatalog.groups(notes, sort: sort)) { group in
                Section {
                    ForEach(group.notes) { entry in
                        Button { onOpen(.note(MarkdownNote(record: entry.note), directoryURL: store.directoryURL, isNew: false)) } label: {
                            LibraryFolderNoteRow(entry: entry)
                        }
                        .accessibilityIdentifier("libraryNote_\(entry.note.fileURL.lastPathComponent)")
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                } header: { LibrarySectionHeading(group.title) }
                .listRowBackground(NotoTheme.card)
            }
            if notes.isEmpty && folders.isEmpty {
                if library?.snapshot == nil {
                    ProgressView().accessibilityIdentifier("libraryLoading")
                        .listRowBackground(Color.clear)
                } else {
                    Text("Nothing here yet.").foregroundStyle(NotoTheme.muted).accessibilityIdentifier("browseEmptyState")
                        .listRowBackground(Color.clear)
                }
            }
        }
        .modifier(LibraryListStyle())
        .navigationTitle(title)
        // Counts sit under the folder name and sorting lives in the title bar,
        // so the list starts with content (Eugene, 2026-10-18).
        .navigationSubtitle(Text(LibraryCatalog.directorySummary(folderCount: folders.count, noteCount: notes.count)))
        .toolbarTitleDisplayMode(.inlineLarge)
        .navigationBarBackButtonHidden(!showsBackButton)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort notes", selection: $sort) {
                        ForEach(LibraryNoteSort.allCases, id: \.self) { option in Text(option.rawValue).tag(option) }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
                .accessibilityLabel("Sort notes")
                .accessibilityIdentifier("libraryFolderSort")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { onOpen(actions.createNoteDestination()) } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New note").accessibilityIdentifier("browse_new_note_action")
                    .contextMenu {
                        Button("New folder", systemImage: "folder.badge.plus") { showNewFolder = true }
                    }
            }
        }
        .task(id: revision) { await load() }
        .onChange(of: fileWatcher?.changeCount) { _, _ in revision += 1 }
        .onReceive(NotificationCenter.default.publisher(for: NoteSyncCenter.notificationName)) { _ in revision += 1 }
        .refreshable { await load() }
        .sheet(isPresented: $showNewFolder) {
            LibraryNewFolderSheet(name: $folderName) {
                _ = actions.createFolder(named: folderName)
                folderName = ""
                revision += 1
            }
        }
    }

    private func load() async {
        store.loadItemsInBackground()
        await library?.refresh()
    }
}

struct LibrarySectionHeading: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title.uppercased()).font(.system(size: 12, weight: .regular))
            .kerning(0.5).foregroundStyle(NotoTheme.muted)
    }
}

struct LibraryListStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .contentMargins(.top, 0, for: .scrollContent)
            .listSectionSpacing(12)
            .environment(\.defaultMinListRowHeight, 52)
            .listRowSeparatorTint(NotoTheme.hairline)
            .background(NotoTheme.background.ignoresSafeArea())
            .tint(NotoTheme.accent)
    }
}

struct LibraryFolderRow: View {
    let name: String
    let count: Int
    var body: some View {
        HStack(spacing: 12) {
            LibraryRowIcon(symbol: name == "Daily Notes" ? "calendar" : "folder", circular: true)
            Text(name).font(.system(size: 16, weight: .semibold)).foregroundStyle(NotoTheme.ink)
            Spacer(minLength: 8)
            Text(count.formatted()).font(.system(size: 14)).foregroundStyle(NotoTheme.muted)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(NotoTheme.faint)
        }
        .contentShape(Rectangle())
    }
}

struct LibraryRowIcon: View {
    let symbol: String
    var pinned = false
    var circular = false
    var body: some View {
        Image(systemName: symbol).font(.system(size: 13, weight: .medium))
            .foregroundStyle(pinned ? NotoTheme.accentText : NotoTheme.muted)
            .frame(width: circular ? 30 : 32, height: circular ? 30 : 32)
            .background {
                if circular {
                    Circle().fill(pinned ? NotoTheme.accentSoft : NotoTheme.secondaryFill)
                } else {
                    RoundedRectangle(cornerRadius: 11).fill(pinned ? NotoTheme.accentSoft : NotoTheme.secondaryFill)
                }
            }
    }
}

struct LibraryNoteRow: View {
    let entry: LibraryNote
    var pinned = false
    var body: some View {
        HStack(spacing: 12) {
            LibraryRowIcon(symbol: pinned ? "pin" : (entry.folderPath == "Daily Notes" ? "calendar" : "doc"), pinned: pinned, circular: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.note.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(NotoTheme.ink).lineLimit(1)
                Text("\(entry.folderPath.isEmpty ? "Library" : entry.folderPath.replacingOccurrences(of: "/", with: " › ")) · \(NotoRelativeDate.compactString(from: entry.note.modifiedDate))")
                    .font(.system(size: 13)).foregroundStyle(NotoTheme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

struct LibraryFolderNoteRow: View {
    let entry: LibraryNote
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(entry.note.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(NotoTheme.ink).lineLimit(1)
                Spacer(minLength: 0)
                Text(entry.note.modifiedDate, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 12)).foregroundStyle(NotoTheme.muted)
            }
            if !entry.preview.isEmpty {
                Text(entry.preview).font(.system(size: 14)).foregroundStyle(NotoTheme.muted).lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct LibraryNewFolderSheet: View {
    @Binding var name: String
    let onCreate: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            Form {
                TextField("Folder name", text: $name).focused($focused)
                    .accessibilityIdentifier("browse_new_folder_name_field")
                    .onSubmit(create)
            }
            .navigationTitle("New folder").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                        .accessibilityLabel("Cancel").accessibilityIdentifier("browse_cancel_folder_button")
                }
            }
            .modifier(LibrarySheetAction(title: "Create folder", identifier: "browse_create_folder_button", disabled: ExplorerDirectoryActions.normalizedFolderName(name) == nil, action: create))
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
    }
    private func create() {
        guard ExplorerDirectoryActions.normalizedFolderName(name) != nil else { return }
        onCreate()
        dismiss()
    }
}

struct LibrarySheetAction: ViewModifier {
    let title: String
    let identifier: String
    var disabled = false
    let action: () -> Void
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                Button(action: action) { Text(title).frame(maxWidth: .infinity).padding(.vertical, 6) }
                    .buttonStyle(.glassProminent).tint(NotoTheme.accent).controlSize(.large)
                    .disabled(disabled).accessibilityIdentifier(identifier).padding(16)
            }
        } else {
            content.safeAreaInset(edge: .bottom) {
                Button(action: action) { Text(title).frame(maxWidth: .infinity).padding(.vertical, 6) }
                    .buttonStyle(.borderedProminent).tint(NotoTheme.accent).controlSize(.large)
                    .disabled(disabled).accessibilityIdentifier(identifier).padding(16)
            }
        }
    }
}
