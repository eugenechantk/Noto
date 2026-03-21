import SwiftUI
import NotoVault

struct VaultNoteEditorView: View {
    @StateObject private var viewModel: NoteEditorViewModel
    @FocusState private var isEditorFocused: Bool
    var onDismiss: (() -> Void)?

    init(note: NoteFile, vault: VaultManager, onDismiss: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: NoteEditorViewModel(note: note, vault: vault))
        self.onDismiss = onDismiss
    }

    var body: some View {
        TextEditor(text: $viewModel.content)
            .font(.body)
            .padding(.horizontal, 4)
            .focused($isEditorFocused)
            .navigationTitle(viewModel.content.isEmpty ? "New Note" : "")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                isEditorFocused = true
            }
            .onDisappear {
                viewModel.save()
                onDismiss?()
            }
            .onChange(of: viewModel.content) { _, _ in
                viewModel.save()
            }
    }
}
