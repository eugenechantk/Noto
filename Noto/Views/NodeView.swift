//
//  OutlineView.swift
//  Noto
//
//  Unified outline view for both home (root) and drill-down (node) modes.
//  When node is nil, shows root-level blocks. When node is non-nil, shows
//  that node's descendants. The only difference is which node is focused.
//

import SwiftUI
import SwiftData
import os.log
import NotoModels
import NotoCore
import NotoFTS5
import NotoDirtyTracker
import NotoSearch
import NotoTodayNotes
import NotoEmbedding

#if canImport(USearch)
import NotoHNSW
#endif

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "OutlineView")

struct OutlineView: View {
    let node: Block?
    @Binding var navigationPath: [Block]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var dirtyTracker: DirtyTracker

    @Query(sort: \Block.sortOrder) private var allBlocks: [Block]

    @State private var editableContent: String = ""
    @State private var isExpanded: Bool = false
    @State private var hasLoaded = false
    @State private var isSyncing = false
    @State private var showSearch = false
    @State private var showDebug = false
    @State private var ancestors: [Block] = []
    @State private var isKeyboardVisible = false

    private var isRoot: Bool { node == nil }
    private var baseDepth: Int { node?.depth ?? -1 }
    private var displayTitle: String {
        guard let content = node?.content else { return "Home" }
        return PlainTextExtractor.plainText(from: content)
    }

    /// Root blocks (parent == nil, not archived), used only in root mode.
    private var rootBlocks: [Block] {
        allBlocks.filter { $0.parent == nil && !$0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Custom Liquid Glass toolbar
                outlineToolbar

                // Title area
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTitle)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(labelPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        .accessibilityIdentifier(isRoot ? "homeTitle" : "nodeViewTitle")
                }

                // Content editor
                NoteTextEditor(
                    text: $editableContent,
                    nodeViewMode: !isRoot,
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
                .ignoresSafeArea(.keyboard)
            }

            // Floating overlays
            if !isKeyboardVisible {
                VStack(spacing: 0) {
                    Spacer()

                    if showDebug {
                        DebugPanelView(blocks: currentBlocks())
                            .transition(.move(edge: .bottom))
                            .padding(.bottom, 8)
                    }

                    bottomToolbar
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background {
            backgroundColor.ignoresSafeArea()
        }
        .navigationBarHidden(true)
        .onAppear {
            if !isRoot {
                triggerAutoBuilding()
                buildAncestorPath()
            }
            loadContent()
        }
        .onDisappear {
            Task { await dirtyTracker.flush() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) { isKeyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) { isKeyboardVisible = false }
        }
        .onChange(of: editableContent) {
            syncContent()
        }
        .onChange(of: isExpanded) {
            reloadContent()
        }
        .sheet(isPresented: $showSearch) {
            SearchSheet(
                searchService: {
                    #if canImport(USearch)
                    return SearchService(
                        fts5Database: sharedSearchDatabase,
                        dirtyTracker: dirtyTracker,
                        dirtyStore: sharedDirtyStore,
                        modelContext: modelContext,
                        embeddingModel: sharedEmbeddingModel,
                        hnswIndex: sharedHNSWIndex,
                        vectorKeyStore: sharedVectorKeyStore
                    )
                    #else
                    return SearchService(
                        fts5Database: sharedSearchDatabase,
                        dirtyTracker: dirtyTracker,
                        dirtyStore: sharedDirtyStore,
                        modelContext: modelContext
                    )
                    #endif
                }(),
                onSelectResult: { blockId in
                    navigateToSearchResult(blockId: blockId)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Toolbar

    private var outlineToolbar: some View {
        HStack {
            if node != nil {
                GlassToolbarButton(systemImage: "chevron.left") {
                    navigationPath.removeLast()
                }
                .accessibilityLabel("Back")
            }

            Spacer()

            if let node = node {
                ScrollableBreadcrumb(ancestors: ancestors, currentNode: node, navigationPath: $navigationPath)
                Spacer()
            }

            HStack(spacing: 8) {
                GlassToolbarButton(systemImage: showDebug ? "ladybug.fill" : "ladybug") {
                    withAnimation { showDebug.toggle() }
                }

                GlassToolbarButton(systemImage: isExpanded ? "list.bullet" : "list.bullet.indent") {
                    dismissKeyboardAndToggle()
                }
                .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        GlassEffectContainer {
            HStack(spacing: 12) {
                GlassTodayButton {
                    navigateToToday()
                }

                GlassSearchBarTrigger {
                    showSearch = true
                }
            }
        }
        .padding(.horizontal, 28)
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

    // MARK: - Data

    /// Build the flat list of (block, indentLevel) entries for display.
    private func displayEntries() -> [(block: Block, indentLevel: Int)] {
        if let node = node {
            return node.flattenedDescendants(expanded: isExpanded).map { ($0.block, $0.indentLevel) }
        } else {
            if isExpanded {
                var result: [(Block, Int)] = []
                func walk(_ blocks: [Block]) {
                    for block in blocks {
                        result.append((block, block.depth))
                        walk(block.sortedChildren.filter { !$0.isArchived })
                    }
                }
                walk(rootBlocks)
                return result
            } else {
                return rootBlocks.map { ($0, 0) }
            }
        }
    }

    /// Flat list of blocks currently displayed.
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

        if isRoot {
            let _ = TodayNotesService.ensureRoot(context: modelContext)
            // Snapshot rootBlocks to avoid @Query timing race — the query
            // may not yet reflect the block inserted by ensureRoot.
            let blocks = rootBlocks
            if blocks.isEmpty {
                let block = Block(content: "", sortOrder: 1.0)
                modelContext.insert(block)
            } else {
                editableContent = blocks.map { $0.content }.joined(separator: "\n")
            }
        } else {
            buildEditableContent()
        }
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

        // Update existing blocks
        for i in 0..<min(parsed.count, blocks.count) {
            let (relativeDepth, content) = parsed[i]
            let absoluteDepth = baseDepth + 1 + relativeDepth

            // Guard: skip content sync for blocks not editable by user
            if blocks[i].content != content && blocks[i].isContentEditableByUser {
                blocks[i].content = content
                blocks[i].updatedAt = Date()
                dirtyTracker.markDirty(blocks[i].id)
            }

            // Skip depth/parent changes for non-movable blocks
            if blocks[i].depth != absoluteDepth && blocks[i].isMovable {
                let newParent = findParent(for: i, relativeDepth: relativeDepth, in: blocks, parsed: parsed)
                let newSortOrder = blocks[i].sortOrder
                blocks[i].move(to: newParent, sortOrder: newSortOrder)
                if blocks[i].depth != absoluteDepth {
                    blocks[i].depth = absoluteDepth
                }
                depthChanged = true

                // In node view (non-root, non-expanded), an indented block
                // gets reparented to a previous sibling. Expand the view
                // so the user can see the indented block as a child of
                // the line above, rather than navigating away.
                if !isRoot && !isExpanded, let newParent = newParent, newParent !== node {
                    isExpanded = true
                }
            }
        }

        // Create new blocks for extra lines
        if parsed.count > blocks.count {
            for i in blocks.count..<parsed.count {
                let (relativeDepth, content) = parsed[i]
                let absoluteDepth = baseDepth + 1 + relativeDepth
                let sortOrder = (blocks.last?.sortOrder ?? 0) + Double(i - blocks.count + 1)
                let newParent = findParent(for: i, relativeDepth: relativeDepth, in: blocks, parsed: parsed)
                let block = Block(content: content, parent: newParent ?? node, sortOrder: sortOrder)
                if block.depth != absoluteDepth {
                    block.depth = absoluteDepth
                }
                modelContext.insert(block)
                blocks.append(block)
                dirtyTracker.markDirty(block.id)
            }
        }

        // Delete excess blocks (skip non-deletable blocks)
        if blocks.count > parsed.count {
            for i in stride(from: blocks.count - 1, through: parsed.count, by: -1) {
                if blocks[i].isDeletable {
                    dirtyTracker.markDeleted(blocks[i].id)
                    modelContext.delete(blocks[i])
                }
            }
        }

        // When a block's depth/parent changed, rebuild content so the text editor stays in sync.
        if depthChanged {
            buildEditableContent()
        }
    }

    private func findParent(for index: Int, relativeDepth: Int, in blocks: [Block], parsed: [(depth: Int, content: String)]) -> Block? {
        if relativeDepth == 0 { return node }
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
        return node
    }

    // MARK: - Reorder

    private func reorderBlock(from source: Int, to destination: Int) {
        var blocks = currentBlocks()
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
        let maxValidDepth = (blockAbove?.depth ?? baseDepth) + 1
        let newDepth = min(movedBlock.depth, maxValidDepth)

        var newParent: Block? = node
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
            var correctParent: Block? = node
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

    private func navigateToToday() {
        let dayBlock = TodayNotesService.ensureToday(context: modelContext)
        if let node = node, dayBlock.id == node.id { return }
        navigationPath.append(dayBlock)
    }

    private func handleDoubleTap(at lineIndex: Int) {
        let blocks = currentBlocks()
        guard lineIndex >= 0, lineIndex < blocks.count else { return }
        let tappedBlock = blocks[lineIndex]
        navigationPath.append(tappedBlock)
    }

    private func navigateToSearchResult(blockId: UUID) {
        let descriptor = FetchDescriptor<Block>(
            predicate: #Predicate<Block> { $0.id == blockId }
        )
        guard let block = try? modelContext.fetch(descriptor).first else { return }

        // Build full ancestor path from root to block
        var path: [Block] = []
        var current: Block? = block
        while let b = current {
            path.insert(b, at: 0)
            current = b.parent
        }
        navigationPath = path
    }

    // MARK: - Auto-Building

    /// Trigger auto-building when navigating to any Today's Notes descendant.
    private func triggerAutoBuilding() {
        guard let node = node else { return }
        var current: Block? = node
        while let block = current {
            if block.content == "Today's Notes" && block.parent == nil {
                let _ = TodayNotesService.buildHierarchy(root: block, for: Date(), context: modelContext)
                return
            }
            current = block.parent
        }
    }

    // MARK: - Ancestor Path

    /// Walk the parent chain to build the full hierarchy path for the breadcrumb.
    private func buildAncestorPath() {
        guard let node = node else { return }
        var path: [Block] = []
        var current: Block? = node
        while let block = current {
            path.insert(block, at: 0)
            current = block.parent
        }
        ancestors = path
        logger.debug("[buildAncestorPath] \(path.map { $0.content }.joined(separator: " \u{2192} "))")
    }

    // MARK: - Expand/Collapse

    private func dismissKeyboardAndToggle() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isExpanded.toggle()
        }
    }
}
