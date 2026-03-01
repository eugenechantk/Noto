//
//  NodeView.swift
//  Noto
//
//  Drill-down view for a single Block node, showing its content as a heading
//  with descendants below in an indented outline.
//

import SwiftUI
import SwiftData
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NodeView")

struct NodeView: View {
    let node: Block
    @Binding var navigationPath: [Block]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @State private var editableContent: String = ""
    @State private var isExpanded: Bool = false
    @State private var hasLoaded = false
    @State private var isSyncing = false
    @State private var searchText: String = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Custom Liquid Glass toolbar
                nodeToolbar

                // Title area
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.content)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(labelPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        .accessibilityIdentifier("nodeViewTitle")
                }

                // Content editor
                NoteTextEditor(
                    text: $editableContent,
                    nodeViewMode: true,
                    onReorderLine: { source, destination in
                        reorderBlock(from: source, to: destination)
                    },
                    onDoubleTapLine: { lineIndex in
                        handleDoubleTap(at: lineIndex)
                    }
                )
                .ignoresSafeArea(.keyboard)
            }

            // Bottom toolbar: Today button + search bar
            bottomToolbar
        }
        .background(backgroundColor)
        .navigationBarHidden(true)
        .onAppear {
            triggerAutoBuilding()
            loadContent()
        }
        .onChange(of: editableContent) {
            syncContent()
        }
        .onChange(of: isExpanded) {
            reloadContent()
        }
    }

    // MARK: - Liquid Glass Toolbar

    private var nodeToolbar: some View {
        HStack {
            // Back button
            GlassToolbarButton(systemImage: "chevron.left") {
                navigationPath.removeLast()
            }
            .accessibilityLabel("Back")

            Spacer()

            // Breadcrumb
            ScrollableBreadcrumb(navigationPath: navigationPath, currentNode: node)

            Spacer()

            // Expand/collapse toggle
            GlassToolbarButton(systemImage: isExpanded ? "list.bullet" : "list.bullet.indent") {
                dismissKeyboardAndToggle()
            }
            .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Bottom Toolbar

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

    // MARK: - Today Navigation

    private func navigateToToday() {
        let dayBlock = TodayNotesService.ensureToday(context: modelContext)

        // Check if already on today's day block
        if dayBlock.id == node.id { return }

        // Build the full navigation path
        var path: [Block] = []
        var current: Block? = dayBlock
        while let block = current {
            path.insert(block, at: 0)
            current = block.parent
        }
        navigationPath = path
    }

    // MARK: - Auto-Building

    /// Trigger auto-building when navigating to any Today's Notes descendant.
    private func triggerAutoBuilding() {
        // Check if this node is part of Today's Notes hierarchy
        var current: Block? = node
        while let block = current {
            if block.content == "Today's Notes" && block.parent == nil {
                // This is a Today's Notes descendant — ensure today's hierarchy is built
                let _ = TodayNotesService.buildHierarchy(root: block, for: Date(), context: modelContext)
                return
            }
            current = block.parent
        }
    }

    // MARK: - Content Management

    private func loadContent() {
        guard !hasLoaded else { return }
        hasLoaded = true
        buildEditableContent()
    }

    private func buildEditableContent() {
        let entries = node.flattenedDescendants(expanded: isExpanded)
        editableContent = entries.map { entry in
            String(repeating: "\t", count: entry.indentLevel) + entry.block.content
        }.joined(separator: "\n")
    }

    private func flattenedBlocks() -> [Block] {
        return node.flattenedDescendants(expanded: isExpanded).map { $0.block }
    }

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
        var blocks = flattenedBlocks()

        // Update existing blocks
        for i in 0..<min(parsed.count, blocks.count) {
            let (relativeDepth, content) = parsed[i]
            let absoluteDepth = node.depth + 1 + relativeDepth

            // Guard: skip content sync for blocks not editable by user
            if blocks[i].content != content && blocks[i].isContentEditableByUser {
                blocks[i].content = content
                blocks[i].updatedAt = Date()
            }

            // Skip depth/parent changes for non-movable blocks
            if blocks[i].depth != absoluteDepth && blocks[i].isMovable {
                let newParent = findParent(for: i, relativeDepth: relativeDepth, in: blocks, parsed: parsed)
                let newSortOrder = blocks[i].sortOrder
                blocks[i].move(to: newParent, sortOrder: newSortOrder)
                if blocks[i].depth != absoluteDepth {
                    blocks[i].depth = absoluteDepth
                }
            }
        }

        // Create new blocks for extra lines
        if parsed.count > blocks.count {
            for i in blocks.count..<parsed.count {
                let (relativeDepth, content) = parsed[i]
                let absoluteDepth = node.depth + 1 + relativeDepth
                let sortOrder = (blocks.last?.sortOrder ?? 0) + Double(i - blocks.count + 1)
                let newParent = findParent(for: i, relativeDepth: relativeDepth, in: blocks, parsed: parsed)
                let block = Block(content: content, parent: newParent ?? node, sortOrder: sortOrder)
                if block.depth != absoluteDepth {
                    block.depth = absoluteDepth
                }
                modelContext.insert(block)
                blocks.append(block)
            }
        }

        // Delete excess blocks (skip non-deletable blocks)
        if blocks.count > parsed.count {
            for i in stride(from: blocks.count - 1, through: parsed.count, by: -1) {
                if blocks[i].isDeletable {
                    modelContext.delete(blocks[i])
                }
            }
        }
    }

    private func findParent(for index: Int, relativeDepth: Int, in blocks: [Block], parsed: [(depth: Int, content: String)]) -> Block? {
        if relativeDepth == 0 { return node }
        for j in stride(from: index - 1, through: 0, by: -1) {
            let candidateRelDepth: Int
            if j < blocks.count {
                candidateRelDepth = blocks[j].depth - node.depth - 1
            } else {
                candidateRelDepth = parsed[j].depth
            }
            if candidateRelDepth == relativeDepth - 1 {
                return blocks[j]
            }
        }
        return node
    }

    // MARK: - Reorder

    private func reorderBlock(from source: Int, to destination: Int) {
        var blocks = flattenedBlocks()
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

        let blockAbove = insertAt > 0 ? blocks[insertAt - 1] : nil
        let maxValidDepth = (blockAbove?.depth ?? node.depth) + 1
        let newDepth = min(movedBlock.depth, maxValidDepth)

        var newParent: Block? = node
        if newDepth > node.depth + 1 {
            for j in stride(from: insertAt - 1, through: 0, by: -1) {
                if blocks[j].depth == newDepth - 1 {
                    newParent = blocks[j]
                    break
                }
            }
        }

        movedBlock.move(to: newParent, sortOrder: 0)

        for (i, block) in blocks.enumerated() {
            block.sortOrder = Double(i + 1)
        }

        reconcileParents(in: blocks)
        reloadContent()
    }

    private func reconcileParents(in blocks: [Block]) {
        for (i, block) in blocks.enumerated() {
            let depth = block.depth
            var correctParent: Block? = node
            if depth > node.depth + 1 {
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

    private func reloadContent() {
        isSyncing = true
        buildEditableContent()
        isSyncing = false
    }

    // MARK: - Navigation

    private func handleDoubleTap(at lineIndex: Int) {
        let blocks = flattenedBlocks()
        guard lineIndex >= 0, lineIndex < blocks.count else { return }
        let tappedBlock = blocks[lineIndex]
        navigationPath.append(tappedBlock)
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

    // MARK: - Expand/Collapse

    private func dismissKeyboardAndToggle() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isExpanded.toggle()
        }
    }
}
