//
//  NoteEditorView.swift
//  Noto
//
//  Full-screen text editor for a single note.
//  Uses TextKit-based NoteTextEditor for markdown display.
//

import SwiftUI
import SwiftData

struct NoteEditorView: View {
    @Bindable var note: Block
    @State private var editableContent: String = ""
    @State private var hasLoaded = false

    var body: some View {
        NoteTextEditor(text: $editableContent)
            .navigationTitle(noteTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Checklist") {
                        // Placeholder for checklist insertion
                    }
                }
            }
            .onAppear {
                if !hasLoaded {
                    editableContent = note.content
                    hasLoaded = true
                }
            }
            .onChange(of: editableContent) {
                note.content = editableContent
                note.updatedAt = Date()
            }
    }

    private var noteTitle: String {
        let firstLine = editableContent.components(separatedBy: "\n").first ?? ""
        return firstLine.isEmpty ? "New Note" : firstLine
    }
}
