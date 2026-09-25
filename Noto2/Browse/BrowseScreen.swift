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

/// Browse tab: the vault's folders and notes, drill-down, tap to open —
/// styled to match Noto 1's file explorer (icon + title/subtitle rows, own
/// chevrons, plain list on `NotoTheme.background`).
/// The root also carries the app's settings button.
struct BrowseScreen: View {
    let vaultController: VaultController
    var locationManager: VaultLocationManager
    /// Set by another tab (a filed capture) to ask Browse to open that note.
    /// Cleared once consumed so the same note is not re-pushed on every appear.
    @Binding var pendingNoteURL: URL?
    @State private var path: [BrowseDestination] = []
    @State private var showSettings = false

    init(
        vaultController: VaultController,
        locationManager: VaultLocationManager,
        pendingNoteURL: Binding<URL?> = .constant(nil)
    ) {
        self.vaultController = vaultController
        self.locationManager = locationManager
        _pendingNoteURL = pendingNoteURL
    }

    var body: some View {
        NavigationStack(path: $path) {
            FolderListView(
                store: vaultController.rootStore,
                title: "Browse",
                vaultController: vaultController,
                onOpen: { path.append($0) },
                onOpenSettings: { showSettings = true }
            )
            .sheet(isPresented: $showSettings) {
                OpenRouterSettingsSheet(locationManager: locationManager)
            }
            .navigationDestination(for: BrowseDestination.self) { destination in
                BrowseDestinationView(
                    destination: destination,
                    vaultController: vaultController,
                    onOpen: { path.append($0) }
                )
                    // A pending note replaces the stack with `[note]`. When a
                    // note is already pushed, that keeps the same stack position,
                    // and without explicit identity SwiftUI reuses the existing
                    // editor (whose session was built from the old note). Keying
                    // by destination makes the new note get its own screen.
                    .id(destination)
            }
        }
        // Both hooks are needed: `onAppear` covers the first hand-off, when the
        // request is set in the same turn that creates this view, and `onChange`
        // covers every later one while Browse is already on screen.
        .onAppear { consumePendingNote() }
        .onChange(of: pendingNoteURL) { _, _ in consumePendingNote() }
    }

    /// Replaces the stack with just this note, so Back lands on the Browse root
    /// rather than wherever the user happened to be browsing before.
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

/// Resolves a destination to its screen. A folder gets a fresh store for its
/// directory; a note gets the editor.
struct BrowseDestinationView: View {
    let destination: BrowseDestination
    let vaultController: VaultController
    var onOpen: (BrowseDestination) -> Void

    var body: some View {
        switch destination {
        case .folder(let folder):
            FolderListView(
                store: vaultController.store(for: folder),
                title: folder.name,
                vaultController: vaultController,
                onOpen: onOpen,
                showsBackButton: true
            )
        case .note(let note, let directoryURL, let isNew):
            NoteScreen(
                store: vaultController.store(for: directoryURL),
                note: note,
                isNew: isNew,
                vaultController: vaultController,
                onNoteDeleted: refreshAfterEditorMutation
            )
            .toolbar(.visible, for: .navigationBar)
        }
    }

    private func refreshAfterEditorMutation() {
        vaultController.refreshRootForForegroundActivation()
    }
}

struct FolderListView: View {
    let store: MarkdownNoteStore
    let title: String
    let vaultController: VaultController
    var onOpen: (BrowseDestination) -> Void
    var showsBackButton = false
    var onOpenSettings: (() -> Void)?

    @State private var newFolderName = ""
    @State private var showNewFolderPrompt = false
    @Environment(\.dismiss) private var dismiss

    private var items: [DirectoryItem] { ExplorerSorting.sorted(store.items) }

    private var actions: ExplorerDirectoryActions {
        ExplorerDirectoryActions(vaultController: vaultController, store: store)
    }

    var body: some View {
        VStack(spacing: 0) {
            directoryTopBar
            Rectangle()
                .fill(NotoTheme.separator)
                .frame(height: 0.5)
            directoryList
        }
        .background(NotoTheme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showNewFolderPrompt, onDismiss: { newFolderName = "" }) {
            NewFolderSheet(name: $newFolderName) {
                _ = actions.createFolder(named: newFolderName)
                newFolderName = ""
            }
        }
        .onAppear {
            store.loadItemsInBackground()
        }
    }

    private var directoryList: some View {
        List {
            if items.isEmpty {
                if store.isLoadingItems {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading…").foregroundStyle(AppTheme.secondaryText)
                    }
                    .listRowBackground(NotoTheme.background)
                    .accessibilityIdentifier("browseLoading")
                } else {
                    Text("Nothing here yet.")
                        .foregroundStyle(AppTheme.secondaryText)
                        .listRowBackground(NotoTheme.background)
                        .accessibilityIdentifier("browseEmptyState")
                }
            }
            ForEach(items) { item in
                Button {
                    switch item {
                    case .folder(let folder): onOpen(.folder(folder))
                    case .note(let note): onOpen(.note(note, directoryURL: store.directoryURL, isNew: false))
                    }
                } label: {
                    switch item {
                    case .folder(let folder):
                        BrowseFolderRow(folder: folder)
                    case .note(let note):
                        BrowseNoteRow(note: note)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(NotoTheme.background)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.automatic)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(NotoTheme.background.ignoresSafeArea())
        .refreshable {
            store.loadItemsInBackground()
        }
    }

    private var directoryTopBar: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(NotoTheme.head)
                .lineLimit(1)
                .padding(.horizontal, 100)
                .accessibilityIdentifier("browse_directory_title")

            HStack(spacing: 0) {
                if showsBackButton {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("browse_back_button")
                }

                Spacer(minLength: 8)

                if let onOpenSettings {
                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .regular))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("browseSettingsButton")
                }

                Menu {
                    Button {
                        onOpen(actions.createNoteDestination())
                    } label: {
                        Label("New Note", systemImage: "doc.badge.plus")
                    }
                    .accessibilityIdentifier("browse_new_note_action")

                    Button {
                        newFolderName = ""
                        showNewFolderPrompt = true
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    .accessibilityIdentifier("browse_new_folder_action")
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18, weight: .regular))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More actions")
                .accessibilityIdentifier("browse_more_actions_menu")
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 8)
        .background(NotoTheme.background)
    }
}

private struct NewFolderSheet: View {
    @Binding var name: String
    let onCreate: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool

    private var canCreate: Bool {
        ExplorerDirectoryActions.normalizedFolderName(name) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Folder")
                .font(.headline)
                .foregroundStyle(NotoTheme.head)

            TextField("Folder name", text: $name)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($isNameFocused)
                .onSubmit(createIfPossible)
                .accessibilityIdentifier("browse_new_folder_name_field")

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("browse_cancel_folder_button")

                Spacer()

                Button("Create") {
                    createIfPossible()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate)
                .accessibilityIdentifier("browse_create_folder_button")
            }
        }
        .padding(24)
        .background(NotoTheme.background.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { isNameFocused = true }
    }

    private func createIfPossible() {
        guard canCreate else { return }
        onCreate()
        dismiss()
    }
}

/// Noto 1's `FolderRow`, verbatim styling: folder glyph, name + contents
/// summary, own faint chevron.
private struct BrowseFolderRow: View {
    let folder: NotoFolder

    private var contentsSummary: String {
        let total = folder.itemCount + folder.folderCount
        return total == 0 ? "Empty" : "\(total) \(total == 1 ? "item" : "items")"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(NotoTheme.muted)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.system(size: NotoTheme.FontSize.rowTitle, weight: .semibold))
                    .foregroundStyle(NotoTheme.head)
                    .lineLimit(1)
                Text(contentsSummary)
                    .font(.system(size: NotoTheme.FontSize.subtitle))
                    .foregroundStyle(NotoTheme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotoTheme.faint)
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("browseFolderRow")
    }
}

/// Noto 1's `MarkdownNoteRow`, verbatim styling: doc glyph, title + "Edited …".
private struct BrowseNoteRow: View {
    let note: MarkdownNote

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(NotoTheme.muted)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(ExplorerSorting.displayTitle(note))
                    .font(.system(size: NotoTheme.FontSize.rowTitle, weight: .semibold))
                    .foregroundStyle(NotoTheme.head)
                    .lineLimit(1)
                Text(NotoRelativeDate.editedString(from: note.modifiedDate))
                    .font(.system(size: NotoTheme.FontSize.subtitle))
                    .foregroundStyle(NotoTheme.muted)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("browseNoteRow")
    }
}
