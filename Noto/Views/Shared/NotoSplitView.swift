import SwiftUI

struct NotoSplitView: View {
    var store: MarkdownNoteStore
    var fileWatcher: VaultFileWatcher?

    @Binding var selectedNote: MarkdownNote?
    @Binding var selectedNoteStore: MarkdownNoteStore?
    @Binding var selectedIsNew: Bool
    @Binding var externallyDeletingNoteID: UUID?

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            NotoSidebarView(
                rootStore: store,
                fileWatcher: fileWatcher,
                selectedNote: $selectedNote,
                selectedNoteStore: $selectedNoteStore,
                selectedIsNew: $selectedIsNew,
                externallyDeletingNoteID: $externallyDeletingNoteID
            )
        } detail: {
            detailView
                .notoBackgroundExtension()
        }
        .navigationTitle("Noto")
        #if os(iOS)
        .navigationSplitViewStyle(.balanced)
        #endif
    }

    @ViewBuilder
    private var detailView: some View {
        if let selectedNote, let selectedNoteStore {
            NoteEditorScreen(
                store: selectedNoteStore,
                note: selectedNote,
                isNew: selectedIsNew,
                fileWatcher: fileWatcher,
                onDelete: {
                    self.selectedNote = nil
                    self.selectedNoteStore = nil
                    self.selectedIsNew = false
                },
                externallyDeletingNoteID: $externallyDeletingNoteID,
                showsInlineBackButton: false,
                showsNavigationChrome: false
            )
            .id(selectedNote.id)
        } else {
            Text("Select a note")
                .font(.title2)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.background)
        }
    }
}

private extension View {
    @ViewBuilder
    func notoBackgroundExtension() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.backgroundExtensionEffect()
        } else {
            self
        }
    }
}
