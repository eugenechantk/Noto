//
//  ContentView.swift
//  Noto
//
//  Created by Eugene Chan on 1/8/26.
//

import SwiftUI
import SwiftData
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "ContentView")

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Block.sortOrder)
    private var allBlocks: [Block]

    /// DFS traversal of the block tree — parents before children.
    private var flattenedBlocks: [Block] {
        var result: [Block] = []
        func flatten(_ blocks: [Block]) {
            for block in blocks.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                result.append(block)
                flatten(block.children.filter { !$0.isArchived })
            }
        }
        flatten(allBlocks.filter { $0.parent == nil && !$0.isArchived })
        return result
    }

    @State private var editableContent: String = ""
    @State private var hasLoaded = false

    @State private var showDebug = false
    @State private var isSyncing = false

    var body: some View {
        ZStack(alignment: .bottom) {
            NoteTextEditor(
                text: $editableContent,
                onReorderLine: { source, destination in
                    reorderBlock(from: source, to: destination)
                }
            )
                .ignoresSafeArea(.keyboard)
                .onAppear {
                    loadContent()
                }
                .onChange(of: editableContent) {
                    syncContent()
                }

            if showDebug {
                DebugPanelView(blocks: flattenedBlocks)
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

        let blocks = flattenedBlocks
        if blocks.isEmpty {
            let block = Block(content: "", sortOrder: 1.0)
            modelContext.insert(block)
        } else {
            editableContent = blocks.map { block in
                String(repeating: "\t", count: block.depth) + block.content
            }.joined(separator: "\n")
        }
    }

    /// Parse a line into (depth, content) by counting leading `\t` characters.
    private func parseLine(_ line: String) -> (depth: Int, content: String) {
        var depth = 0
        for ch in line {
            guard ch == "\t" else { break }
            depth += 1
        }
        let content = String(line.dropFirst(depth))
        return (depth, content)
    }

    private func syncContent() {
        guard hasLoaded, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let lines = editableContent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let parsed = lines.map { parseLine($0) }
        var blocks = flattenedBlocks

        if parsed.contains(where: { $0.depth > 0 }) {
            logger.debug("[syncContent] parsed depths: \(parsed.enumerated().map { "[\($0.offset)] d=\($0.element.depth) \"\($0.element.content.prefix(20))\"" }.joined(separator: ", "))")
        }

        // Update existing blocks
        for i in 0..<min(parsed.count, blocks.count) {
            let (depth, content) = parsed[i]

            if blocks[i].content != content {
                blocks[i].content = content
                blocks[i].updatedAt = Date()
            }

            // Update depth / parent if changed
            if blocks[i].depth != depth {
                let newParent = findParent(for: i, depth: depth, in: blocks, parsed: parsed)
                logger.debug("[syncContent] block[\(i)] depth \(blocks[i].depth)→\(depth), parent: \(newParent?.content.prefix(20) ?? "nil")")
                let newSortOrder = blocks[i].sortOrder
                blocks[i].move(to: newParent, sortOrder: newSortOrder)
                // move() computes depth from parent; override if the parsed
                // depth disagrees (e.g. orphan indent with no valid parent).
                if blocks[i].depth != depth {
                    blocks[i].depth = depth
                }
            }
        }

        // Create new blocks for extra lines
        if parsed.count > blocks.count {
            for i in blocks.count..<parsed.count {
                let (depth, content) = parsed[i]
                let sortOrder = (blocks.last?.sortOrder ?? 0) + Double(i - blocks.count + 1)
                let newParent = findParent(for: i, depth: depth, in: blocks, parsed: parsed)
                let block = Block(content: content, parent: newParent, sortOrder: sortOrder)
                // The Block init sets depth from parent, but we need to override for root blocks
                if depth != block.depth {
                    block.depth = depth
                }
                modelContext.insert(block)
                blocks.append(block)
            }
        }

        // Delete excess blocks
        if blocks.count > parsed.count {
            for i in stride(from: blocks.count - 1, through: parsed.count, by: -1) {
                modelContext.delete(blocks[i])
            }
        }
    }

    /// Walk backwards to find the nearest block with depth == targetDepth - 1.
    private func findParent(for index: Int, depth: Int, in blocks: [Block], parsed: [(depth: Int, content: String)]) -> Block? {
        guard depth > 0 else { return nil }
        for j in stride(from: index - 1, through: 0, by: -1) {
            let candidateDepth: Int
            if j < blocks.count {
                candidateDepth = blocks[j].depth
            } else {
                candidateDepth = parsed[j].depth
            }
            if candidateDepth == depth - 1 {
                return blocks[j]
            }
        }
        return nil
    }

    // MARK: - Reorder

    /// Move a block from `source` line index to `destination` insertion index.
    /// Destination uses insertion semantics: 0 = before first, count = after last.
    private func reorderBlock(from source: Int, to destination: Int) {
        var blocks = flattenedBlocks
        guard source >= 0, source < blocks.count else { return }
        guard destination >= 0, destination <= blocks.count else { return }
        guard source != destination, source != destination - 1 else { return }

        let movedBlock = blocks[source]

        // Build the virtual reordered array
        blocks.remove(at: source)
        // Adjust destination index after removal
        let insertAt = destination > source ? destination - 1 : destination
        blocks.insert(movedBlock, at: insertAt)

        // Compute new sortOrder from neighbors
        let before: Double? = insertAt > 0 ? blocks[insertAt - 1].sortOrder : nil
        let after: Double? = insertAt < blocks.count - 1 ? blocks[insertAt + 1].sortOrder : nil
        let newSortOrder = Block.sortOrderBetween(before, after)

        logger.debug("[reorderBlock] moving '\(movedBlock.content.prefix(20))' from \(source) to \(destination), new sortOrder=\(newSortOrder)")

        movedBlock.sortOrder = newSortOrder
        movedBlock.updatedAt = Date()

        reloadContent()
    }

    /// Regenerate `editableContent` from the current model state.
    private func reloadContent() {
        isSyncing = true
        editableContent = flattenedBlocks.map { block in
            String(repeating: "\t", count: block.depth) + block.content
        }.joined(separator: "\n")
        isSyncing = false
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Block.self, BlockLink.self, Tag.self, BlockTag.self, MetadataField.self, BlockEmbedding.self, SearchIndex.self], inMemory: true)
}
