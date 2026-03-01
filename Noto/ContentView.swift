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
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Block.sortOrder)
    private var allBlocks: [Block]

    /// Flat list of all blocks ordered by global sortOrder.
    private var flattenedBlocks: [Block] {
        allBlocks.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    @State private var editableContent: String = ""
    @State private var hasLoaded = false
    @State private var showDebug = false
    @State private var isSyncing = false
    @State private var navigationPath: [Block] = []
    @State private var searchText: String = ""

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    // Top toolbar with liquid glass
                    topToolbar

                    // Title section
                    titleSection

                    // Main text editor
                    NoteTextEditor(
                        text: $editableContent,
                        onReorderLine: { source, destination in
                            reorderBlock(from: source, to: destination)
                        },
                        onDoubleTapLine: { lineIndex in
                            handleDoubleTap(at: lineIndex)
                        }
                    )
                    .ignoresSafeArea(.keyboard)
                    .onAppear {
                        loadContent()
                    }
                    .onChange(of: editableContent) {
                        syncContent()
                    }
                }

                // Floating overlays
                VStack(spacing: 0) {
                    Spacer()

                    if showDebug {
                        DebugPanelView(blocks: flattenedBlocks)
                            .transition(.move(edge: .bottom))
                            .padding(.bottom, 8)
                    }

                    // Bottom search bar
                    GlassSearchBar(text: $searchText)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 32)
                }
            }
            .background(backgroundColor)
            .navigationDestination(for: Block.self) { block in
                NodeView(node: block, navigationPath: $navigationPath)
            }
        }
    }

    // MARK: - Liquid Glass UI

    private var topToolbar: some View {
        HStack {
            Text("Home")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(labelSecondary)
                .tracking(-0.25)

            Spacer()

            HStack(spacing: 8) {
                // Debug toggle
                GlassToolbarButton(systemImage: showDebug ? "ladybug.fill" : "ladybug") {
                    withAnimation { showDebug.toggle() }
                }

                // Sort button (from Figma design)
                GlassToolbarButton(systemImage: "arrow.up.arrow.down") {
                    logger.debug("Sort button tapped")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Home")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(labelPrimary)
                .tracking(0.4)

            Text("Add tag here")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(labelSecondary)
                .tracking(-0.25)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Colors

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.07, green: 0.07, blue: 0.07)
            : .white
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

    // MARK: - Double-Tap Navigation

    private func handleDoubleTap(at lineIndex: Int) {
        let blocks = flattenedBlocks
        guard lineIndex >= 0, lineIndex < blocks.count else { return }
        let tappedBlock = blocks[lineIndex]
        navigationPath.append(tappedBlock)
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

        // Build the new flat order
        blocks.remove(at: source)
        let insertAt = destination > source ? destination - 1 : destination
        blocks.insert(movedBlock, at: insertAt)

        // Adjust depth: a block can be at most 1 deeper than the block above it.
        let blockAbove = insertAt > 0 ? blocks[insertAt - 1] : nil
        let maxValidDepth = (blockAbove?.depth ?? -1) + 1
        let newDepth = min(movedBlock.depth, maxValidDepth)

        if movedBlock.depth != newDepth {
            logger.debug("[reorderBlock] adjusting depth \(movedBlock.depth)→\(newDepth)")
        }

        // Find the parent for the (possibly adjusted) depth
        var newParent: Block? = nil
        if newDepth > 0 {
            for j in stride(from: insertAt - 1, through: 0, by: -1) {
                if blocks[j].depth == newDepth - 1 {
                    newParent = blocks[j]
                    break
                }
            }
        }

        logger.debug("[reorderBlock] moving '\(movedBlock.content.prefix(20))' from \(source) to \(destination), depth \(movedBlock.depth)→\(newDepth), newParent=\(newParent?.content.prefix(20) ?? "nil")")

        // Update the moved block's parent and depth via move() (also updates descendants)
        movedBlock.move(to: newParent, sortOrder: 0)

        // Assign sequential sortOrders to ALL blocks to maintain the flat order
        for (i, block) in blocks.enumerated() {
            block.sortOrder = Double(i + 1)
        }

        // Reconcile parents for any blocks whose visual position now implies
        // a different parent (e.g., a child that's now visually under a new parent)
        reconcileParents(in: blocks)

        reloadContent()
    }

    /// Ensure each block's parent matches the flat visual order.
    /// Walk the flat list and assign parents by looking backward for the nearest
    /// block at depth - 1.
    private func reconcileParents(in blocks: [Block]) {
        for (i, block) in blocks.enumerated() {
            let depth = block.depth
            var correctParent: Block? = nil
            if depth > 0 {
                for j in stride(from: i - 1, through: 0, by: -1) {
                    if blocks[j].depth == depth - 1 {
                        correctParent = blocks[j]
                        break
                    }
                }
            }
            if block.parent !== correctParent {
                block.parent = correctParent
                block.updatedAt = Date()
            }
        }
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
