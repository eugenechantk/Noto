import NotoVault
import SwiftUI
import os.log

private let browseLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto2", category: "BrowseScreen")

/// Navigation targets shared by Browse and Search (a search hit opens the same
/// note screen the explorer does).
enum BrowseDestination: Hashable {
    case folder(NotoFolder)
    case note(MarkdownNote, directoryURL: URL)

    /// The editor target for a note at `fileURL`, or `nil` when the URL is not
    /// a note inside this vault. Shared by every entry point that opens a note
    /// from a bare file URL — a search hit and a freshly filed capture — so the
    /// two cannot drift. The note's own directory is carried through: an
    /// `inbox/` note must be edited through the `inbox/` store, not the root.
    @MainActor
    static func note(at fileURL: URL, in vaultController: VaultController) -> BrowseDestination? {
        guard let relative = vaultController.vaultRelativePath(for: fileURL),
              let located = vaultController.note(atVaultRelativePath: relative) else { return nil }
        return .note(located.note, directoryURL: located.store.directoryURL)
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
                onOpen: { path.append($0) }
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                        .accessibilityIdentifier("browseSettingsButton")
                }
            }
            .sheet(isPresented: $showSettings) {
                OpenRouterSettingsSheet(locationManager: locationManager)
            }
            .navigationDestination(for: BrowseDestination.self) { destination in
                BrowseDestinationView(destination: destination, vaultController: vaultController, onOpen: { path.append($0) })
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
            FolderListView(store: vaultController.store(for: folder), title: folder.name, vaultController: vaultController, onOpen: onOpen)
        case .note(let note, let directoryURL):
            NoteScreen(store: vaultController.store(for: directoryURL), note: note, vaultController: vaultController)
        }
    }
}

struct FolderListView: View {
    let store: MarkdownNoteStore
    let title: String
    let vaultController: VaultController
    var onOpen: (BrowseDestination) -> Void

    private var items: [DirectoryItem] { ExplorerSorting.sorted(store.items) }

    var body: some View {
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
                    case .note(let note): onOpen(.note(note, directoryURL: store.directoryURL))
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
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            store.loadItemsInBackground()
        }
        .task {
            if store.items.isEmpty {
                store.loadItemsInBackground()
            }
        }
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
