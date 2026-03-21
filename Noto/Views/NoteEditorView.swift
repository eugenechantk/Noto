//
//  NoteEditorView.swift
//  Noto
//
//  Full-screen editor for a single note (Block). Shows the note's content
//  in a plain text editor. Children are displayed as indented lines when expanded.
//  Inspired by Simple-Notes (github.com/pmattos/Simple-Notes).
//

import SwiftUI
import SwiftData
import os.log
import NotoModels
import NotoCore
import NotoDirtyTracker

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "NoteEditorView")

struct NoteEditorView: View {
    let note: Block
    @Binding var navigationPath: [Block]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var dirtyTracker: DirtyTracker

    @State private var editableContent: String = ""
    @State private var isExpanded: Bool = false
    @State private var hasLoaded = false
    @State private var isSyncing = false

    private var baseDepth: Int { note.depth }

    var body: some View {
        VStack(spacing: 0) {
            NoteTextEditor(
                text: $editableContent,
                nodeViewMode: true,
                onEndEditing: {
                    Task { await dirtyTracker.flush() }
                },
                onReorderLine: { source, destination in
                    reorderBlock(from: source, to: destination)
                },
                onDoubleTapLine: { lineIndex in
                    handleDoubleTap(at: lineIndex)
                }
            )
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    navigationPath.removeLast()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Notes")
                            .font(.system(size: 17))
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismissKeyboardAndToggle()
                } label: {
                    Image(systemName: isExpanded ? "list.bullet" : "list.bullet.indent")
                        .font(.system(size: 17, weight: .medium))
                }
                .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
            }
        }
        .onAppear {
            loadContent()
        }
        .onDisappear {
            Task { await dirtyTracker.flush() }
        }
        .onChange(of: editableContent) {
            syncContent()
        }
        .onChange(of: isExpanded) {
            reloadContent()
        }
    }

    // MARK: - Display

    private var displayTitle: String {
        let plain = PlainTextExtractor.plainText(from: note.content)
        return plain.isEmpty ? "New Note" : plain
    }

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.07, green: 0.07, blue: 0.07)
            : .white
    }

    // MARK: - Data

    private func displayEntries() -> [(block: Block, indentLevel: Int)] {
        return note.flattenedDescendants(expanded: isExpanded).map { ($0.block, $0.indentLevel) }
    }

    private func currentBlocks() -> [Block] {
        displayEntries().map { $0.block }
    }

    private func buildEditableContent() {
        editableContent = displayEntries().map { entry in
            String(repeating: "\t", count: entry.indentLevel) + entry.block.content
        }.joined(separator: "\n")
    }

    private func loadContent() {
        guard !hasLoaded else { return }
        hasLoaded = true
        buildEditableContent()
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
        var blocks = currentBlocks()
        var depthChanged = false

        for i in 0..<min(parsed.count, blocks.count) {
            let (relativeDepth, content) = parsed[i]
            let absoluteDepth = baseDepth + 1 + relativeDepth

            if blocks[i].content != content && blocks[i].isContentEditableByUser {
                blocks[i].content = content
                blocks[i].updatedAt = Date()
                dirtyTracker.markDirty(blocks[i].id)
            }

            if blocks[i].depth != absoluteDepth && blocks[i].isMovable {
                let newParent = findParent(for: i, relativeDepth: relativeDepth, in: blocks, parsed: parsed)
                let newSortOrder = blocks[i].sortOrder
                blocks[i].move(to: newParent, sortOrder: newSortOrder)
                if blocks[i].depth != absoluteDepth {
                    blocks[i].depth = absoluteDepth
                }
                depthChanged = true

                if !isExpanded, let newParent = newParent, newParent !== note {
                    isExpanded = true
                }
            }
        }

        if parsed.count > blocks.count {
            for i in blocks.count..<parsed.count {
                let (relativeDepth, content) = parsed[i]
                let absoluteDepth = baseDepth + 1 + relativeDepth
                let sortOrder = (blocks.last?.sortOrder ?? 0) + Double(i - blocks.count + 1)
                let newParent = findParent(for: i, relativeDepth: relativeDepth, in: blocks, parsed: parsed)
                let block = Block(content: content, parent: newParent ?? note, sortOrder: sortOrder)
                if block.depth != absoluteDepth {
                    block.depth = absoluteDepth
                }
                modelContext.insert(block)
                blocks.append(block)
                dirtyTracker.markDirty(block.id)
            }
        }

        if blocks.count > parsed.count {
            for i in stride(from: blocks.count - 1, through: parsed.count, by: -1) {
                if blocks[i].isDeletable {
                    dirtyTracker.markDeleted(blocks[i].id)
                    modelContext.delete(blocks[i])
                }
            }
        }

        if depthChanged {
            buildEditableContent()
        }
    }

    private func findParent(for index: Int, relativeDepth: Int, in blocks: [Block], parsed: [(depth: Int, content: String)]) -> Block? {
        if relativeDepth == 0 { return note }
        for j in stride(from: index - 1, through: 0, by: -1) {
            let candidateRelDepth: Int
            if j < blocks.count {
                candidateRelDepth = blocks[j].depth - baseDepth - 1
            } else {
                candidateRelDepth = parsed[j].depth
            }
            if candidateRelDepth == relativeDepth - 1 {
                return blocks[j]
            }
        }
        return note
    }

    // MARK: - Reorder

    private func reorderBlock(from source: Int, to destination: Int) {
        var blocks = currentBlocks()
        guard source >= 0, source < blocks.count else { return }
        guard destination >= 0, destination <= blocks.count else { return }
        guard source != destination, source != destination - 1 else { return }

        let movedBlock = blocks[source]
        guard movedBlock.isReorderable else { return }

        blocks.remove(at: source)
        let insertAt = destination > source ? destination - 1 : destination
        blocks.insert(movedBlock, at: insertAt)

        let blockAbove = insertAt > 0 ? blocks[insertAt - 1] : nil
        let maxValidDepth = (blockAbove?.depth ?? baseDepth) + 1
        let newDepth = min(movedBlock.depth, maxValidDepth)

        var newParent: Block? = note
        if newDepth > baseDepth + 1 {
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
            var correctParent: Block? = note
            if depth > baseDepth + 1 {
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
        let blocks = currentBlocks()
        guard lineIndex >= 0, lineIndex < blocks.count else { return }
        navigationPath.append(blocks[lineIndex])
    }

    // MARK: - Expand/Collapse

    private func dismissKeyboardAndToggle() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isExpanded.toggle()
        }
    }
}
