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
    @Query(sort: \Block.sortOrder)
    private var allBlocks: [Block]

    private var rootBlocks: [Block] {
        allBlocks.filter { $0.parent == nil && !$0.isArchived }
    }

    @State private var editableContent: String = ""
    @State private var hasLoaded = false

    @State private var showDebug = false
    @State private var isSyncing = false

    var body: some View {
        ZStack(alignment: .bottom) {
            NoteTextEditor(text: $editableContent)
                .ignoresSafeArea(.keyboard)
                .onAppear {
                    loadContent()
                }
                .onChange(of: editableContent) {
                    syncContent()
                }

            if showDebug {
                DebugPanelView(blocks: rootBlocks)
                    .transition(.move(edge: .bottom))
            }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer()
                Button {
                    withAnimation { showDebug.toggle() }
                } label: {
                    Image(systemName: showDebug ? "ladybug.fill" : "ladybug")
                        .font(.caption)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.trailing, 12)
            }
            .frame(height: 32)
        }
    }

    private func loadContent() {
        guard !hasLoaded else { return }
        hasLoaded = true

        let blocks = rootBlocks
        if blocks.isEmpty {
            let block = Block(content: "", sortOrder: 1.0)
            modelContext.insert(block)
        } else {
            editableContent = blocks.map(\.content).joined(separator: "\n")
        }
    }

    private func syncContent() {
        guard hasLoaded, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let lines = editableContent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks = rootBlocks

        // Update existing blocks
        for i in 0..<min(lines.count, blocks.count) {
            if blocks[i].content != lines[i] {
                blocks[i].content = lines[i]
                blocks[i].updatedAt = Date()
            }
        }

        // Create new blocks for extra lines
        if lines.count > blocks.count {
            for i in blocks.count..<lines.count {
                let sortOrder = (blocks.last?.sortOrder ?? 0) + Double(i - blocks.count + 1)
                let block = Block(content: lines[i], sortOrder: sortOrder)
                modelContext.insert(block)
                blocks.append(block)
            }
        }

        // Delete excess blocks
        if blocks.count > lines.count {
            for i in stride(from: blocks.count - 1, through: lines.count, by: -1) {
                modelContext.delete(blocks[i])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Block.self, BlockLink.self, Tag.self, BlockTag.self, MetadataField.self, BlockEmbedding.self, SearchIndex.self], inMemory: true)
}
