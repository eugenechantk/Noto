import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NoteEditorScreen")

struct NoteEditorScreen: View {
    @ObservedObject var store: MarkdownNoteStore
    let note: MarkdownNote
    var isNew: Bool = false

    @State private var content: String = ""
    @State private var hasLoaded = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        MarkdownEditorView(text: $content, autoFocus: isNew) { newContent in
            store.save(content: newContent, for: note)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .navigationTitle(MarkdownNote.titleFrom(content))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !hasLoaded {
                content = store.readContent(of: note)
                hasLoaded = true
            }
        }
    }
}
