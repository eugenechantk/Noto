import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct NotoSidebarView: View {
    var rootStore: MarkdownNoteStore
    var fileWatcher: VaultFileWatcher?
    var selectedNote: MarkdownNote?
    @Binding var searchText: String
    var onIntent: (VaultWorkspaceIntent) -> Void
    var onToggleSidebar: (() -> Void)? = nil

    @State private var folderStack: [SidebarDirectoryPage] = []
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    #if os(macOS)
    @State private var targetedDropDirectoryURL: URL?
    @State private var draggedNoteURL: URL?
    #endif

    private var currentPage: SidebarDirectoryPage {
        folderStack.last ?? SidebarDirectoryPage(store: rootStore, title: "Noto")
    }

    private var currentStore: MarkdownNoteStore {
        currentPage.store
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            #if os(macOS)
            DirectoryContentListView(
                store: currentStore,
                fileWatcher: fileWatcher,
                selectedNote: selectedNote,
                presentation: .sidebar,
                onOpenFolder: openFolder,
                onOpenNote: openNote,
                onDeleteItem: deleteItem,
                onNoteDrag: noteDragProvider
            )
            .contextMenu {
                sidebarContextMenu
            }
            #else
            DirectoryContentListView(
                store: currentStore,
                fileWatcher: fileWatcher,
                selectedNote: selectedNote,
                presentation: .sidebar,
                onOpenFolder: openFolder,
                onOpenNote: openNote,
                onDeleteItem: deleteItem
            )
            .contextMenu {
                sidebarContextMenu
            }
            #endif
        }
        .notoSidebarBackground()
        .notoSidebarOwnsTopEdge()
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppTheme.separator.opacity(0.85))
                .frame(width: 0.5)
                .allowsHitTesting(false)
                .notoSidebarHidesTrailingRule()
        }
        .contextMenu {
            sidebarContextMenu
        }
        .alert("New Folder", isPresented: $showNewFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                createFolder()
            }
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
        }
        .onAppear {
            expandToSelectedNote()
        }
        .onChange(of: selectedNote) { _, _ in
            expandToSelectedNote()
        }
        #if os(macOS)
        .background(currentDirectoryDropTarget)
        #endif
    }

    @ViewBuilder
    private var sidebarHeader: some View {
        vaultSidebarHeader
    }

    /// v2 design (VaultSidebarContent): explorer nav row (accent `‹ parent` back ·
    /// new-folder + ⋯ more) over a large folder title + "N folders · M notes" counts.
    /// Shared across iPhone, iPad, and macOS.
    private var vaultSidebarHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                if !folderStack.isEmpty {
                    Button {
                        folderStack.removeLast()
                    } label: {
                        HStack(spacing: 1) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                            Text(parentTitle)
                                .font(.system(size: 16, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(NotoTheme.accent)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sidebar_back_button")
                    .accessibilityLabel("Back")
                }

                Spacer(minLength: 0)

                // iOS/iPadOS AND macOS: new-folder + more live in the content header,
                // on the same nav row as the `‹ back` button (matching the iPad layout).
                HStack(spacing: 20) {
                    Button {
                        showNewFolderAlert = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(NotoTheme.head)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sidebar_new_folder_button")
                    .accessibilityLabel("New Folder")

                    Menu {
                        Button {
                            onIntent(.createNote(in: currentStore))
                        } label: {
                            Label("New Note", systemImage: "doc.badge.plus")
                        }
                        Button {
                            showNewFolderAlert = true
                        } label: {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                        Divider()
                        Button {
                            onIntent(.openSettings)
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(NotoTheme.head)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .menuIndicator(.hidden)
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityIdentifier("sidebar_more_button")
                    .accessibilityLabel("More")
                }
            }
            .frame(minHeight: 22)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(currentPage.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(NotoTheme.head)
                    .lineLimit(1)
                Text(countsSummary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(NotoTheme.muted)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)

            Rectangle()
                .fill(NotoTheme.hairline)
                .frame(height: 0.5)
        }
        .notoSidebarHeaderTopInset()
        .notoSidebarHeaderBackground()
    }

    private var parentTitle: String {
        if folderStack.count >= 2 {
            return folderStack[folderStack.count - 2].title
        }
        return "Vault"
    }

    private var countsSummary: String {
        let folderCount = currentStore.items.reduce(into: 0) { count, item in
            if case .folder = item { count += 1 }
        }
        let noteCount = currentStore.items.reduce(into: 0) { count, item in
            if case .note = item { count += 1 }
        }
        let folderPart = "\(folderCount) folder" + (folderCount == 1 ? "" : "s")
        let notePart = "\(noteCount) note" + (noteCount == 1 ? "" : "s")
        return "\(folderPart) · \(notePart)"
    }

    private var legacySidebarHeader: some View {
        ZStack {
            Text(currentPage.title)
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(AppTheme.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 44)

            HStack(spacing: 0) {
                if !folderStack.isEmpty {
                    Button {
                        folderStack.removeLast()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: sidebarHeaderButtonSize, height: sidebarHeaderButtonSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sidebar_back_button")
                    .accessibilityLabel("Back")
                    .help("Back")
                }

                Spacer(minLength: 0)

                #if os(iOS)
                Button {
                    onIntent(.openSettings)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 17, weight: .regular))
                        .frame(width: sidebarHeaderButtonSize, height: sidebarHeaderButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar_settings_button")
                .accessibilityLabel("Settings")
                .help("Settings")
                #endif

                Button {
                    onIntent(.openChat)
                } label: {
                    Label("AI Chat", systemImage: "bubble.left")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 17, weight: .regular))
                        .frame(width: sidebarHeaderButtonSize, height: sidebarHeaderButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar_chat_button")
                .accessibilityLabel("AI Chat")
                .help("AI Chat")

                Button {
                    onIntent(.openSearch)
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 17, weight: .regular))
                        .frame(width: sidebarHeaderButtonSize, height: sidebarHeaderButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search_button")
                .accessibilityLabel("Search")
                .help("Search")
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 0)
        .padding(.bottom, 8)
        .notoSidebarHeaderTopInset()
        .notoSidebarHeaderBackground()
    }

    private var sidebarHeaderButtonSize: CGFloat {
        #if os(iOS)
        44
        #else
        28
        #endif
    }

    private func expandToSelectedNote() {
        guard let selectedNote else { return }
        guard let relativePath = rootStore.vaultRelativePath(for: selectedNote.fileURL) else { return }
        let folderPath = (relativePath as NSString).deletingLastPathComponent
        guard !folderPath.isEmpty, folderPath != "." else {
            if !folderStack.isEmpty {
                folderStack = []
            }
            return
        }
        let components = folderPath.split(separator: "/").map(String.init)
        // Skip the rebuild when the stack already points at this folder. Each
        // rebuild allocates fresh, unloaded MarkdownNoteStore instances; if the
        // new currentStore's directory path matches the old one, the
        // DirectoryContentListView's .task(id:) won't re-fire and the new store
        // is never loaded — leaving the sidebar visually empty.
        if folderStack.map(\.title) == components {
            return
        }
        var newStack: [SidebarDirectoryPage] = []
        var currentURL = rootStore.vaultRootURL.standardizedFileURL
        for component in components {
            currentURL = currentURL.appendingPathComponent(component)
            let store = MarkdownNoteStore(
                directoryURL: currentURL,
                vaultRootURL: rootStore.vaultRootURL,
                autoload: false,
                directoryLoader: rootStore.directoryLoader
            )
            newStack.append(SidebarDirectoryPage(store: store, title: component))
        }
        folderStack = newStack
    }

    @ViewBuilder
    private var sidebarContextMenu: some View {
        Button {
            onIntent(.createNote(in: currentStore))
        } label: {
            Label("New Note", systemImage: "doc.badge.plus")
        }

        Button {
            showNewFolderAlert = true
        } label: {
            Label("New Folder", systemImage: "folder.badge.plus")
        }
    }

    private func openFolder(_ folder: NotoFolder, parentStore: MarkdownNoteStore) {
        let store = MarkdownNoteStore(
            directoryURL: folder.folderURL,
            vaultRootURL: parentStore.vaultRootURL,
            autoload: false,
            directoryLoader: parentStore.directoryLoader
        )
        folderStack.append(SidebarDirectoryPage(store: store, title: folder.name))
    }

    private func openNote(_ note: MarkdownNote, noteStore: MarkdownNoteStore, isNew: Bool) {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchText = ""
        }
        onIntent(.openNote(note, store: noteStore, isNew: isNew))
    }

    private func deleteItem(_ item: DirectoryItem, noteStore: MarkdownNoteStore) {
        onIntent(.deleteItem(item, in: noteStore))
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderName = ""
        guard !name.isEmpty else { return }
        onIntent(.createFolder(named: name, in: currentStore))
    }

    #if os(macOS)
    private var currentDirectoryDropTarget: some View {
        Color.clear
            .contentShape(Rectangle())
            .onDrop(
                of: [UTType.fileURL],
                isTargeted: currentDirectoryDropTargetBinding,
                perform: { providers in
                    handleNoteDrop(providers, to: currentStore.directoryURL.standardizedFileURL)
                }
            )
    }

    private var currentDirectoryDropTargetBinding: Binding<Bool> {
        Binding(
            get: {
                targetedDropDirectoryURL == currentStore.directoryURL.standardizedFileURL
            },
            set: { isTargeted in
                targetedDropDirectoryURL = isTargeted ? currentStore.directoryURL.standardizedFileURL : nil
            }
        )
    }

    private func noteDragProvider(for note: MarkdownNote) -> NSItemProvider {
        let fileURL = note.fileURL.standardizedFileURL
        draggedNoteURL = fileURL
        return NSItemProvider(contentsOf: fileURL) ?? NSItemProvider(object: fileURL as NSURL)
    }

    private func handleNoteDrop(_ providers: [NSItemProvider], to destinationURL: URL) -> Bool {
        if let draggedNoteURL {
            moveDroppedNote(from: draggedNoteURL, to: destinationURL)
            return true
        }

        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let sourceURL = droppedFileURL(from: item) else { return }
            DispatchQueue.main.async {
                moveDroppedNote(from: sourceURL, to: destinationURL)
            }
        }
        return true
    }

    private func droppedFileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let url = item as? NSURL {
            return url as URL
        }
        if let data = item as? Data,
           let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url
        }
        if let string = item as? String {
            return URL(string: string) ?? URL(fileURLWithPath: string)
        }
        return nil
    }

    private func moveDroppedNote(from sourceURL: URL, to destinationURL: URL) {
        let normalizedSourceURL = sourceURL.standardizedFileURL
        let normalizedDestinationURL = destinationURL.standardizedFileURL
        guard normalizedSourceURL.pathExtension.localizedCaseInsensitiveCompare("md") == .orderedSame,
              normalizedSourceURL.deletingLastPathComponent() != normalizedDestinationURL,
              FileManager.default.fileExists(atPath: normalizedSourceURL.path),
              normalizedSourceURL.path.hasPrefix(rootStore.vaultRootURL.standardizedFileURL.path + "/") else {
            targetedDropDirectoryURL = nil
            draggedNoteURL = nil
            return
        }

        onIntent(.moveNoteURL(normalizedSourceURL, to: normalizedDestinationURL))
        targetedDropDirectoryURL = nil
        draggedNoteURL = nil
    }
    #endif
}

private struct SidebarDirectoryPage {
    let store: MarkdownNoteStore
    let title: String
}

private extension View {
    @ViewBuilder
    func notoSidebarOwnsTopEdge() -> some View {
        #if os(iOS)
        ignoresSafeArea(edges: .top)
        #else
        self
        #endif
    }

    @ViewBuilder
    func notoSidebarHeaderTopInset() -> some View {
        #if os(iOS)
        safeAreaPadding(.top)
        #else
        // macOS v2: the native split already insets content below the title bar, so
        // no extra top reserve — the nav row sits at the same level as the editor's
        // detail toolbar. Traffic lights are repositioned into the sidebar top via
        // the window chrome (NotoApp).
        self
        #endif
    }

    /// v2: translucent Liquid Glass sidebar. The panel container provides the glass
    /// (macOS `macSidebarGlassPanel()`), so the sidebar's own background is clear there;
    /// iOS paints one uniform dark surface.
    @ViewBuilder
    func notoSidebarBackground() -> some View {
        #if os(iOS)
        // One uniform dark surface across header + list + bottom. The list paints
        // AppTheme.sidebarBackground (0x111113) opaquely, so matching it here removes
        // the two-tone seam (lighter glass at top/bottom vs dark rows region).
        self.background(AppTheme.sidebarBackground)
        #else
        self
        #endif
    }

    @ViewBuilder
    func notoSidebarHeaderBackground() -> some View {
        #if os(iOS)
        self
        #else
        self
        #endif
    }

    /// The flush trailing hairline reads wrong against the translucent glass panel.
    @ViewBuilder
    func notoSidebarHidesTrailingRule() -> some View {
        #if os(iOS)
        self.hidden()
        #else
        self.hidden()
        #endif
    }
}

/// Whether the navigation split sidebar is currently expanded. Set by the split
/// container so the sidebar's toolbar actions can hide when it collapses.
private struct NotoSidebarVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var notoSidebarVisible: Bool {
        get { self[NotoSidebarVisibleKey.self] }
        set { self[NotoSidebarVisibleKey.self] = newValue }
    }
}
