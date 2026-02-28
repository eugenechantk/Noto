//
//  ContentView.swift
//  Noto
//
//  Created by Eugene Chan on 1/8/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Query(sort: \Block.updatedAt, order: .reverse)
    private var allBlocks: [Block]

    var body: some View {
        NavigationStack {
            NotesListView()
                .navigationTitle("Noto")
                .navigationDestination(for: UUID.self) { blockId in
                    if let block = allBlocks.first(where: { $0.id == blockId }) {
                        NoteEditorView(note: block)
                    }
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Block.self, BlockLink.self, Tag.self, BlockTag.self, MetadataField.self, BlockEmbedding.self, SearchIndex.self], inMemory: true)
}
