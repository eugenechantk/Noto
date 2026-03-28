//
//  NotesListView.swift
//  Noto
//
//  List of all root-level notes. Tapping a note pushes to NoteEditorView.
//  Inspired by Simple-Notes (github.com/pmattos/Simple-Notes).
//

import SwiftUI
import SwiftData
import os.log
import NotoModels
import NotoCore

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NotesListView")

struct NotesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(filter: #Predicate<Block> { $0.parent == nil && !$0.isArchived },
           sort: \Block.updatedAt, order: .reverse) private var notes: [Block]

    var body: some View {
        List {
            ForEach(notes) { note in
                NavigationLink(value: note) {
                    NoteRow(note: note)
                }
                .listRowBackground(backgroundColor)
                .listRowSeparatorTint(separatorColor)
            }
            .onDelete(perform: deleteNotes)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(backgroundColor)
        .navigationTitle("Notes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: createNote) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
        }
    }

    private func createNote() {
        let maxSort = (notes.map(\.sortOrder).max() ?? 0) + 1
        let block = Block(content: "", sortOrder: maxSort)
        modelContext.insert(block)
        logger.debug("[createNote] created new root block")
    }

    private func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            let note = notes[index]
            modelContext.delete(note)
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.07, green: 0.07, blue: 0.07)
            : .white
    }

    private var separatorColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.1)
            : Color.black.opacity(0.1)
    }
}

// MARK: - Note Row

private struct NoteRow: View {
    let note: Block
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(labelPrimary)
                .lineLimit(1)

            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(labelSecondary)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
    }

    private var title: String {
        let plain = PlainTextExtractor.plainText(from: note.content)
        return plain.isEmpty ? "New Note" : plain
    }

    private var subtitle: String {
        let date = RelativeDateFormatter.string(for: note.updatedAt)
        let childCount = note.children.count
        if childCount > 0 {
            return "\(date) · \(childCount) item\(childCount == 1 ? "" : "s")"
        }
        return date
    }

    private var labelPrimary: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.9)
            : Color(red: 0.1, green: 0.1, blue: 0.1)
    }

    private var labelSecondary: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.45)
            : Color(red: 0.45, green: 0.45, blue: 0.45)
    }
}

// MARK: - Relative Date Formatter

private enum RelativeDateFormatter {
    private static let formatter: Foundation.RelativeDateTimeFormatter = {
        let f = Foundation.RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    static func string(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return formatter.localizedString(for: date, relativeTo: Date())
        }
    }
}
