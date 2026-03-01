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

    var body: some View {
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
        .background(backgroundColor)
        .navigationBarHidden(true)
        .onAppear {
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
            breadcrumbView

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

    // MARK: - Breadcrumb

    private var breadcrumbView: some View {
        HStack(spacing: 4) {
            Text("Home")
                .foregroundStyle(labelSecondary)
            ForEach(navigationPath, id: \.id) { block in
                Text("/")
                    .foregroundStyle(labelSecondary)
                if block.id == node.id {
                    Text(block.content.isEmpty ? "Untitled" : String(block.content.prefix(20)))
                        .foregroundStyle(labelPrimary)
                        .lineLimit(1)
                } else {
                    Text(block.content.isEmpty ? "Untitled" : String(block.content.prefix(20)))
                        .foregroundStyle(labelSecondary)
                        .lineLimit(1)
                }
            }
        }
        .font(.system(size: 15, weight: .medium))
        .tracking(-0.25)
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

    /// Get the flattened list of descendant blocks in display order.
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

            if blocks[i].content != content {
                blocks[i].content = content
                blocks[i].updatedAt = Date()
            }

            if blocks[i].depth != absoluteDepth {
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

        // Delete excess blocks
        if blocks.count > parsed.count {
            for i in stride(from: blocks.count - 1, through: parsed.count, by: -1) {
                modelContext.delete(blocks[i])
            }
        }
    }

    /// Find parent for a block at the given relative depth.
    /// Relative depth 0 → parent is the node itself.
    /// Relative depth N → walk backward for nearest block at relative depth N-1.
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

        blocks.remove(at: source)
        let insertAt = destination > source ? destination - 1 : destination
        blocks.insert(movedBlock, at: insertAt)

        // Adjust depth relative to the node
        let blockAbove = insertAt > 0 ? blocks[insertAt - 1] : nil
        let maxValidDepth = (blockAbove?.depth ?? node.depth) + 1
        let newDepth = min(movedBlock.depth, maxValidDepth)

        // Find parent
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

        // Assign sequential sortOrders
        for (i, block) in blocks.enumerated() {
            block.sortOrder = Double(i + 1)
        }

        // Reconcile parents
        reconcileParents(in: blocks)

        // Rebuild content from the locally reordered array
        isSyncing = true
        editableContent = blocks.map { block in
            let relativeDepth = block.depth - node.depth - 1
            return String(repeating: "\t", count: relativeDepth) + block.content
        }.joined(separator: "\n")
        isSyncing = false
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
