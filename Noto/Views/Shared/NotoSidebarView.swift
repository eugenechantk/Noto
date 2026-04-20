import SwiftUI
import NotoVault

struct NotoSidebarView: View {
    var rootStore: MarkdownNoteStore
    var fileWatcher: VaultFileWatcher?
    @Binding var selectedNote: MarkdownNote?
    @Binding var selectedNoteStore: MarkdownNoteStore?
    @Binding var selectedIsNew: Bool
    @Binding var externallyDeletingNoteID: UUID?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var searchText = ""
    @State private var rows: [SidebarTreeNode] = []
    @State private var expandedFolderURLs: Set<URL> = []
    @State private var hasLoadedExpansionState = false
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var newFolderParentURL: URL?

    private let loader = SidebarTreeLoader()

    var body: some View {
        VStack(spacing: 8) {
            searchField
                .padding(.horizontal, 12)
                .padding(.top, 8)

            List {
                ForEach(displayRows) { row in
                    sidebarRow(row)
                        .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
                        .listRowSeparator(.hidden)
                        .listRowBackground(rowBackground(for: row))
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .contextMenu {
                createMenuItems(in: rootStore.vaultRootURL)
            }
        }
        .background(.clear)
        .navigationTitle("Noto")
        .alert("New Folder", isPresented: $showNewFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                commitNewFolder()
            }
            Button("Cancel", role: .cancel) {
                resetNewFolderState()
            }
        }
        .task {
            reloadTree()
        }
        .onChange(of: fileWatcher?.changeCount) { _, _ in
            reloadTree()
            applySelectedNoteUpdate(selectedNote)
        }
        .onChange(of: selectedNote) { _, updatedNote in
            applySelectedNoteUpdate(updatedNote)
        }
    }

    private var displayRows: [SidebarTreeNode] {
        loader.filterRows(rows, matching: searchText)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(AppTheme.mutedText)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(AppTheme.primaryText)
                .accessibilityIdentifier("sidebar_search_field")
        }
        .padding(.horizontal, 10)
        .frame(minHeight: searchFieldHeight)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.primaryText.opacity(0.07))
        }
    }

    private var searchFieldHeight: CGFloat {
        #if os(macOS)
        28
        #else
        horizontalSizeClass == .regular ? 36 : 32
        #endif
    }

    private var rowHeight: CGFloat {
        #if os(macOS)
        24
        #else
        horizontalSizeClass == .regular ? 44 : 32
        #endif
    }

    @ViewBuilder
    private func sidebarRow(_ row: SidebarTreeNode) -> some View {
        Button {
            activate(row)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbolName(for: row))
                    .font(.body)
                    .foregroundStyle(.tint)
                    .frame(width: 18, alignment: .center)
                Text(row.name)
                    .font(.body)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(row.depth) * 16)
            .frame(minHeight: rowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier(for: row))
        .contextMenu {
            contextMenuItems(for: row)
        }
    }

    @ViewBuilder
    private func contextMenuItems(for row: SidebarTreeNode) -> some View {
        switch row.kind {
        case .folder:
            createMenuItems(in: row.url)
        case .note:
            createMenuItems(in: row.url.deletingLastPathComponent())
        }

        Divider()

        Button(role: .destructive) {
            delete(row)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func createMenuItems(in directoryURL: URL) -> some View {
        Button {
            createNote(in: directoryURL)
        } label: {
            Label("New Note", systemImage: "doc.badge.plus")
        }
        .accessibilityIdentifier("new_note_context_menu_item")

        Button {
            beginNewFolder(in: directoryURL)
        } label: {
            Label("New Folder", systemImage: "folder.badge.plus")
        }
        .accessibilityIdentifier("new_folder_context_menu_item")
    }

    private func rowBackground(for row: SidebarTreeNode) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isSelected(row) ? AppTheme.selectedRowBackground : Color.clear)
    }

    private func symbolName(for row: SidebarTreeNode) -> String {
        switch row.kind {
        case .folder(isExpanded: true):
            "folder.fill"
        case .folder(isExpanded: false):
            "folder"
        case .note:
            "doc"
        }
    }

    private func accessibilityIdentifier(for row: SidebarTreeNode) -> String {
        switch row.kind {
        case .folder:
            "folder_\(row.name)"
        case .note:
            "note_\(row.name)"
        }
    }

    private func activate(_ row: SidebarTreeNode) {
        switch row.kind {
        case .folder:
            toggleFolder(row.url)
        case .note:
            selectNote(at: row.url, modifiedAt: row.modifiedAt)
        }
    }

    private func toggleFolder(_ url: URL) {
        let normalizedURL = url.standardizedFileURL
        if expandedFolderURLs.contains(normalizedURL) {
            expandedFolderURLs.remove(normalizedURL)
        } else {
            expandedFolderURLs.insert(normalizedURL)
        }
        persistExpansionState()
        reloadTree()
    }

    private func selectNote(at url: URL, modifiedAt: Date) {
        let noteStore = MarkdownNoteStore(directoryURL: url.deletingLastPathComponent(), vaultRootURL: rootStore.vaultRootURL)
        let note = markdownNote(for: url, modifiedAt: modifiedAt)
        selectedNoteStore = noteStore
        selectedNote = note
        selectedIsNew = false
    }

    private func createNote(in directoryURL: URL) {
        let noteStore = MarkdownNoteStore(directoryURL: directoryURL, vaultRootURL: rootStore.vaultRootURL)
        let note = noteStore.createNote()
        expandedFolderURLs.insert(directoryURL.standardizedFileURL)
        persistExpansionState()
        selectedNoteStore = noteStore
        selectedNote = note
        selectedIsNew = true
        reloadTree()
    }

    private func beginNewFolder(in directoryURL: URL) {
        newFolderParentURL = directoryURL
        newFolderName = ""
        showNewFolderAlert = true
    }

    private func commitNewFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            resetNewFolderState()
            return
        }

        let parentURL = newFolderParentURL ?? rootStore.vaultRootURL
        let parentStore = MarkdownNoteStore(directoryURL: parentURL, vaultRootURL: rootStore.vaultRootURL)
        let folder = parentStore.createFolder(name: name)
        expandedFolderURLs.insert(parentURL.standardizedFileURL)
        expandedFolderURLs.insert(folder.folderURL.standardizedFileURL)
        persistExpansionState()
        resetNewFolderState()
        reloadTree()
    }

    private func resetNewFolderState() {
        newFolderName = ""
        newFolderParentURL = nil
    }

    private func delete(_ row: SidebarTreeNode) {
        switch row.kind {
        case .folder:
            let parentStore = MarkdownNoteStore(directoryURL: row.url.deletingLastPathComponent(), vaultRootURL: rootStore.vaultRootURL)
            parentStore.deleteFolder(NotoFolder(
                id: VaultDirectoryLoader.stableID(for: row.url),
                folderURL: row.url,
                name: row.name,
                modifiedDate: row.modifiedAt
            ))
            expandedFolderURLs.remove(row.url.standardizedFileURL)
            persistExpansionState()
        case .note:
            let parentStore = MarkdownNoteStore(directoryURL: row.url.deletingLastPathComponent(), vaultRootURL: rootStore.vaultRootURL)
            let note = markdownNote(for: row.url, modifiedAt: row.modifiedAt)
            externallyDeletingNoteID = note.id
            if selectedNote?.fileURL.standardizedFileURL == row.url.standardizedFileURL {
                selectedNote = nil
                selectedNoteStore = nil
                selectedIsNew = false
            }
            parentStore.deleteNote(note)
        }
        reloadTree()
    }

    private func markdownNote(for url: URL, modifiedAt: Date) -> MarkdownNote {
        let content = CoordinatedFileManager.readString(from: url) ?? ""
        let titleResolver = NoteTitleResolver()
        let id = MarkdownNote.idFromFrontmatter(content) ?? VaultDirectoryLoader.stableID(for: url)
        return MarkdownNote(
            id: id,
            fileURL: url,
            title: titleResolver.title(from: content, fallbackTitle: titleResolver.fallbackTitle(for: url)),
            modifiedDate: modifiedAt
        )
    }

    private func isSelected(_ row: SidebarTreeNode) -> Bool {
        guard case .note = row.kind else { return false }
        return selectedNote?.fileURL.standardizedFileURL == row.url.standardizedFileURL
    }

    private func applySelectedNoteUpdate(_ note: MarkdownNote?) {
        guard let note else { return }
        let normalizedURL = note.fileURL.standardizedFileURL

        guard let index = rows.firstIndex(where: { $0.url == normalizedURL }) else {
            reloadTree()
            return
        }

        let row = rows[index]
        guard case .note = row.kind, row.name != note.title || row.modifiedAt != note.modifiedDate else {
            return
        }

        rows[index] = SidebarTreeNode(
            kind: row.kind,
            depth: row.depth,
            name: note.title,
            url: normalizedURL,
            modifiedAt: note.modifiedDate
        )
    }

    private func reloadTree() {
        do {
            loadExpansionStateIfNeeded()
            if !hasPersistedExpansionState {
                let expandedRows = try loader.loadRows(rootURL: rootStore.vaultRootURL)
                expandedFolderURLs = Set(expandedRows.compactMap { row in
                    if case .folder = row.kind {
                        return row.url.standardizedFileURL
                    }
                    return nil
                })
                persistExpansionState()
                rows = expandedRows
            } else {
                rows = try loader.loadRows(
                    rootURL: rootStore.vaultRootURL,
                    expandedFolderURLs: expandedFolderURLs
                )
            }
        } catch {
            rows = []
        }
    }

    private var expansionStateKey: String {
        "NotoSidebarExpandedFolderURLs.\(rootStore.vaultRootURL.standardizedFileURL.path)"
    }

    private var hasPersistedExpansionState: Bool {
        UserDefaults.standard.object(forKey: expansionStateKey) != nil
    }

    private func loadExpansionStateIfNeeded() {
        guard !hasLoadedExpansionState else { return }
        hasLoadedExpansionState = true
        guard let paths = UserDefaults.standard.array(forKey: expansionStateKey) as? [String] else { return }
        expandedFolderURLs = Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL })
    }

    private func persistExpansionState() {
        let paths = expandedFolderURLs
            .map(\.standardizedFileURL.path)
            .sorted()
        UserDefaults.standard.set(paths, forKey: expansionStateKey)
    }
}
