//
//  NotesListView.swift
//  Noto
//
//  Displays all notes sorted by modification date.
//  Mimics the Simple-Notes list pattern.
//

import SwiftUI
import SwiftData

struct NotesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Block.updatedAt, order: .reverse)
    private var allBlocks: [Block]

    private var notes: [Block] {
        allBlocks.filter { $0.parent == nil && !$0.isArchived }
    }

    var body: some View {
        List {
            ForEach(notes, id: \.id) { note in
                NavigationLink(value: note.id) {
                    NoteRow(note: note)
                }
            }
            .onDelete(perform: deleteNotes)
        }
        .listStyle(.plain)
        .overlay {
            if notes.isEmpty {
                ContentUnavailableView("No Notes", systemImage: "note.text", description: Text("Tap + to create a note."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: createNote) {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private func createNote() {
        let newBlock = Block(
            content: "",
            sortOrder: Block.sortOrderForAppending(to: notes)
        )
        modelContext.insert(newBlock)
    }

    private func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            let note = notes[index]
            note.isArchived = true
            note.updatedAt = Date()
        }
    }
}

// MARK: - Note Row

private struct NoteRow: View {
    let note: Block

    private var title: String {
        let firstLine = note.content.components(separatedBy: "\n").first ?? ""
        return firstLine.isEmpty ? "New Note" : firstLine
    }

    private var preview: String {
        let lines = note.content.components(separatedBy: "\n")
        if lines.count > 1 {
            return lines.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 8) {
                Text(note.updatedAt.relativeDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !preview.isEmpty {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Date Helper

extension Date {
    var relativeDescription: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: self)
    }
}
