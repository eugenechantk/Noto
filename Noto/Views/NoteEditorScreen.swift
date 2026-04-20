import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NoteEditorScreen")

struct NoteEditorScreen: View {
    var store: MarkdownNoteStore
    var isNew: Bool = false
    var fileWatcher: VaultFileWatcher?
    var onDelete: (() -> Void)? = nil
    var onOpenTodayNote: (() -> Void)? = nil
    var onCreateRootNote: (() -> Void)? = nil
    var onTapBreadcrumbLevel: ((URL) -> Void)? = nil
    var showsInlineBackButton = true
    var showsNavigationChrome = true
    private var externallyDeletingNoteID: Binding<UUID?>?

    @State private var session: NoteEditorSession
    @State private var showDeleteConfirmation = false

    init(
        store: MarkdownNoteStore,
        note: MarkdownNote,
        isNew: Bool = false,
        fileWatcher: VaultFileWatcher? = nil,
        onDelete: (() -> Void)? = nil,
        onOpenTodayNote: (() -> Void)? = nil,
        onCreateRootNote: (() -> Void)? = nil,
        onTapBreadcrumbLevel: ((URL) -> Void)? = nil,
        externallyDeletingNoteID: Binding<UUID?>? = nil,
        showsInlineBackButton: Bool = true,
        showsNavigationChrome: Bool = true
    ) {
        self.store = store
        self.isNew = isNew
        self.fileWatcher = fileWatcher
        self.onDelete = onDelete
        self.onOpenTodayNote = onOpenTodayNote
        self.onCreateRootNote = onCreateRootNote
        self.onTapBreadcrumbLevel = onTapBreadcrumbLevel
        self.externallyDeletingNoteID = externallyDeletingNoteID
        self.showsInlineBackButton = showsInlineBackButton
        self.showsNavigationChrome = showsNavigationChrome
        _session = State(initialValue: NoteEditorSession(store: store, note: note, isNew: isNew))
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var session = session
        Group {
            if session.downloadFailed {
                ContentUnavailableView(
                    "Download Failed",
                    systemImage: "exclamationmark.icloud",
                    description: Text("Could not download this note from iCloud. Check your connection and try again.")
                )
            } else if session.isDownloading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Downloading from iCloud...")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.background)
            } else {
                VStack(spacing: 0) {
                    if session.pendingRemoteSnapshot != nil {
                        remoteUpdateBanner
                    }
                    TextKit2EditorView(text: $session.content, autoFocus: session.isNew, onTextChange: session.handleEditorChange)
                }
                .background(AppTheme.background)
                #if os(iOS)
                .ignoresSafeArea(edges: [.top, .bottom])
                #endif
            }
        }
        .background(AppTheme.background)
        .foregroundStyle(AppTheme.primaryText)
        .tint(AppTheme.primaryText)
        #if os(iOS)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if showsNavigationChrome {
                if showsInlineBackButton {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { dismiss() }) {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityIdentifier("back_button")
                    }
                }

                ToolbarItem(placement: .principal) {
                    BreadcrumbBar(
                        vaultRootURL: store.vaultRootURL,
                        noteFileURL: session.note.fileURL,
                        onTapLevel: onTapBreadcrumbLevel
                    )
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                            Label("Delete Note", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityIdentifier("more_menu_button")
                }
            }
        }
        .notoAppBottomToolbar(
            onOpenTodayNote: showsNavigationChrome ? onOpenTodayNote : nil,
            onCreateRootNote: showsNavigationChrome ? onCreateRootNote : nil
        )
        #elseif os(macOS)
        .navigationTitle(MarkdownNote.titleFrom(session.content))
        .toolbar {
            if showsNavigationChrome {
                ToolbarItem(placement: .automatic) {
                    Button(action: { NoteEditorCommands.requestToggleStrikethrough() }) {
                        Label("Strikethrough", systemImage: "strikethrough")
                    }
                    .accessibilityIdentifier("toggle_strikethrough_button")
                    .keyboardShortcut("x", modifiers: [.command, .shift])
                    .help("Strikethrough (Shift-Command-X)")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                        Label("Delete Note", systemImage: "trash")
                    }
                    .accessibilityIdentifier("delete_note_button")
                    .keyboardShortcut(.delete, modifiers: [.command])
                }
            }
        }
        #endif
        .task {
            guard !session.hasLoaded else { return }
            await session.loadNoteContent()
        }
        .onDisappear {
            session.cancelBackgroundWork()
            session.persistFinalSnapshotIfNeeded(isExternallyDeleting: externallyDeletingNoteID?.wrappedValue == session.note.id)
            if externallyDeletingNoteID?.wrappedValue == session.note.id {
                externallyDeletingNoteID?.wrappedValue = nil
            }
        }
        .onChange(of: fileWatcher?.changeCount) { _, _ in
            session.handleExternalChange(changedURL: fileWatcher?.lastChangedFileURL)
        }
        .onReceive(NotificationCenter.default.publisher(for: NoteSyncCenter.notificationName)) { notification in
            guard let snapshot = notification.object as? NoteSyncSnapshot else { return }
            session.handleRemoteSnapshot(snapshot)
        }
        .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirmation) {
            Button("Delete Note", role: .destructive) {
                deleteCurrentNote()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var remoteUpdateBanner: some View {
        HStack(spacing: 12) {
            Label("Updated in another window", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button("Keep Mine") {
                session.discardRemoteConflict()
            }
            Button("Reload") {
                session.reloadRemoteSnapshot()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.separator)
                .frame(height: 1)
        }
    }

    private func deleteCurrentNote() {
        session.markDeleting()
        let noteToDelete = session.note
        guard session.store.deleteNote(noteToDelete) else {
            session.finishDeleteAttempt()
            return
        }
        onDelete?()
        dismiss()
    }
}

#if os(iOS)

/// Horizontally scrollable breadcrumb showing the folder chain from vault root
/// down to the note's parent directory. Replaces the navigation title.
private struct BreadcrumbBar: View {
    let vaultRootURL: URL
    let noteFileURL: URL
    var onTapLevel: ((URL) -> Void)? = nil

    @State private var isOverflowing = false

    private static let levelMaxWidth: CGFloat = 140

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.mutedText)
                    }
                    levelLabel(level, isCurrent: index == levels.count - 1)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 24)
        }
        .defaultScrollAnchor(.trailing)
        .scrollClipDisabled()
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentSize.width > geometry.containerSize.width
        } action: { _, newValue in
            isOverflowing = newValue
        }
        .mask(maskGradient)
        .accessibilityIdentifier("breadcrumb_bar")
    }

    private var maskGradient: LinearGradient {
        let stops: [Gradient.Stop] = isOverflowing
            ? [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1)
            ]
            : [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 1)
            ]
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    @ViewBuilder
    private func levelLabel(_ level: Level, isCurrent: Bool) -> some View {
        let text = Text(level.name)
            .font(.subheadline.weight(isCurrent ? .semibold : .medium))
            .foregroundStyle(isCurrent ? AnyShapeStyle(AppTheme.primaryText) : AnyShapeStyle(AppTheme.mutedText))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: Self.levelMaxWidth, alignment: .leading)

        if onTapLevel == nil {
            text
        } else {
            Button {
                onTapLevel?(level.url)
            } label: {
                text
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCurrent ? "\(level.name), current note location" : level.name)
        }
    }

    private struct Level {
        let name: String
        let url: URL
    }

    /// Folder chain from vault root → note's parent directory.
    /// Excludes the note's filename. Falls back to a single "Vault" level for notes at the root.
    private var levels: [Level] {
        let noteParent = noteFileURL.deletingLastPathComponent().standardizedFileURL
        let root = vaultRootURL.standardizedFileURL
        let rootName = root.lastPathComponent.isEmpty ? "Vault" : root.lastPathComponent

        let rootComps = root.pathComponents
        let parentComps = noteParent.pathComponents
        guard parentComps.count >= rootComps.count,
              Array(parentComps.prefix(rootComps.count)) == rootComps else {
            return [Level(name: rootName, url: root)]
        }
        let relative = Array(parentComps.dropFirst(rootComps.count))
        var result: [Level] = [Level(name: rootName, url: root)]
        var currentURL = root
        for component in relative {
            currentURL = currentURL.appendingPathComponent(component)
            result.append(Level(name: component, url: currentURL))
        }
        return result
    }
}

#endif
