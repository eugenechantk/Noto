import SwiftUI
import NotoVault

#if os(macOS)
import AppKit
#endif

struct NotoSidebarView: View {
    var rootStore: MarkdownNoteStore
    var fileWatcher: VaultFileWatcher?
    @Binding var selectedNote: MarkdownNote?
    @Binding var selectedNoteStore: MarkdownNoteStore?
    @Binding var selectedIsNew: Bool
    @Binding var externallyDeletingNoteID: UUID?
    @Binding var searchText: String
    @Binding var isSearchPresented: Bool

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var rows: [SidebarTreeNode] = []
    @State private var searchableRows: [SidebarTreeNode] = []
    @State private var expandedFolderURLs: Set<URL> = []
    @State private var hasLoadedExpansionState = false
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var newFolderParentURL: URL?
    @State private var searchLoadTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool

    private let loader = SidebarTreeLoader()

    var body: some View {
        VStack(spacing: 8) {
            sidebarRows
        }
        .background {
            sidebarBackground
        }
        .navigationTitle("Noto")
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                searchButton
            }
        }
        #endif
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
        .onChange(of: searchText) { _, updatedSearchText in
            handleSearchTextChange(updatedSearchText)
        }
    }

    @ViewBuilder
    private var sidebarBackground: some View {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
        #else
        AppTheme.background
            .ignoresSafeArea(edges: .bottom)
        #endif
    }

    @ViewBuilder
    private var sidebarRows: some View {
        #if os(macOS)
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(displayRows) { row in
                    sidebarRow(row)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.vertical, 4)
        }
        .background(.clear)
        .contextMenu {
            createMenuItems(in: rootStore.vaultRootURL)
        }
        #else
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(displayRows) { row in
                    sidebarRow(row)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
        .background(AppTheme.background)
        .contextMenu {
            createMenuItems(in: rootStore.vaultRootURL)
        }
        #endif
    }

    private var sidebarRowInsets: EdgeInsets {
        #if os(macOS)
        EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        #else
        EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        #endif
    }

    private var displayRows: [SidebarTreeNode] {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearchText.isEmpty else { return rows }
        return loader.filterRows(searchableRows, matching: trimmedSearchText)
    }

    private var searchButton: some View {
        Button {
            isSearchPresented.toggle()
        } label: {
            Label("Search", systemImage: "magnifyingglass")
        }
        .labelStyle(.iconOnly)
        .accessibilityIdentifier("search_button")
        .accessibilityLabel("Search")
        .help("Search")
        .popover(isPresented: $isSearchPresented, arrowEdge: .top) {
            searchPopover
        }
    }

    private var searchPopover: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.mutedText)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .accessibilityIdentifier("sidebar_search_field")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Label("Clear Search", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .labelStyle(.iconOnly)
                .foregroundStyle(AppTheme.mutedText)
                .accessibilityIdentifier("clear_search_button")
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 240, height: 32)
        .onAppear {
            isSearchFocused = true
        }
    }

    private var rowHeight: CGFloat {
        #if os(macOS)
        28
        #else
        40
        #endif
    }

    private func rowContentInsets(for row: SidebarTreeNode) -> EdgeInsets {
        #if os(macOS)
        EdgeInsets(top: 0, leading: 10 + CGFloat(row.depth) * 16, bottom: 0, trailing: 8)
        #else
        return EdgeInsets(
            top: 1,
            leading: 20 + CGFloat(row.depth) * 16,
            bottom: 1,
            trailing: 20
        )
        #endif
    }

    @ViewBuilder
    private func sidebarRow(_ row: SidebarTreeNode) -> some View {
        let isSelected = isSelected(row)

        Button {
            activate(row)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbolName(for: row))
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AppTheme.primaryText : AppTheme.secondaryText)
                    .frame(width: 18, alignment: .center)
                Text(row.name)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AppTheme.primaryText : AppTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(rowContentInsets(for: row))
            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
            .background(rowBackground(for: row))
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
            selectNote(row)
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

    private func selectNote(_ row: SidebarTreeNode) {
        let noteStore = MarkdownNoteStore(
            directoryURL: row.url.deletingLastPathComponent(),
            vaultRootURL: rootStore.vaultRootURL,
            autoload: false
        )
        let note = MarkdownNote(
            id: row.noteID ?? VaultDirectoryLoader.stableID(for: row.url),
            fileURL: row.url,
            title: row.name,
            modifiedDate: row.modifiedAt
        )
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

        let didUpdateVisibleRows = updateNoteRow(
            in: &rows,
            matching: normalizedURL,
            title: note.title,
            modifiedAt: note.modifiedDate
        )
        let didUpdateSearchableRows = updateNoteRow(
            in: &searchableRows,
            matching: normalizedURL,
            title: note.title,
            modifiedAt: note.modifiedDate
        )

        guard didUpdateVisibleRows || didUpdateSearchableRows else {
            reloadTree()
            return
        }
    }

    private func updateNoteRow(
        in rowSnapshot: inout [SidebarTreeNode],
        matching normalizedURL: URL,
        title: String,
        modifiedAt: Date
    ) -> Bool {
        guard let index = rowSnapshot.firstIndex(where: { $0.url == normalizedURL }) else {
            return false
        }

        let row = rowSnapshot[index]
        guard case .note = row.kind else {
            return true
        }
        guard row.name != title || row.modifiedAt != modifiedAt else {
            return true
        }

        rowSnapshot[index] = SidebarTreeNode(
            kind: row.kind,
            depth: row.depth,
            name: title,
            url: normalizedURL,
            modifiedAt: modifiedAt,
            noteID: row.noteID
        )
        return true
    }

    private func reloadTree() {
        do {
            loadExpansionStateIfNeeded()
            if !hasPersistedExpansionState {
                expandedFolderURLs = []
                persistExpansionState()
            }

            rows = try loader.loadRows(
                rootURL: rootStore.vaultRootURL,
                expandedFolderURLs: expandedFolderURLs
            )
            handleSearchTextChange(searchText)
        } catch {
            rows = []
            searchableRows = []
        }
    }

    private func handleSearchTextChange(_ text: String) {
        let trimmedSearchText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearchText.isEmpty else {
            searchLoadTask?.cancel()
            searchableRows = []
            return
        }

        reloadSearchableRows()
    }

    private func reloadSearchableRows() {
        searchLoadTask?.cancel()
        let rootURL = rootStore.vaultRootURL
        searchLoadTask = Task {
            let loadedRows = await Task.detached(priority: .userInitiated) {
                (try? SidebarTreeLoader().loadRows(rootURL: rootURL)) ?? []
            }.value

            guard !Task.isCancelled else { return }
            searchableRows = loadedRows
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
