import SwiftUI
import NotoVault

struct VaultNotesListView: View {
    @StateObject private var viewModel: NotesListViewModel
    @State private var selectedNote: NoteFile?
    @State private var navigateToNote: NoteFile?

    private let vault: VaultManager

    init(vault: VaultManager) {
        self.vault = vault
        _viewModel = StateObject(wrappedValue: NotesListViewModel(vault: vault))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.notes) { note in
                    Button {
                        navigateToNote = note
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(note.modifiedAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        viewModel.deleteNote(viewModel.notes[index])
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if let note = viewModel.createNote() {
                            navigateToNote = note
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(item: $navigateToNote) { note in
                VaultNoteEditorView(note: note, vault: vault, onDismiss: {
                    viewModel.loadNotes()
                })
            }
            .onAppear {
                viewModel.loadNotes()
            }
        }
    }
}
