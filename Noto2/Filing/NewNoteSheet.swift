import NotoDigest
import NotoVault
import SwiftUI

/// UI presentation state shared by the native toolbar actions and their
/// integration regression. It owns no note or folder data.
@MainActor
@Observable
final class NewNotePresentation {
    private(set) var isEditing = false

    func showEditor() { isEditing = true }
    func showFolders() { isEditing = false }
}

@MainActor
struct NewNoteSheet: View {
    let vaultURL: URL
    let draft: String
    private let onCreateWithBody: (NewNoteFolder, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var bodyText: String
    @State private var query = ""
    @State private var folders: [NewNoteFolder] = []
    @State private var recentFolders: [NewNoteFolder] = []
    @State private var selectedID: URL?
    @State private var browsingID: URL?
    @State private var presentation: NewNotePresentation
    @State private var showingNewFolder = false
    @State private var folderName = ""
    @State private var errorMessage: String?
    @FocusState private var searching: Bool
    @ScaledMetric(relativeTo: .body) private var rowTitleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var newFolderIconSize: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var selectionCheckSize: CGFloat = 24

    /// Preserved for existing Capture callers.
    init(vaultURL: URL, draft: String, onCreate: @escaping (NewNoteFolder) -> Void) {
        self.init(vaultURL: vaultURL, draft: draft, onCreateWithBody: { folder, _ in onCreate(folder) })
    }

    init(vaultURL: URL, draft: String, presentation: NewNotePresentation? = nil,
         onCreateWithBody: @escaping (NewNoteFolder, String) -> Void) {
        self.vaultURL = vaultURL
        self.draft = draft
        self.onCreateWithBody = onCreateWithBody
        _bodyText = State(initialValue: draft)
        _presentation = State(initialValue: presentation ?? NewNotePresentation())
    }

    private var editing: Bool { presentation.isEditing }
    private var filename: String {
        DigestMarkdown.noteTitle(fromFirstLineOf: bodyText).flatMap(DigestMarkdown.filename(forTitle:)) ?? "Untitled.md"
    }
    private var selected: NewNoteFolder? { folders.first { $0.id == selectedID } ?? recentFolders.first ?? folders.first }
    private var browsing: NewNoteFolder? { folders.first { $0.id == browsingID } }
    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var matchingFolders: [NewNoteFolder] { NewNoteFolder.matching(folders, query: query) }
    private var destinationPath: String { selected.map { $0.isRoot ? $0.name : $0.path } ?? NewNoteFolder.rootName }

    var body: some View {
        NavigationStack {
            Group {
                if editing {
                    VStack(alignment: .leading, spacing: 0) {
                        Label(filename + " · named from the first line", systemImage: "doc")
                            .font(.footnote).foregroundStyle(NotoTheme.muted)
                            .padding(.horizontal, 20).padding(.top, 12)
                            .accessibilityIdentifier("newNoteFilename")
                        TextKit2EditorView(text: $bodyText, documentID: "new-note-edit", autoFocus: true,
                                           onTextChange: { bodyText = $0 }, vaultRootURL: vaultURL,
                                           keyboardToolbarStyle: .floating,
                                           backgroundColorOverride: .clear)
                            .accessibilityIdentifier("newNoteEditor")
                    }
                    // The editor retains its native accessory and safe-area
                    // behavior. Only the folder picker needs the local adapter.
                    .safeAreaBar(edge: .bottom) { bottomActions }
                } else {
                    FilingKeyboardLayout {
                        folderList
                    } bottomBar: {
                        bottomActions
                    }
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                }
            }
            .navigationTitle("New note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if editing {
                        Button("Back to folders", systemImage: "chevron.left") { presentation.showFolders() }
                            .labelStyle(.iconOnly).tint(NotoTheme.ink).accessibilityIdentifier("newNoteBackToFolders")
                    } else {
                        Button(role: .close) { dismiss() }
                            .tint(NotoTheme.ink).accessibilityIdentifier("newNoteCloseButton")
                    }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 3) {
                        Text(editing ? "Edit note" : "New note").font(.headline)
                        Text("in \(destinationPath)").font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("newNoteDestination")
                    }
                }
            }
        }
        .presentationDetents([.large])
        .task { await load() }
        .alert("New folder", isPresented: $showingNewFolder) {
            TextField("Folder name", text: $folderName).accessibilityIdentifier("newNoteNewFolderName")
            Button("Cancel", role: .cancel) {}
            Button("Create") { Task { await createFolder() } }
                .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: { Text("Create in \(browsing?.name ?? selected?.name ?? NewNoteFolder.rootName)") }
        .alert("Couldn't create folder", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private var folderList: some View {
        List {
            if hasQuery {
                Section {
                    if matchingFolders.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .listRowBackground(NotoTheme.card)
                            .accessibilityIdentifier("newNoteNoFolders")
                    }
                    ForEach(matchingFolders) { folder in folderRow(folder, drills: false) }
                } header: {
                    FilingSectionCaption("\(matchingFolders.count) \(matchingFolders.count == 1 ? "folder" : "folders")")
                }
            } else if let browsing {
                Section {
                    Button {
                        if browsing.isRoot { browsingID = nil }
                        else { browsingID = browsing.url.deletingLastPathComponent().standardizedFileURL }
                    } label: {
                        folderBreadcrumb(browsing)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("newNoteFolderPath")
                }
                Section {
                    Button { selectedID = browsing.id } label: {
                        HStack {
                            Image(systemName: "folder").font(.body).foregroundStyle(NotoTheme.inboxNewNote)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Save here").font(.system(size: rowTitleSize, weight: .semibold))
                                Text(browsing.name).font(.subheadline).foregroundStyle(NotoTheme.muted)
                            }
                            Spacer()
                            if selected?.id == browsing.id { selectionCheck }
                        }
                    }
                    .foregroundStyle(NotoTheme.ink)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(selected?.id == browsing.id ? NotoTheme.accentSoft : NotoTheme.card)
                    .accessibilityIdentifier("newNoteSaveHereRow")
                }
                Section {
                    ForEach(NewNoteFolder.children(of: browsing, in: folders)) { folder in folderRow(folder, drills: true) }
                    newFolderButton("New folder in \(browsing.name)")
                } header: {
                    FilingSectionCaption("Inside \(browsing.name)")
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(filename).font(.footnote).foregroundStyle(.secondary)
                                .accessibilityIdentifier("newNoteFilename")
                            Spacer()
                            Button("Edit") { searching = false; presentation.showEditor() }
                                .foregroundStyle(NotoTheme.accentText).accessibilityIdentifier("newNoteEditButton")
                        }
                        Text(bodyText).font(.body).lineLimit(3)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(NotoTheme.card)
                }
                Section {
                    ForEach(recentFolders) { folder in folderRow(folder, drills: false) }
                } header: {
                    FilingSectionCaption("Recent folders")
                }
                Section {
                    Button {
                        browsingID = folders.first?.id
                        selectedID = folders.first?.id
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder").font(.body).foregroundStyle(NotoTheme.inboxNewNote)
                            Text("All folders").font(.system(size: rowTitleSize, weight: .medium)).foregroundStyle(NotoTheme.ink)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(NotoTheme.faint)
                        }
                        .frame(minHeight: 30)
                    }
                    .listRowInsets(EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16))
                    .listRowBackground(NotoTheme.card)
                    .accessibilityIdentifier("newNoteAllFoldersButton")
                    newFolderButton("New folder")
                }
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, 0, for: .scrollContent)
        .listSectionSpacing(browsing == nil ? 10 : 8)
        .scrollContentBackground(.hidden)
    }

    private var bottomActions: some View {
        VStack(spacing: 10) {
            if !editing {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search folders", text: $query).focused($searching).autocorrectionDisabled()
                        .accessibilityIdentifier("newNoteFolderSearchField")
                    if !query.isEmpty {
                        Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                            .labelStyle(.iconOnly).foregroundStyle(.secondary).accessibilityIdentifier("newNoteClearSearch")
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(.quaternary, in: Capsule())
            }
            Button {
                guard let selected else { return }
                onCreateWithBody(selected, bodyText)
                dismiss()
            } label: {
                Text("Create in \(selected?.name ?? NewNoteFolder.rootName)")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(NotoTheme.onAccent)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).controlSize(.large).tint(NotoTheme.accent)
            .disabled(DigestMarkdown.noteTitle(fromFirstLineOf: bodyText) == nil || selected == nil)
            .accessibilityIdentifier("newNoteCreateButton")
        }
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    private func folderRow(_ folder: NewNoteFolder, drills: Bool) -> some View {
        let isSelected = folder.id == selected?.id
        return Button {
            selectedID = folder.id
            if drills { browsingID = folder.id }
            if hasQuery { query = ""; searching = false; browsingID = folder.id }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: folder.isRoot ? "tray.full" : "folder").font(.body).foregroundStyle(NotoTheme.inboxNewNote)
                VStack(alignment: .leading, spacing: 2) {
                    FilingMatchText(text: folder.name, query: query)
                        .font(.system(size: rowTitleSize, weight: .medium))
                    if !drills && !folder.path.isEmpty && (hasQuery || folder.path != folder.name) {
                        Text(folder.path).font(.subheadline).foregroundStyle(NotoTheme.muted).lineLimit(1)
                    }
                }
                Spacer()
                if drills {
                    Text(folder.noteCount, format: .number).font(.subheadline).foregroundStyle(NotoTheme.muted)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(NotoTheme.faint)
                }
                else if isSelected { selectionCheck }
            }
            .frame(minHeight: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16))
        .listRowBackground(isSelected && !drills ? NotoTheme.accentSoft : NotoTheme.card)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("newNoteFolderRow")
    }

    private var selectionCheck: some View {
        Image(systemName: "checkmark.circle.fill")
            .resizable().scaledToFit()
            .frame(width: selectionCheckSize, height: selectionCheckSize)
            .foregroundStyle(NotoTheme.accent)
            .accessibilityHidden(true)
    }

    private func newFolderButton(_ label: String) -> some View {
        Button { folderName = ""; showingNewFolder = true } label: {
            Label {
                Text(label)
            } icon: {
                Image(systemName: "folder.badge.plus")
                    .resizable().scaledToFit()
                    .frame(width: newFolderIconSize, height: newFolderIconSize)
            }
            .font(.system(size: rowTitleSize, weight: .semibold)).foregroundStyle(NotoTheme.accentText)
            .frame(minHeight: 30)
        }
        .listRowInsets(EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16))
        .listRowBackground(NotoTheme.card)
        .accessibilityIdentifier("newNoteNewFolderButton")
    }

    private func folderBreadcrumb(_ folder: NewNoteFolder) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.left")
            if folder.isRoot {
                Text("Recent folders")
            } else {
                let ancestors = folder.path.components(separatedBy: " › ").dropLast()
                Text((["Library"] + Array(ancestors)).joined(separator: " › ") + " ›")
                Text(folder.name).foregroundStyle(NotoTheme.ink)
            }
        }
        .font(.subheadline).foregroundStyle(NotoTheme.muted).lineLimit(1)
    }

    private func load() async {
        let root = vaultURL.standardizedFileURL
        let rows = await Task.detached(priority: .userInitiated) { (try? SidebarTreeLoader().loadRows(rootURL: root)) ?? [] }.value
        folders = NewNoteFolder.options(from: rows, vaultURL: root)
        recentFolders = NewNoteFolder.recent(folders, notes: AddToCandidates.recent(from: rows, vaultURL: root))
        if selectedID == nil { selectedID = recentFolders.first?.id ?? folders.first?.id }
    }

    private func createFolder() async {
        let parent = browsing?.url ?? selected?.url ?? vaultURL
        let root = vaultURL
        let name = folderName
        let result = await Task.detached(priority: .userInitiated) { Result { try DigestFolderCreation.create(named: name, in: parent, vaultURL: root) } }.value
        switch result {
        case .success(let url): await load(); selectedID = url; browsingID = url
        case .failure(let error): errorMessage = error.localizedDescription
        }
    }
}
