import NotoVault
import SwiftUI

struct LibraryMoveNoteSheet: View {
    let vaultController: VaultController
    let note: MarkdownNote
    let onCancel: () -> Void
    let onMove: (URL) -> Void
    @State private var rows: [SidebarTreeNode] = []
    @State private var expanded: Set<URL> = []
    @State private var selected: URL?
    @State private var query = ""
    @State private var newFolder = false
    @State private var newFolderName = ""
    @State private var revision = 0
    @State private var isLoading = true

    private var current: URL { note.fileURL.deletingLastPathComponent().standardizedFileURL }
    private var root: URL { vaultController.vaultURL.standardizedFileURL }
    private var destinationName: String { selected == root ? "Library" : selected?.lastPathComponent ?? "folder" }
    private var filteredRows: [SidebarTreeNode] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return rows.filter { $0.name.localizedCaseInsensitiveContains(trimmed) } }
        return rows.filter { row in
            var parent = row.url.deletingLastPathComponent().standardizedFileURL
            while parent != root && parent.path.hasPrefix(root.path + "/") {
                guard expanded.contains(parent) else { return false }
                parent = parent.deletingLastPathComponent().standardizedFileURL
            }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            List {
                HStack(spacing: 12) {
                    LibraryRowIcon(symbol: "doc")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(note.title).font(.body.weight(.semibold)).foregroundStyle(NotoTheme.ink)
                        Text("From \(current == root ? "Library" : relativePath(current))").font(.caption).foregroundStyle(NotoTheme.muted)
                    }
                }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                Section {
                    Button("New folder", systemImage: "folder.badge.plus") { newFolder = true }
                        .foregroundStyle(NotoTheme.accentText).accessibilityIdentifier("moveNewFolder")
                }.listRowBackground(NotoTheme.card)
                Section {
                    folderRow(url: root, name: "Library", depth: 0, hasChildren: false)
                    ForEach(filteredRows) { row in
                        folderRow(url: row.url, name: row.name, depth: query.isEmpty ? row.depth + 1 : 0,
                                  hasChildren: rows.contains { $0.url.deletingLastPathComponent().standardizedFileURL == row.url.standardizedFileURL })
                    }
                }.listRowBackground(NotoTheme.card)
                if isLoading { ProgressView().accessibilityIdentifier("moveFoldersLoading") }
            }
            .environment(\.defaultMinListRowHeight, 48)
            .modifier(LibraryListStyle())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search folders")
            .navigationTitle("Move note").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close, action: onCancel)
                        .accessibilityLabel("Cancel").accessibilityIdentifier("move_note_cancel_button")
                }
            }
            .modifier(LibrarySheetAction(title: "Move to \(destinationName)", identifier: "moveNoteConfirm", disabled: selected == nil || selected == current) {
                if let selected { onMove(selected) }
            })
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("moveNoteSheet")
        .task(id: revision) { await load() }
        .sheet(isPresented: $newFolder) {
            LibraryNewFolderSheet(name: $newFolderName) {
                let destination = selected ?? root
                if let created = ExplorerDirectoryActions(vaultController: vaultController, store: vaultController.store(for: destination)).createFolder(named: newFolderName) {
                    selected = created.folderURL.standardizedFileURL
                    expanded.insert(destination)
                }
                newFolderName = ""
                revision += 1
            }
        }
    }

    private func folderRow(url: URL, name: String, depth: Int, hasChildren: Bool) -> some View {
        let normalized = url.standardizedFileURL
        return HStack(spacing: 10) {
            if hasChildren && query.isEmpty {
                Button {
                    if expanded.contains(normalized) { expanded.remove(normalized) } else { expanded.insert(normalized) }
                } label: {
                    Image(systemName: expanded.contains(normalized) ? "chevron.down" : "chevron.right")
                        .font(.caption).frame(width: 24, height: 32)
                }
                .buttonStyle(.plain).foregroundStyle(NotoTheme.muted)
                .accessibilityLabel("\(expanded.contains(normalized) ? "Collapse" : "Expand") \(name)")
                .accessibilityIdentifier("moveExpand_\(name)")
            } else { Color.clear.frame(width: 24, height: 1) }
            Button { selected = normalized } label: {
                HStack(spacing: 12) {
                    Image(systemName: normalized == root ? "books.vertical" : "folder").foregroundStyle(NotoTheme.accentText)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name).foregroundStyle(NotoTheme.ink)
                        if !query.isEmpty { Text(relativePath(url)).font(.caption).foregroundStyle(NotoTheme.muted) }
                    }
                    Spacer()
                    if normalized == current {
                        Text("Current").font(.caption).foregroundStyle(NotoTheme.faint)
                    } else if normalized == selected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(NotoTheme.accent)
                    }
                }.frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(normalized == current)
            .accessibilityIdentifier("move_destination_\(name)")
        }
        .padding(.leading, CGFloat(max(0, depth - 1)) * 20)
        .opacity(normalized == current ? 0.55 : 1)
        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
        .listRowBackground(normalized == selected ? NotoTheme.accentSoft : NotoTheme.card)
    }

    private func relativePath(_ url: URL) -> String {
        VaultPathResolver(vaultRootURL: root).relativePath(for: url)?.replacingOccurrences(of: "/", with: " › ") ?? "Library"
    }

    private func load() async {
        let root = root
        let loaded = await Task.detached(priority: .userInitiated) {
            ((try? SidebarTreeLoader().loadRows(rootURL: root)) ?? []).filter {
                if case .folder = $0.kind { return LibraryCatalog.isVisible($0.url, in: root) }
                return false
            }
        }.value
        guard !Task.isCancelled else { return }
        rows = loaded
        if revision == 0 {
            var parent = current.deletingLastPathComponent().standardizedFileURL
            while parent.path.hasPrefix(root.path + "/") {
                expanded.insert(parent)
                parent = parent.deletingLastPathComponent().standardizedFileURL
            }
        }
        isLoading = false
    }
}
