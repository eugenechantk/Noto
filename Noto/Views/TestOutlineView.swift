//
//  TestOutlineView.swift
//  PersonalNotetaking
//
//  Minimal test UI for validating the data structure.
//

import SwiftUI
import SwiftData

struct TestOutlineView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Block> { $0.parent == nil && !$0.isArchived },
           sort: \Block.sortOrder)
    private var rootBlocks: [Block]

    @State private var selectedBlock: Block?
    @State private var showingLinkSheet = false
    @State private var showingBacklinksSheet = false
    @State private var linkTargetId: String = ""

    var body: some View {
        NavigationSplitView {
            VStack {
                // Toolbar
                HStack {
                    Button(action: addRootBlock) {
                        Label("Add Block", systemImage: "plus")
                    }
                    Spacer()
                    if let selected = selectedBlock {
                        Text("Selected: \(selected.content.prefix(20))...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Block list
                List(selection: $selectedBlock) {
                    ForEach(rootBlocks) { block in
                        BlockTreeView(
                            block: block,
                            selectedBlock: $selectedBlock,
                            onAddChild: { addChildBlock(to: block) },
                            onDelete: { deleteBlock(block) },
                            onIndent: { indentBlock(block) },
                            onOutdent: { outdentBlock(block) },
                            onCreateLink: {
                                selectedBlock = block
                                showingLinkSheet = true
                            },
                            onShowBacklinks: {
                                selectedBlock = block
                                showingBacklinksSheet = true
                            },
                            onMove: { block, direction in
                                moveBlock(block, direction: direction)
                            }
                        )
                    }
                }
                .listStyle(.plain)
            }
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 300, ideal: 400)
#endif
        } detail: {
            if let block = selectedBlock {
                BlockDetailView(block: block)
            } else {
                Text("Select a block")
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showingLinkSheet) {
            LinkCreationSheet(
                sourceBlock: selectedBlock,
                linkTargetId: $linkTargetId,
                onCreateLink: createLink
            )
        }
        .sheet(isPresented: $showingBacklinksSheet) {
            if let block = selectedBlock {
                BacklinksSheet(block: block)
            }
        }
    }

    // MARK: - Actions

    private func addRootBlock() {
        withAnimation {
            let sortOrder = Block.sortOrderForAppending(to: rootBlocks)
            let block = Block(content: "New block", sortOrder: sortOrder)
            modelContext.insert(block)
        }
    }

    private func addChildBlock(to parent: Block) {
        withAnimation {
            let sortOrder = Block.sortOrderForAppending(to: parent.sortedChildren)
            let child = Block(content: "New child", parent: parent, sortOrder: sortOrder)
            modelContext.insert(child)
        }
    }

    private func deleteBlock(_ block: Block) {
        withAnimation {
            modelContext.delete(block)
        }
    }

    private func indentBlock(_ block: Block) {
        withAnimation {
            let siblings: [Block]
            if let parent = block.parent {
                siblings = parent.sortedChildren
            } else {
                siblings = rootBlocks
            }
            _ = block.indent(siblings: siblings)
        }
    }

    private func outdentBlock(_ block: Block) {
        withAnimation {
            _ = block.outdent()
        }
    }

    private func moveBlock(_ block: Block, direction: MoveDirection) {
        withAnimation {
            let siblings: [Block]
            if let parent = block.parent {
                siblings = parent.sortedChildren
            } else {
                siblings = rootBlocks
            }

            guard let currentIndex = siblings.firstIndex(where: { $0.id == block.id }) else { return }

            switch direction {
            case .up:
                guard currentIndex > 0 else { return }
                let targetIndex = currentIndex - 1
                let beforeOrder = targetIndex > 0 ? siblings[targetIndex - 1].sortOrder : nil
                let afterOrder = siblings[targetIndex].sortOrder
                block.sortOrder = Block.sortOrderBetween(beforeOrder, afterOrder)

            case .down:
                guard currentIndex < siblings.count - 1 else { return }
                let targetIndex = currentIndex + 1
                let beforeOrder = siblings[targetIndex].sortOrder
                let afterOrder = targetIndex < siblings.count - 1 ? siblings[targetIndex + 1].sortOrder : nil
                block.sortOrder = Block.sortOrderBetween(beforeOrder, afterOrder)
            }
            block.updatedAt = Date()
        }
    }

    private func createLink(from source: Block, toId: String) {
        guard let targetUUID = UUID(uuidString: toId) else { return }

        // Find target block
        let descriptor = FetchDescriptor<Block>(predicate: #Predicate { $0.id == targetUUID })
        guard let targets = try? modelContext.fetch(descriptor),
              let target = targets.first else { return }

        // Prevent self-link
        guard source.id != target.id else { return }

        let link = BlockLink(
            sourceBlock: source,
            targetBlock: target,
            mentionText: target.content
        )
        modelContext.insert(link)
        showingLinkSheet = false
        linkTargetId = ""
    }
}

enum MoveDirection {
    case up, down
}

// MARK: - Block Tree View (Recursive)

struct BlockTreeView: View {
    @Bindable var block: Block
    @Binding var selectedBlock: Block?
    let onAddChild: () -> Void
    let onDelete: () -> Void
    let onIndent: () -> Void
    let onOutdent: () -> Void
    let onCreateLink: () -> Void
    let onShowBacklinks: () -> Void
    let onMove: (Block, MoveDirection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                BlockRowView(
                    block: block,
                    onAddChild: onAddChild,
                    onDelete: onDelete,
                    onIndent: onIndent,
                    onOutdent: onOutdent,
                    onCreateLink: onCreateLink,
                    onShowBacklinks: onShowBacklinks
                )

                // Move buttons
                VStack(spacing: 2) {
                    Button(action: { onMove(block, .up) }) {
                        Image(systemName: "chevron.up")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)

                    Button(action: { onMove(block, .down) }) {
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(selectedBlock?.id == block.id ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedBlock = block
            }

            // Render children recursively
            ForEach(block.sortedChildren) { child in
                BlockTreeView(
                    block: child,
                    selectedBlock: $selectedBlock,
                    onAddChild: {
                        // Add child to this child
                    },
                    onDelete: {
                        // Delete this child
                    },
                    onIndent: {
                        // Indent
                    },
                    onOutdent: {
                        // Outdent
                    },
                    onCreateLink: onCreateLink,
                    onShowBacklinks: onShowBacklinks,
                    onMove: onMove
                )
            }
        }
    }
}

// MARK: - Block Detail View

struct BlockDetailView: View {
    @Bindable var block: Block

    var body: some View {
        Form {
            Section("Content") {
                TextEditor(text: $block.content)
                    .frame(minHeight: 100)
                    .onChange(of: block.content) {
                        block.updatedAt = Date()
                    }
            }

            Section("Info") {
                LabeledContent("ID", value: block.id.uuidString)
                LabeledContent("Depth", value: "\(block.depth)")
                LabeledContent("Sort Order", value: String(format: "%.4f", block.sortOrder))
                LabeledContent("Created", value: block.createdAt.formatted())
                LabeledContent("Updated", value: block.updatedAt.formatted())
                LabeledContent("Children", value: "\(block.children.count)")
            }

            Section("Outgoing Links") {
                if block.outgoingLinks.isEmpty {
                    Text("No outgoing links")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(block.outgoingLinks) { link in
                        if let target = link.targetBlock {
                            Text("→ \(target.content.prefix(30))...")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Block Details")
    }
}

// MARK: - Link Creation Sheet

struct LinkCreationSheet: View {
    let sourceBlock: Block?
    @Binding var linkTargetId: String
    let onCreateLink: (Block, String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Create Link")
                .font(.headline)

            if let source = sourceBlock {
                Text("From: \(source.content.prefix(30))...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            TextField("Target Block ID (UUID)", text: $linkTargetId)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Button("Create Link") {
                    if let source = sourceBlock {
                        onCreateLink(source, linkTargetId)
                    }
                }
                .disabled(linkTargetId.isEmpty || sourceBlock == nil)
            }
        }
        .padding()
        .frame(minWidth: 300)
    }
}

// MARK: - Backlinks Sheet

struct BacklinksSheet: View {
    let block: Block
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var backlinks: [BlockLink] {
        let blockId = block.id
        let descriptor = FetchDescriptor<BlockLink>(
            predicate: #Predicate { $0.targetBlock?.id == blockId }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Backlinks")
                .font(.headline)

            Text("Links pointing to: \(block.content.prefix(30))...")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if backlinks.isEmpty {
                Text("No backlinks found")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                List(backlinks) { link in
                    if let source = link.sourceBlock {
                        VStack(alignment: .leading) {
                            Text(source.content.prefix(50))
                            Text("ID: \(source.id.uuidString)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Button("Done") {
                dismiss()
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
}

#Preview {
    TestOutlineView()
        .modelContainer(for: [Block.self, BlockLink.self, Tag.self, BlockTag.self, MetadataField.self, BlockEmbedding.self, SearchIndex.self], inMemory: true)
}
