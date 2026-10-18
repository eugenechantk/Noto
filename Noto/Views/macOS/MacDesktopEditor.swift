#if os(macOS)
import AppKit
import SwiftUI
import NotoVault

struct MacDesktopEditor: View {
    @Bindable var model: MacDesktopModel
    let note: MarkdownNote
    var fileWatcher: VaultFileWatcher?
    var hostingWindow: NSWindow?
    @Binding var inspectorVisible: Bool
    var single: Bool
    var onOpenPath: (String) -> Void
    var header: AnyView?
    var focusEditorOnOpen: Bool
    var focusMode: Bool
    var textColumnWidth: CGFloat?
    var minimumTextInset: CGFloat
    var showsMetadataProperties: Bool
    @State private var session: NoteEditorSession
    @State private var findVisible = false
    @State private var findQuery = ""
    @State private var findStatus = EditorFindStatus()
    @State private var findRequest: EditorFindNavigationRequest?
    @State private var findSequence = 0
    @State private var count = WordCounter.Count(words: 0, characters: 0)
    @State private var countTask: Task<Void, Never>?
    @State private var showProperties = false
    @Environment(\.openWindow) private var openWindow

    init(model: MacDesktopModel, note: MarkdownNote, fileWatcher: VaultFileWatcher?, hostingWindow: NSWindow?, inspectorVisible: Binding<Bool>, single: Bool, onOpenPath: @escaping (String) -> Void, header: AnyView? = nil, focusEditorOnOpen: Bool = false, focusMode: Bool = false, textColumnWidth: CGFloat? = nil, minimumTextInset: CGFloat = 32, showsMetadataProperties: Bool = true) {
        self.model = model; self.note = note; self.fileWatcher = fileWatcher; self.hostingWindow = hostingWindow
        _inspectorVisible = inspectorVisible; self.single = single; self.onOpenPath = onOpenPath; self.header = header; self.focusEditorOnOpen = focusEditorOnOpen
        self.focusMode = focusMode
        self.textColumnWidth = textColumnWidth; self.minimumTextInset = minimumTextInset; self.showsMetadataProperties = showsMetadataProperties
        _session = State(initialValue: NoteEditorSession(store: MarkdownNoteStore(directoryURL: note.fileURL.deletingLastPathComponent(), vaultRootURL: model.vaultURL, autoload: false), note: note, isNew: model.selectedIsNew))
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if let header { header }
                if findVisible {
                    MacDesktopFindBar(query: $findQuery, status: findStatus, onNavigate: navigateFind, onClose: { findVisible = false; findQuery = "" })
                }
                EditorContentView(session: session, isFindVisible: $findVisible, findQuery: $findQuery,
                    findNavigationRequest: $findRequest, findStatus: $findStatus,
                    pageMentionProvider: { session.store.pageMentionDocuments(matching: $0, excluding: session.note.fileURL) },
                    onOpenDocumentLink: onOpenPath, onOpenDocumentLinkInNewWindow: { openWindow(id: "main", value: $0) },
                    onFindNavigate: navigateFind, showsFindBar: false, focusEditorOnOpen: focusEditorOnOpen, usesFocusLayout: focusMode,
                    dailyNoteDate: model.destination == .daily ? model.currentLibraryNote?.dailyDate() : nil,
                    textColumnWidth: textColumnWidth, minimumTextInset: minimumTextInset, showsMetadataProperties: showsMetadataProperties,
                    documentBreadcrumb: single && !focusMode && model.destination != .daily ? model.currentLibraryNote?.breadcrumb : nil,
                    documentTitleSize: (textColumnWidth ?? 640) <= 500 && model.destination != .daily && (!inspectorVisible || single) ? 28 : 30)
                HStack {
                    if focusMode {
                        Spacer()
                        Text("\(count.words) words"); Text("·")
                        Text("\(max(1, Int(ceil(Double(count.words) / 220)))) min read"); Text("·")
                        Text(session.hasPendingLocalEdits ? "Saving…" : "Saved")
                        Spacer()
                    } else {
                    Text(single ? session.note.fileURL.lastPathComponent : session.store.vaultRelativePath(for: session.note.fileURL) ?? session.note.fileURL.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 12)
                    Text("\(count.words) words · \(session.hasPendingLocalEdits ? "Saving…" : "Saved")")
                    }
                }.font(.system(size: 11)).foregroundStyle(MacDesktopStyle.secondary).padding(.horizontal, 16).frame(height: 30)
                    .overlay(alignment: .top) { MacDesktopStyle.separator.frame(height: 1) }.accessibilityElement(children: .contain).accessibilityIdentifier("macEditorStatus")
            }
            if inspectorVisible && !single && !focusMode { inspector.frame(width: 288).padding(.trailing, 8).padding(.vertical, 8) }
        }
        .overlay(alignment: .trailing) {
            if inspectorVisible && single && !focusMode {
                ZStack(alignment: .trailing) {
                    Color.black.opacity(0.25).onTapGesture { inspectorVisible = false }
                    inspector.frame(width: 300).padding(8).shadow(radius: 16)
                }
            }
        }
        .task {
            await session.loadNoteContent()
            guard !Task.isCancelled else { return }
            applyFindRequest()
            applyPendingMove()
            applyPendingDuplicate()
        }
        .onAppear { model.activeEditorID = session.note.id }
        .onChange(of: note) { _, newNote in session.replaceNoteFromParent(newNote) }
        .onChange(of: session.hasLoaded, initial: true) { _, loaded in model.documentReady = loaded; if loaded { applyPendingMove(); applyPendingDuplicate() } }
        .onChange(of: model.pendingMove) { _, _ in applyPendingMove() }
        .onChange(of: model.pendingDuplicate) { _, _ in applyPendingDuplicate() }
        .onChange(of: session.content, initial: true) { _, content in
            model.document = content
            countTask?.cancel()
            countTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                let updated = await Task.detached { WordCounter().count(in: content) }.value
                guard !Task.isCancelled else { return }; count = updated
            }
        }
        .onChange(of: session.note) { _, updated in model.update(updated) }
        .onChange(of: model.findRequest) { _, _ in applyFindRequest() }
        .onChange(of: fileWatcher?.changeCount) { _, _ in session.handleExternalChange(changedURL: fileWatcher?.lastChangedFileURL) }
        .onReceive(NotificationCenter.default.publisher(for: NoteSyncCenter.notificationName)) { notification in
            if let snapshot = notification.object as? NoteSyncSnapshot { session.handleRemoteSnapshot(snapshot) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NoteEditorCommands.showFind)) { notification in
            guard NotoCommandTarget.matches(notification, window: hostingWindow) else { return }; findVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NoteEditorCommands.showMoveNote)) { notification in
            guard NotoCommandTarget.matches(notification, window: hostingWindow) else { return }; model.palette = .move
        }
        .onReceive(NotificationCenter.default.publisher(for: MacDesktopModel.editorAction)) { notification in
            guard let owner = notification.object as? MacDesktopModel, owner === model,
                  let id = notification.userInfo?["noteID"] as? UUID, id == session.note.id,
                  let action = notification.userInfo?["action"] as? String else { return }
            switch action {
            case "rename":
                guard session.hasLoaded, let title = notification.userInfo?["title"] as? String else { model.error = "Wait for the note to finish loading."; return }
                session.applyExternalContentEdit(VaultMarkdown.renamingTitle(in: session.content, to: title))
                let renamed = session.store.renameFileIfNeeded(for: session.note)
                session.replaceNoteFromParent(renamed)
                model.update(renamed); model.scheduleRefresh()
            case "move":
                guard let url = notification.userInfo?["url"] as? URL else { return }
                move(to: url)
            case "pin":
                guard session.hasLoaded else { model.error = "Wait for the note to finish loading."; return }
                let pinned = NoteFrontmatter.value(for: "pinned", in: session.content) == "true"
                session.applyExternalContentEdit(NoteFrontmatter.setting("pinned", to: pinned ? "false" : "true", in: session.content))
            case "trash":
                session.persistFinalSnapshotIfNeeded(isExternallyDeleting: false)
                do {
                    try FileManager.default.trashItem(at: session.note.fileURL, resultingItemURL: nil)
                    session.markDeleting(); model.deletingNoteID = session.note.id; model.selectedNote = nil; model.scheduleRefresh()
                } catch { model.error = error.localizedDescription }
            default: break
            }
        }
        .onDisappear {
            if model.activeEditorID == session.note.id { model.activeEditorID = nil }
            session.cancelBackgroundWork(); countTask?.cancel()
            session.persistFinalSnapshotIfNeeded(isExternallyDeleting: model.deletingNoteID == session.note.id)
            if model.deletingNoteID == session.note.id { model.deletingNoteID = nil }
            model.scheduleRefresh()
        }
        .sheet(isPresented: $showProperties) {
            MacPropertiesForm(session: session, onClose: { showProperties = false }, onMoveFolder: { showProperties = false; model.palette = .move })
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("macNoteEditor")
    }
    private var inspector: some View {
        MacDesktopInspector(session: session, library: model.library, count: count,
            onClose: { inspectorVisible = false }, onProperties: { showProperties = true },
            onHeading: { heading in findQuery = heading; findVisible = true }, onOpen: { model.openURL($0) })
    }
    private func applyFindRequest() {
        if let query = model.findQuery, !query.isEmpty { findQuery = query; findVisible = true }
    }
    private func applyPendingMove() {
        guard session.hasLoaded, let move = model.pendingMove, move.noteID == session.note.id else { return }
        model.pendingMove = nil
        self.move(to: move.directory)
    }
    private func applyPendingDuplicate() {
        guard session.hasLoaded, model.pendingDuplicate == session.note.id, let note = model.currentLibraryNote else { return }
        model.pendingDuplicate = nil
        model.document = session.content; model.documentReady = true
        model.duplicate(note)
    }
    private func move(to directory: URL) {
        let moved = session.moveNote(to: directory)
        guard moved.fileURL.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path else { model.error = "The note could not be moved."; return }
        model.destination = .folder(directory); model.open(moved); model.palette = nil; model.scheduleRefresh()
    }
    private func navigateFind(_ direction: EditorFindNavigationDirection) {
        findSequence += 1
        findRequest = EditorFindNavigationRequest(id: findSequence, direction: direction)
    }
}

private struct MacDesktopFindBar: View {
    @Binding var query: String
    var status: EditorFindStatus
    var onNavigate: (EditorFindNavigationDirection) -> Void
    var onClose: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(MacDesktopStyle.secondary)
            MacDesktopQueryField(text: $query, placeholder: "Find in note", accessibilityIdentifier: "editor_find_field", fontSize: 12) { key, _ in
                switch key {
                case .escape: onClose()
                case .enter, .down: onNavigate(.next)
                case .up: onNavigate(.previous)
                default: return false
                }
                return true
            }.frame(height: 26)
            Text(status.matchCount > 0 ? "\((status.selectedMatchIndex ?? 0) + 1) of \(status.matchCount)" : "No matches")
                .foregroundStyle(MacDesktopStyle.secondary).accessibilityIdentifier("editor_find_count")
            Button { onNavigate(.previous) } label: { Image(systemName: "chevron.up") }
                .disabled(status.matchCount == 0).accessibilityLabel("Previous occurrence").accessibilityIdentifier("editor_find_previous_button")
            Button { onNavigate(.next) } label: { Image(systemName: "chevron.down") }
                .disabled(status.matchCount == 0).accessibilityLabel("Next occurrence").accessibilityIdentifier("editor_find_next_button")
            Button("Done", action: onClose).keyboardShortcut(.cancelAction).accessibilityIdentifier("editor_find_close_button")
        }.buttonStyle(.plain).font(.system(size: 12)).padding(.horizontal, 16).frame(height: 42)
            .background(.white.opacity(0.035)).overlay(alignment: .bottom) { MacDesktopStyle.separator.frame(height: 1) }
            .accessibilityElement(children: .contain).accessibilityIdentifier("macFindBar")
    }
}

struct MacDesktopInspector: View {
    @Bindable var session: NoteEditorSession
    var library: VaultLibrarySnapshot?
    var count: WordCounter.Count
    var onClose: () -> Void
    var onProperties: () -> Void
    var onHeading: (String) -> Void
    var onOpen: (URL) -> Void
    @State private var tab = "Info"

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $tab) { Text("Info").tag("Info"); Text("Outline").tag("Outline") }
                .pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("macInspectorTabs")
                .padding(.horizontal, 10).frame(height: 48)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if tab == "Info" {
                        properties
                        Divider().overlay(MacDesktopStyle.separator)
                        linkedFrom
                        Divider().overlay(MacDesktopStyle.separator)
                        fileDetails
                    } else {
                        section("On this page")
                        ForEach(VaultLibraryNote.outline(of: session.content)) { heading in
                            Button { onHeading(heading.title) } label: {
                                Text(heading.title).font(.system(size: 12)).padding(.leading, CGFloat(max(0, heading.level - 1)) * 12)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                            }.buttonStyle(.plain).accessibilityIdentifier("macOutline_\(heading.line)")
                        }
                    }
                }.padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 14)
            }
            Spacer(minLength: 0)
        }.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08)))
            .accessibilityElement(children: .contain).accessibilityIdentifier("macInspector")
    }
    private var properties: some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Properties").padding(.bottom, 6)
            ForEach(fields) { field in
                HStack(spacing: 8) {
                    Text(field.key == "updated" ? "Modified" : field.key.capitalized).foregroundStyle(MacDesktopStyle.secondary)
                    Spacer(minLength: 4)
                    propertyValue(field)
                }.font(.system(size: 12.5)).frame(minHeight: field.key == "tags" || field.key == "status" ? 28 : 26)
            }
            Button("+ Add Property", action: onProperties).buttonStyle(.plain).font(.system(size: 12.5)).foregroundStyle(MacDesktopStyle.icon)
                .padding(.top, 4).accessibilityIdentifier("macInspectorAddProperty")
        }
    }
    private var linkedFrom: some View {
        VStack(alignment: .leading, spacing: 6) {
            section("Linked from · \(backlinks.count)").padding(.bottom, 2)
            ForEach(backlinks) { note in
                Button { onOpen(note.fileURL) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(note.title).fontWeight(.semibold)
                            Text("· " + note.breadcrumb).foregroundStyle(MacDesktopStyle.secondary).lineLimit(1)
                        }.font(.system(size: 12.5))
                        Text(VaultLibraryNote.plainTextSnippet(from: note.preview))
                            .font(.system(size: 12)).foregroundStyle(MacDesktopStyle.secondary).lineLimit(2)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 8)
                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).accessibilityIdentifier("macBacklink_" + note.id.uuidString)
            }
        }
    }
    private var fileDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            section("File").padding(.bottom, 2)
            Text(session.store.vaultRelativePath(for: session.note.fileURL) ?? session.note.fileURL.lastPathComponent)
                .font(.system(size: 12.5)).textSelection(.enabled)
            Text("\(count.words) words · \(count.characters) characters · \(max(1, count.words / 200)) min read")
                .font(.system(size: 12)).foregroundStyle(MacDesktopStyle.secondary)
            HStack(spacing: 6) {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([session.note.fileURL]) }.accessibilityIdentifier("macRevealInFinder")
                Button("Copy Link") {
                    guard let path = session.store.vaultRelativePath(for: session.note.fileURL), let url = NotoDeepLink.webURL(vaultRelativePath: path) else { return }
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }.accessibilityIdentifier("macCopyNoteLink")
            }.buttonStyle(.bordered).controlSize(.small).font(.system(size: 12)).padding(.top, 6)
        }
    }
    @ViewBuilder private func propertyValue(_ field: EditableFrontmatterField) -> some View {
        if field.key.lowercased() == "status" {
            Text(field.displayValue).foregroundStyle(Color.yellow.opacity(0.85)).padding(.horizontal, 7).padding(.vertical, 2)
                .background(Color.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
        } else {
        switch NotePropertyClassifier.kind(key: field.key, value: field.value) {
        case .date:
            if let date = NotePropertyClassifier.date(from: field.value) {
                Text(date.formatted(date: .abbreviated, time: .shortened)).lineLimit(2)
            } else { Text(field.displayValue).lineLimit(2) }
        case .tags:
            HStack(spacing: 4) {
                ForEach(NotePropertyClassifier.parseTags(field.value), id: \.self) { tag in
                    Text(tag).padding(.horizontal, 7).padding(.vertical, 2).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        default:
            Text(field.displayValue).textSelection(.enabled).lineLimit(3)
        }
        }
    }
    private var fields: [EditableFrontmatterField] { (EditableFrontmatterDocument(markdown: session.content)?.fields ?? []).filter { $0.key != "id" } }
    private var backlinks: [VaultLibraryNote] {
        guard let note = library?.notes.first(where: { $0.id == session.note.id }) else { return [] }
        return library?.backlinks(to: note) ?? []
    }
    private func section(_ title: String) -> some View { Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(MacDesktopStyle.secondary) }
}
#endif
