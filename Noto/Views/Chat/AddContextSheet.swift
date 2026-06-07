import SwiftUI

/// The "Add context" picker (HIG sheet): browse the vault folder-by-folder OR
/// search a flat list across all levels; every row shows its vault-path
/// breadcrumb so deeply-nested notes are identifiable. Multi-select; returns
/// the chosen vault-relative paths to the composer's mention tags.
/// See `.claude/notochat-ui/component-breakdown.md`.
struct AddContextSheet: View {
    let vaultURL: URL
    /// Already-attached paths (pre-checked).
    let initiallySelected: Set<String>
    /// Called with the final selection on confirm.
    let onConfirm: (Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected: Set<String>
    @State private var browseDir: String = ""   // vault-relative folder being browsed ("" = root)
    @State private var allNotes: [VaultNoteRef] = []

    init(vaultURL: URL, initiallySelected: Set<String>, onConfirm: @escaping (Set<String>) -> Void) {
        self.vaultURL = vaultURL
        self.initiallySelected = initiallySelected
        self.onConfirm = onConfirm
        _selected = State(initialValue: initiallySelected)
    }

    var body: some View {
        ZStack {
            NotoChatTokens.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                searchField
                if query.isEmpty {
                    browseList
                } else {
                    searchResults
                }
                footer
            }
        }
        .preferredColorScheme(.dark)
        .tint(NotoChatTokens.accent)
        .task { allNotes = Self.enumerateNotes(in: vaultURL) }
        .accessibilityIdentifier("addContext.sheet")
    }

    // MARK: Header (✕ · title · ✓)

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NotoChatTokens.ink).frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            Spacer()
            VStack(spacing: 1) {
                Text("Add context").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NotoChatTokens.head)
                Text("\(selected.count) selected").font(.system(size: 12))
                    .foregroundStyle(NotoChatTokens.faint)
            }
            Spacer()
            Button { onConfirm(selected); dismiss() } label: {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white).frame(width: 30, height: 30)
                    .background(NotoChatTokens.accent, in: Circle())
            }
            .accessibilityIdentifier("addContext.confirm")
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(NotoChatTokens.faint)
            TextField("Search notes", text: $query)
                .textFieldStyle(.plain).foregroundStyle(NotoChatTokens.ink)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(NotoChatTokens.userPill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16).padding(.bottom, 6)
        .accessibilityIdentifier("addContext.search")
    }

    // MARK: Browse (folder-by-folder)

    private var browseList: some View {
        List {
            if !browseDir.isEmpty {
                Button {
                    browseDir = (browseDir as NSString).deletingLastPathComponent
                } label: {
                    Label("Vault", systemImage: "chevron.left").foregroundStyle(NotoChatTokens.accent)
                }
                .listRowBackground(Color.clear)
            }
            ForEach(childFolders(of: browseDir), id: \.self) { folder in
                Button { browseDir = folder } label: {
                    HStack {
                        Image(systemName: "folder").foregroundStyle(NotoChatTokens.ink)
                        Text((folder as NSString).lastPathComponent).foregroundStyle(NotoChatTokens.head)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(NotoChatTokens.faint)
                    }
                }
                .listRowBackground(Color.clear)
            }
            ForEach(notes(inFolder: browseDir)) { note in
                pickerRow(note, showBreadcrumb: false)
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
    }

    private var searchResults: some View {
        List {
            Section {
                ForEach(allNotes.filter {
                    $0.title.localizedCaseInsensitiveContains(query)
                }) { note in
                    pickerRow(note, showBreadcrumb: true)
                }
            } header: {
                Text("Results · all notes").font(.system(size: 11)).foregroundStyle(NotoChatTokens.faint)
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
    }

    private func pickerRow(_ note: VaultNoteRef, showBreadcrumb: Bool) -> some View {
        Button {
            if selected.contains(note.path) { selected.remove(note.path) } else { selected.insert(note.path) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc").foregroundStyle(NotoChatTokens.faint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title).foregroundStyle(NotoChatTokens.head).lineLimit(1)
                    if showBreadcrumb, !note.breadcrumb.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "folder").font(.system(size: 9))
                            Text(note.breadcrumb).font(.system(size: 12))
                        }.foregroundStyle(NotoChatTokens.faint)
                    }
                }
                Spacer()
                Image(systemName: selected.contains(note.path) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected.contains(note.path) ? NotoChatTokens.accent : NotoChatTokens.faint)
            }
        }
        .listRowBackground(selected.contains(note.path) ? Color.white.opacity(0.04) : Color.clear)
        .accessibilityIdentifier("addContext.row.\(note.path)")
    }

    private var footer: some View {
        HStack {
            Text("\(selected.count) selected").font(.system(size: 13)).foregroundStyle(NotoChatTokens.faint)
            Spacer()
            Button("Add to chat") { onConfirm(selected); dismiss() }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(NotoChatTokens.accent)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    // MARK: Data

    private func childFolders(of dir: String) -> [String] {
        let prefix = dir.isEmpty ? "" : dir + "/"
        var set = Set<String>()
        for n in allNotes where n.path.hasPrefix(prefix) {
            let rest = String(n.path.dropFirst(prefix.count))
            if let slash = rest.firstIndex(of: "/") {
                set.insert(prefix + rest[..<slash])
            }
        }
        return set.sorted()
    }

    private func notes(inFolder dir: String) -> [VaultNoteRef] {
        allNotes.filter { (($0.path as NSString).deletingLastPathComponent) == dir }
            .sorted { $0.title < $1.title }
    }
}

/// A note reference for the picker: vault-relative path + display helpers.
struct VaultNoteRef: Identifiable, Hashable {
    let path: String
    var id: String { path }
    var title: String { NotoChatPath.title(path) }
    var breadcrumb: String { NotoChatPath.breadcrumb(path) }
}

extension AddContextSheet {
    /// Recursively enumerate `.md` notes under the vault, returning vault-relative paths.
    static func enumerateNotes(in vaultURL: URL) -> [VaultNoteRef] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: vaultURL, includingPropertiesForKeys: [.isRegularFileKey],
                                     options: [.skipsHiddenFiles]) else { return [] }
        var out: [VaultNoteRef] = []
        let base = vaultURL.standardizedFileURL.path
        for case let url as URL in en where url.pathExtension == "md" {
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(base) else { continue }
            var rel = String(full.dropFirst(base.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            out.append(VaultNoteRef(path: rel))
        }
        return out.sorted { $0.path < $1.path }
    }
}
