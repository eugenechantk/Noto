//
//  ContentView.swift
//  Noto
//
//  Created by Eugene Chan on 1/8/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Block.updatedAt, order: .reverse)
    private var allBlocks: [Block]

    private var rootBlock: Block? {
        allBlocks.first { $0.parent == nil && !$0.isArchived }
    }

    @State private var editableContent: String = ""
    @State private var hasLoaded = false

    var body: some View {
        NoteTextEditor(text: $editableContent)
            .ignoresSafeArea(.keyboard)
            .onAppear {
                loadContent()
            }
            .onChange(of: editableContent) {
                syncContent()
            }
    }

    private func loadContent() {
        guard !hasLoaded else { return }
        hasLoaded = true

        if let block = rootBlock {
            editableContent = block.content
        } else {
            // Create the single root block
            let block = Block(content: "", sortOrder: 1.0)
            modelContext.insert(block)
        }
    }

    private func syncContent() {
        guard hasLoaded else { return }

        if let block = rootBlock {
            if block.content != editableContent {
                block.content = editableContent
                block.updatedAt = Date()
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Block.self, BlockLink.self, Tag.self, BlockTag.self, MetadataField.self, BlockEmbedding.self, SearchIndex.self], inMemory: true)
}
