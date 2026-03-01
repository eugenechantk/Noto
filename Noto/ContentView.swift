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
    @Query(filter: #Predicate<Block> { $0.parent == nil && !$0.isArchived }, sort: \Block.sortOrder)
    private var rootBlocks: [Block]

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
                        DebugPanelView(blocks: rootBlocks)
                            .transition(.move(edge: .bottom))
                            .padding(.bottom, 8)
                    }

                    // Bottom toolbar: Today button + search bar
                    bottomToolbar
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
                .accessibilityIdentifier("homeTitle")

            Text("Add tag here")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(labelSecondary)
                .tracking(-0.25)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var bottomToolbar: some View {
        GlassEffectContainer {
            HStack(spacing: 12) {
                GlassTodayButton {
                    navigateToToday()
                }

                GlassSearchBar(text: $searchText)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 32)
        .padding(.top, 4)
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

    // MARK: - Today Navigation

    private func navigateToToday() {
        let dayBlock = TodayNotesService.ensureToday(context: modelContext)
        // Build the full navigation path: Today's Notes root → Year → Month → Week → Day
        var path: [Block] = []
        var current: Block? = dayBlock
        while let block = current {
            path.insert(block, at: 0)
            current = block.parent
        }
        navigationPath = path
    }

    // MARK: - Double-Tap Navigation

    private func handleDoubleTap(at lineIndex: Int) {
        guard lineIndex >= 0, lineIndex < rootBlocks.count else { return }
        let tappedBlock = rootBlocks[lineIndex]
        navigationPath.append(tappedBlock)
    }

    private func loadContent() {
        guard !hasLoaded else { return }
        hasLoaded = true

        // Ensure Today's Notes root exists
        let _ = TodayNotesService.ensureRoot(context: modelContext)

        if rootBlocks.isEmpty {
            let block = Block(content: "", sortOrder: 1.0)
            modelContext.insert(block)
        } else {
            editableContent = rootBlocks.map { $0.content }.joined(separator: "\n")
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

        let lines = editableContent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let parsed = lines.map { parseLine($0) }
        var blocks = Array(rootBlocks)
        var needsReload = false

        // Update existing blocks
        for i in 0..<min(parsed.count, blocks.count) {
            let (depth, content) = parsed[i]

            // Guard: skip content sync for blocks not editable by user
            if blocks[i].content != content && blocks[i].isContentEditableByUser {
                blocks[i].content = content
                blocks[i].updatedAt = Date()
            }

            // Handle indentation on home screen: reparent under previous sibling
            // Skip for non-movable blocks (e.g. auto-built Today's Notes blocks)
            if depth > 0 && blocks[i].isMovable {
                if let newParent = findParent(for: i, depth: depth, in: blocks, parsed: parsed) {
                    let newSortOrder = Block.sortOrderForAppending(to: newParent.sortedChildren.filter { !$0.isArchived })
                    blocks[i].move(to: newParent, sortOrder: newSortOrder)
                    needsReload = true
                }
            }
        }

        // Create new blocks for extra lines
        if parsed.count > blocks.count {
            for i in blocks.count..<parsed.count {
                let (depth, content) = parsed[i]
                let sortOrder = (blocks.last?.sortOrder ?? 0) + Double(i - blocks.count + 1)
                let newParent: Block? = depth > 0 ? findParent(for: i, depth: depth, in: blocks, parsed: parsed) : nil
                let block = Block(content: content, parent: newParent, sortOrder: sortOrder)
                modelContext.insert(block)
                blocks.append(block)
            }
        }

        // Delete excess blocks — only delete root-level, deletable blocks.
        // Reparented blocks (parent != nil) must be preserved.
        if blocks.count > parsed.count {
            for i in stride(from: blocks.count - 1, through: parsed.count, by: -1) {
                if blocks[i].parent == nil && blocks[i].isDeletable {
                    modelContext.delete(blocks[i])
                }
            }
        }

        // Rebuild content from remaining root blocks immediately
        // (can't rely on @Query rootBlocks which hasn't refreshed yet)
        if needsReload {
            let remainingRoots = blocks.filter { $0.parent == nil }
            editableContent = remainingRoots.map { $0.content }.joined(separator: "\n")
        }

        isSyncing = false
    }

    /// Walk backwards to find the nearest block with depth == targetDepth - 1.
    private func findParent(for index: Int, depth: Int, in blocks: [Block], parsed: [(depth: Int, content: String)]) -> Block? {
        guard depth > 0 else { return nil }
        for j in stride(from: index - 1, through: 0, by: -1) {
            let candidateDepth = parsed[j].depth
            if candidateDepth == depth - 1 {
                return blocks[j]
            }
        }
        return nil
    }

    // MARK: - Reorder

    /// Move a block from `source` line index to `destination` insertion index.
    private func reorderBlock(from source: Int, to destination: Int) {
        var blocks = Array(rootBlocks)
        guard source >= 0, source < blocks.count else { return }
        guard destination >= 0, destination <= blocks.count else { return }
        guard source != destination, source != destination - 1 else { return }

        let movedBlock = blocks[source]

        // Guard: non-reorderable blocks cannot be moved
        guard movedBlock.isReorderable else {
            logger.debug("[reorderBlock] block '\(movedBlock.content.prefix(20))' is not reorderable")
            return
        }

        blocks.remove(at: source)
        let insertAt = destination > source ? destination - 1 : destination
        blocks.insert(movedBlock, at: insertAt)

        logger.debug("[reorderBlock] moving '\(movedBlock.content.prefix(20))' from \(source) to \(destination)")

        // Assign sequential sortOrders to maintain the new order
        for (i, block) in blocks.enumerated() {
            block.sortOrder = Double(i + 1)
        }

        // Rebuild content from the locally reordered array
        // (rootBlocks @Query hasn't refreshed the new sortOrder yet)
        isSyncing = true
        editableContent = blocks.map { $0.content }.joined(separator: "\n")
        isSyncing = false
    }

    /// Regenerate `editableContent` from the current root blocks.
    private func reloadContent() {
        isSyncing = true
        editableContent = rootBlocks.map { $0.content }.joined(separator: "\n")
        isSyncing = false
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Block.self, BlockLink.self, Tag.self, BlockTag.self, MetadataField.self, BlockEmbedding.self, SearchIndex.self], inMemory: true)
}
