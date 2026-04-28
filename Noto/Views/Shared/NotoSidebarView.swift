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
        .background(AppTheme.sidebarBackground)
        .notoSidebarOwnsTopEdge()
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppTheme.separator.opacity(0.85))
                .frame(width: 0.5)
                .allowsHitTesting(false)
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
        #if os(macOS)
        .background(currentDirectoryDropTarget)
        #endif
    }

    private var sidebarHeader: some View {
        ZStack {
            Text(currentPage.title)
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(AppTheme.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 44)

            HStack {
                if !folderStack.isEmpty {
                    Button {
                        folderStack.removeLast()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("sidebar_back_button")
                    .accessibilityLabel("Back")
                    .help("Back")
                }

                Spacer(minLength: 0)

                Button {
                    onIntent(.openSearch)
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("search_button")
                .accessibilityLabel("Search")
                .help("Search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 0)
        .padding(.bottom, 6)
        .notoSidebarHeaderTopInset()
        .background(AppTheme.sidebarBackground)
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
        self
        #endif
    }
}
