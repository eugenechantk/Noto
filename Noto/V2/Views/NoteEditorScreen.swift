import SwiftUI
import Combine
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NoteEditorScreen")

struct NoteEditorScreen: View {
    @ObservedObject var store: MarkdownNoteStore
    var isNew: Bool = false

    @State private var note: MarkdownNote
    @State private var content: String = ""
    @State private var hasLoaded = false
    @State private var saveTask: Task<Void, Never>?

    init(store: MarkdownNoteStore, note: MarkdownNote, isNew: Bool = false) {
        self.store = store
        self.isNew = isNew
        _note = State(initialValue: note)
    }

    var body: some View {
        MarkdownEditorView(text: $content, autoFocus: isNew) { _ in
            scheduleSave()
        }
        .navigationTitle(MarkdownNote.titleFrom(content))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !hasLoaded {
                content = store.readContent(of: note)
                hasLoaded = true
            }
        }
        .onDisappear {
            saveTask?.cancel()
            note = store.save(content: content, for: note)
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            note = store.save(content: content, for: note)
        }
    }
}
