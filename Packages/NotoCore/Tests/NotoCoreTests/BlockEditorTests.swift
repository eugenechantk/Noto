//
//  BlockEditorTests.swift
//  NotoCoreTests
//
//  TDD tests for BlockEditor — the middle layer that manages
//  block mutations for the outline editor.
//
//  ═══════════════════════════════════════════════════════════
//  TEST CASE INDEX
//  ═══════════════════════════════════════════════════════════
//
//  Load / Initialization
//  ─────────────────────
//  loadIncludesParent          — reload() includes root at line 0 plus children; expect 3 entries for root+2 children
//  loadCollapsed               — collapsed editor hides grandchildren; expect only root + direct children
//  loadExpanded                — expanded editor shows full subtree with indent levels; expect grandchild at indentLevel 1
//  loadChildrenSorted          — children appear sorted by sortOrder regardless of insertion order; expect A, B, C
//  loadEmptyParent             — root with no children loads as single entry; expect count == 1
//
//  Update Content
//  ──────────────
//  updateParentContent         — updateContent on line 0 modifies root's content and updatedAt; expect new content + later timestamp
//  updateChildContent          — updateContent on line 1 modifies that child's content; expect new string
//  updateGrandchildContent     — updateContent on expanded grandchild (line 2) works; expect new string
//  updateDeeplyNestedContent   — updateContent at depth 3 (line 3) works; expect new string
//  updatePreservesOtherBlocks  — updating one line leaves all other blocks unchanged; expect only target modified
//
//  Insert Line
//  ───────────
//  insertAfterParent           — insertLine(afterLine:0) creates sibling of root; expect parent == root.parent, empty content
//  insertBetweenChildren       — insertLine between two children uses fractional sortOrder; expect between A and B
//  insertAfterLastChild        — insertLine after last child gets sortOrder > last; expect sortOrder > B
//  insertInheritsDepth         — new block inherits depth of reference block; expect same depth as grandchild
//  insertReturnsNewBlock       — return value is the newly created empty block; expect content == "", correct parent
//
//  Delete Line
//  ───────────
//  deleteChild                 — deleteLine removes one child from entries; expect count decremented, ID gone
//  deleteParentDisallowed      — deleteLine(atLine:0) is a no-op (root protected); expect count unchanged
//  deleteChildWithDescendants  — deleting a child cascades to its subtree; expect child + grandchild both gone
//  deleteOnlyChild             — deleting the sole child leaves root alone; expect count == 1
//
//  Indent
//  ──────
//  indentChild                 — indent reparents block under previous sibling; expect parent == prev sibling, depth +1
//  indentFirstChildNoOp        — indent on first child (no prev sibling) is no-op; expect parent/depth unchanged
//  indentParentDisallowed      — indent on line 0 (root) is no-op; expect depth unchanged
//  indentUpdatesDescendants    — indent cascades depth +1 to all descendants; expect children depths +1
//  indentSortOrder             — after indent, block gets sortOrder < first existing child; expect sortOrder < X
//
//  Outdent
//  ───────
//  outdentGrandchild           — outdent reparents under grandparent; expect parent == root, sortOrder > old parent
//  outdentDirectChild          — outdent on direct child of root is no-op; expect parent/depth unchanged
//  outdentParentDisallowed     — outdent on line 0 (root) is no-op; expect depth unchanged
//  outdentUpdatesDescendants   — outdent cascades depth -1 to descendants; expect child depths -1
//
//  Move / Reorder
//  ──────────────
//  moveSiblingDown             — moveLine shifts block down among siblings; expect B, A, C order
//  moveSiblingUp               — moveLine shifts block up among siblings; expect C, A, B order
//  moveSiblingToEnd            — moveLine to end position works; expect A last
//  moveParentDisallowed        — moveLine on root (line 0) is no-op; expect count unchanged
//  movePreservesParent         — move doesn't change parent relationships; expect all still under root
//
//  Edge Cases
//  ──────────
//  parentOnlyNoChildren        — operations on root-only editor (insert, indent, outdent, delete) are safe; expect no crash
//  singleChild                 — indent/outdent/insert/delete on sole child are safe; expect correct state
//  deepNesting                 — 5-level chain: outdent leaf then re-indent; expect parent toggles correctly
//
//  Deep Tree Tests (4–5 levels)
//  ────────────────────────────
//  deepTreeLoadsCorrectOrder         — 13-node tree flattens in correct DFS order; expect exact content array
//  deepTreeIndentLevels              — indent levels match tree structure; expect [0,0,1,2,3,2,1,0,1,2,3,0,1]
//  insertAfterDeepLeaf               — insert after depth-4 leaf creates sibling under same parent; expect parent == A1a
//  insertAfterMidLevelNode           — insert after A1 creates sibling between A1 and A2; expect fractional sortOrder
//  insertAfterLastChildInBranch      — insert after B1a-i (deepest in B branch); expect parent == B1a
//  insertAfterC1CreatesC2            — insert after C1 creates C2 under C; expect parent == C, same depth
//  deleteSubtreeAtLevel2             — delete A1 cascades to A1a, A1a-i, A1b (4 removed); expect 9 remaining, A2 survives
//  deleteEntireBranch                — delete B removes B+B1+B1a+B1a-i; expect 9 remaining
//  deleteDeepLeafOnly                — delete depth-4 leaf removes only it; expect parent survives, 12 remaining
//  indentMovesBlockUnderPreviousSibling — indent A2 under A1; expect parent == A1, sortOrder < A1a
//  indentAtLevel3                    — indent A1b under A1a; expect parent == A1a, sortOrder < A1a-i
//  indentTopLevelBlockWithSubtree    — indent B under A cascades depth +1 to B1, B1a, B1a-i; expect all depths +1
//  indentFirstChildAtLevelIsNoOp     — indent A1a (first child of A1) is no-op; expect unchanged
//  indentC                           — indent C under B cascades depth to C1; expect C1.depth +1
//  outdentFromLevel4                 — outdent A1a-i from depth 4; expect parent == A1, sortOrder > A1a
//  outdentFromLevel3                 — outdent A1a cascades depth -1 to A1a-i; expect parent == A
//  outdentFromLevel2                 — outdent B1 to root level cascades depth -1 to B1a, B1a-i; expect parent == root
//  outdentDirectChildOfRootIsNoOp    — outdent A (direct child of root) is no-op; expect unchanged
//  outdentPushesLaterSiblings        — outdent A1 to root pushes B's sortOrder forward; expect B.sortOrder > A1
//  moveTopLevelSiblingDown           — move A past B; expect B first in top-level order
//  moveTopLevelSiblingUp             — move C before A; expect C first in top-level order
//  movePreservesSubtreeIntegrity     — move B to front; expect B1→B, B1a→B1, B1a-i→B1a intact
//  moveToSamePositionIsNoOp          — move B to same position; expect entries unchanged
//  indentThenOutdentRestoresOriginal — indent A2 then outdent; expect parent/depth restored
//  insertThenDeleteRestoresCount     — insert at deep leaf then delete; expect original count restored
//  deleteAfterIndentRemovesCorrectSubtree — indent B under A, delete A; expect only Root+C+C1 remain
//  multipleOutdentsToTop             — outdent B1a-i 3 times to root, 4th is no-op; expect parent == root
//  multipleIndentsToMaxDepth         — indent C under B, second indent is no-op (first child); expect parent == B
//

import Testing
import Foundation
import SwiftData
@testable import NotoCore
@testable import NotoModels

// All tests serialized to avoid SwiftData cascade-delete crashes
// when multiple in-memory stores run concurrently.
@Suite("BlockEditor", .serialized)
struct BlockEditorTests {

    // MARK: - Shared Helper

    @MainActor
    static func makeEditor(
        childContents: [String],
        expanded: Bool = false
    ) throws -> (editor: BlockEditor, root: Block, children: [Block]) {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1)
        context.insert(root)

        var children: [Block] = []
        for (i, content) in childContents.enumerated() {
            let child = Block(content: content, parent: root, sortOrder: Double(i + 1))
            context.insert(child)
            children.append(child)
        }

        let editor = BlockEditor(root: root, modelContext: context, expanded: expanded, retainContainer: container)
        return (editor, root, children)
    }

    // MARK: - Load / Initialization

    @Test @MainActor
    func loadIncludesParent() throws {
        let (editor, root, _) = try Self.makeEditor(childContents: ["A", "B"])
        #expect(editor.entries.count == 3)
        #expect(editor.entries[0].block.id == root.id)
        #expect(editor.entries[1].block.content == "A")
        #expect(editor.entries[2].block.content == "B")
    }

    @Test @MainActor
    func loadCollapsed() throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let root = Block(content: "Root", sortOrder: 1)
        context.insert(root)
        let child = Block(content: "Child", parent: root, sortOrder: 1)
        context.insert(child)
        let _ = Block(content: "Grandchild", parent: child, sortOrder: 1)

        let editor = BlockEditor(root: root, modelContext: context, expanded: false, retainContainer: container)
        #expect(editor.entries.count == 2)
        #expect(editor.entries[0].block.id == root.id)
        #expect(editor.entries[1].block.content == "Child")
    }

    @Test @MainActor
    func loadExpanded() throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let root = Block(content: "Root", sortOrder: 1)
        context.insert(root)
        let child = Block(content: "Child", parent: root, sortOrder: 1)
        context.insert(child)
        let _ = Block(content: "Grandchild", parent: child, sortOrder: 1)

        let editor = BlockEditor(root: root, modelContext: context, expanded: true, retainContainer: container)
        #expect(editor.entries.count == 3)
        #expect(editor.entries[1].indentLevel == 0)
        #expect(editor.entries[2].block.content == "Grandchild")
        #expect(editor.entries[2].indentLevel == 1)
    }

    @Test @MainActor
    func loadChildrenSorted() throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let root = Block(content: "Root", sortOrder: 1)
        context.insert(root)
        let _ = Block(content: "C", parent: root, sortOrder: 3)
        let _ = Block(content: "A", parent: root, sortOrder: 1)
        let _ = Block(content: "B", parent: root, sortOrder: 2)

        let editor = BlockEditor(root: root, modelContext: context, expanded: false, retainContainer: container)
        #expect(editor.entries[1].block.content == "A")
        #expect(editor.entries[2].block.content == "B")
        #expect(editor.entries[3].block.content == "C")
    }

    @Test @MainActor
    func loadEmptyParent() throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let root = Block(content: "Root", sortOrder: 1)
        context.insert(root)

        let editor = BlockEditor(root: root, modelContext: context, expanded: false, retainContainer: container)
        #expect(editor.entries.count == 1)
        #expect(editor.entries[0].block.id == root.id)
    }

    // MARK: - Update Content

    @Test @MainActor
    func updateParentContent() throws {
        let (editor, root, _) = try Self.makeEditor(childContents: ["A"])
        let oldDate = root.updatedAt
        editor.updateContent(atLine: 0, newContent: "New Root")
        #expect(root.content == "New Root")
        #expect(root.updatedAt > oldDate)
    }

    @Test @MainActor
    func updateChildContent() throws {
        let (editor, _, children) = try Self.makeEditor(childContents: ["Old"])
        editor.updateContent(atLine: 1, newContent: "New")
        #expect(children[0].content == "New")
    }

    @Test @MainActor
    func updateGrandchildContent() throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let root = Block(content: "Root", sortOrder: 1)
        context.insert(root)
        let child = Block(content: "Child", parent: root, sortOrder: 1)
        context.insert(child)
        let grandchild = Block(content: "Old", parent: child, sortOrder: 1)
        context.insert(grandchild)

        let editor = BlockEditor(root: root, modelContext: context, expanded: true, retainContainer: container)
        editor.updateContent(atLine: 2, newContent: "New")
        #expect(grandchild.content == "New")
    }

    @Test @MainActor
    func updateDeeplyNestedContent() throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let root = Block(content: "Root", sortOrder: 1)
        context.insert(root)
        let l1 = Block(content: "L1", parent: root, sortOrder: 1)
        context.insert(l1)
        let l2 = Block(content: "L2", parent: l1, sortOrder: 1)
        context.insert(l2)
        let l3 = Block(content: "L3", parent: l2, sortOrder: 1)
        context.insert(l3)

        let editor = BlockEditor(root: root, modelContext: context, expanded: true, retainContainer: container)
        editor.updateContent(atLine: 3, newContent: "Updated")
        #expect(l3.content == "Updated")
    }

    @Test @MainActor
    func updatePreservesOtherBlocks() throws {
        let (editor, root, children) = try Self.makeEditor(childContents: ["A", "B", "C"])
        editor.updateContent(atLine: 2, newContent: "B2")
        #expect(root.content == "Root")
        #expect(children[0].content == "A")
        #expect(children[1].content == "B2")
        #expect(children[2].content == "C")
    }

    // MARK: - Insert Line

    @Test @MainActor
    func insertAfterParent() throws {
        let (editor, root, children) = try Self.makeEditor(childContents: ["A"])
        let newBlock = editor.insertLine(afterLine: 0)
        #expect(newBlock.parent?.id == root.id)
        #expect(newBlock.depth == root.depth + 1)
        #expect(newBlock.content == "")
        #expect(newBlock.sortOrder < children[0].sortOrder) // inserted at top
    }

    @Test @MainActor
    func insertBetweenChildren() throws {
        let (editor, root, children) = try Self.makeEditor(childContents: ["A", "B"])
        let newBlock = editor.insertLine(afterLine: 1)
        #expect(newBlock.parent?.id == root.id)
        #expect(newBlock.sortOrder > children[0].sortOrder)
        #expect(newBlock.sortOrder < children[1].sortOrder)
    }

    @Test @MainActor
    func insertAfterLastChild() throws {
        let (editor, root, children) = try Self.makeEditor(childContents: ["A", "B"])
        let newBlock = editor.insertLine(afterLine: 2)
        #expect(newBlock.parent?.id == root.id)
        #expect(newBlock.sortOrder > children[1].sortOrder)
    }

    @Test @MainActor
    func insertInheritsDepth() throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let root = Block(content: "Root", sortOrder: 1)
        context.insert(root)
        let child = Block(content: "Child", parent: root, sortOrder: 1)
        context.insert(child)
        let grandchild = Block(content: "GC", parent: child, sortOrder: 1)
        context.insert(grandchild)

        let editor = BlockEditor(root: root, modelContext: context, expanded: true, retainContainer: container)
        let newBlock = editor.insertLine(afterLine: 2)
        #expect(newBlock.parent?.id == child.id)
        #expect(newBlock.depth == grandchild.depth)
    }

    @Test @MainActor
    func insertReturnsNewBlock() throws {
        let (editor, root, _) = try Self.makeEditor(childContents: ["A"])
        let newBlock = editor.insertLine(afterLine: 1)
        #expect(newBlock.content == "")
        #expect(newBlock.parent?.id == root.id)
        #expect(newBlock.depth == root.depth + 1)
    }

    // MARK: - Delete Line

    @Test @MainActor
    func deleteChild() throws {
        let (editor, _, children) = try Self.makeEditor(childContents: ["A", "B", "C"])
        let deletedId = children[1].id
        editor.deleteLine(atLine: 2)
        let ids = editor.entries.map { $0.block.id }
        #expect(!ids.contains(deletedId))
        #expect(editor.entries.count == 3)
    }

    @Test @MainActor
    func deleteParentDisallowed() throws {
        let (editor, root, _) = try Self.makeEditor(childContents: ["A", "B"])
        let countBefore = editor.entries.count
        editor.deleteLine(atLine: 0)
        #expect(editor.entries.count == countBefore)
        #expect(editor.entries[0].block.id == root.id)
    }

    @Test @MainActor
    func deleteChildWithDescendants() throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let root = Block(content: "Root", sortOrder: 1)
        context.insert(root)
        let child = Block(content: "Child", parent: root, sortOrder: 1)
        context.insert(child)
        let grandchild = Block(content: "GC", parent: child, sortOrder: 1)
        context.insert(grandchild)
        let childId = child.id
        let gcId = grandchild.id

        let editor = BlockEditor(root: root, modelContext: context, expanded: true, retainContainer: container)
        #expect(editor.entries.count == 3)
        editor.deleteLine(atLine: 1)
        let ids = editor.entries.map { $0.block.id }
        #expect(!ids.contains(childId))
        #expect(!ids.contains(gcId))
        #expect(editor.entries.count == 1)
    }

    @Test @MainActor
    func deleteOnlyChild() throws {
        let (editor, root, _) = try Self.makeEditor(childContents: ["A"])
        editor.deleteLine(atLine: 1)
        #expect(editor.entries.count == 1)
        #expect(editor.entries[0].block.id == root.id)
    }

    // MARK: - Indent

    @Test @MainActor
    func indentChild() throws {
        let (editor, _, children) = try Self.makeEditor(childContents: ["A", "B"])
        let blockA = children[0]
        let blockB = children[1]
        let depthBefore = blockB.depth
        editor.indentLine(atLine: 2)
        #expect(blockB.parent?.id == blockA.id)
        #expect(blockB.depth == depthBefore + 1)
    }

    @Test @MainActor
    func indentFirstChildNoOp() throws {
        let (editor, _, children) = try Self.makeEditor(childContents: ["A", "B"])
        let blockA = children[0]
        let depthBefore = blockA.depth
        let parentBefore = blockA.parent?.id
        editor.indentLine(atLine: 1)
        #expect(blockA.parent?.id == parentBefore)
        #expect(blockA.depth == depthBefore)
    }

    @Test @MainActor
    func indentParentDisallowed() throws {
        let (editor, root, _) = try Self.makeEditor(childContents: ["A"])
        let depthBefore = root.depth
        editor.indentLine(atLine: 0)
        #expect(root.depth == depthBefore)
    }

    @Test @MainActor
    func indentUpdatesDescendants() throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let root = Block(content: "Root", sortOrder: 1)
        context.insert(root)
        let a = Block(content: "A", parent: root, sortOrder: 1)
        context.insert(a)
        let b = Block(content: "B", parent: root, sortOrder: 2)
        context.insert(b)
        let b1 = Block(content: "B1", parent: b, sortOrder: 1)
        context.insert(b1)
        let b2 = Block(content: "B2", parent: b, sortOrder: 2)
        context.insert(b2)

        let editor = BlockEditor(root: root, modelContext: context, expanded: true, retainContainer: container)
        let b1DepthBefore = b1.depth
        let b2DepthBefore = b2.depth
        editor.indentLine(atLine: 2)
        #expect(b.parent?.id == a.id)
        #expect(b1.depth == b1DepthBefore + 1)
        #expect(b2.depth == b2DepthBefore + 1)
    }

    @Test @MainActor
    func indentSortOrder() throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let root = Block(content: "Root", sortOrder: 1)
        context.insert(root)
        let a = Block(content: "A", parent: root, sortOrder: 1)
        context.insert(a)
        let x = Block(content: "X", parent: a, sortOrder: 1)
        context.insert(x)
        let y = Block(content: "Y", parent: a, sortOrder: 2)
        context.insert(y)
        let b = Block(content: "B", parent: root, sortOrder: 2)
        context.insert(b)

        let editor = BlockEditor(root: root, modelContext: context, expanded: true, retainContainer: container)
        editor.indentLine(atLine: 4)
        #expect(b.parent?.id == a.id)
        #expect(b.sortOrder < x.sortOrder) // B is first child of A
    }

    // MARK: - Outdent

    @Test @MainActor
    func outdentGrandchild() throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let root = Block(content: "Root", sortOrder: 1)
        context.insert(root)
        let a = Block(content: "A", parent: root, sortOrder: 1)
        context.insert(a)
        let g = Block(content: "G", parent: a, sortOrder: 1)
        context.insert(g)

        let editor = BlockEditor(root: root, modelContext: context, expanded: true, retainContainer: container)
        editor.outdentLine(atLine: 2)
        #expect(g.parent?.id == root.id)
        #expect(g.sortOrder > a.sortOrder)
    }

    @Test @MainActor
    func outdentDirectChild() throws {
        let (editor, _, children) = try Self.makeEditor(childContents: ["A"])
        let blockA = children[0]
        let parentBefore = blockA.parent?.id
        let depthBefore = blockA.depth
        editor.outdentLine(atLine: 1)
        #expect(blockA.parent?.id == parentBefore)
        #expect(blockA.depth == depthBefore)
    }

    @Test @MainActor
    func outdentParentDisallowed() throws {
        let (editor, root, _) = try Self.makeEditor(childContents: ["A"])
        let depthBefore = root.depth
        editor.outdentLine(atLine: 0)
        #expect(root.depth == depthBefore)
    }

    @Test @MainActor
    func outdentUpdatesDescendants() throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let root = Block(content: "Root", sortOrder: 1)
        context.insert(root)
        let a = Block(content: "A", parent: root, sortOrder: 1)
        context.insert(a)
        let g = Block(content: "G", parent: a, sortOrder: 1)
        context.insert(g)
        let gg = Block(content: "GG", parent: g, sortOrder: 1)
        context.insert(gg)

        let editor = BlockEditor(root: root, modelContext: context, expanded: true, retainContainer: container)
        let ggDepthBefore = gg.depth
        editor.outdentLine(atLine: 2)
        #expect(g.parent?.id == root.id)
        #expect(gg.depth == ggDepthBefore - 1)
    }

    // MARK: - Move / Reorder

    @Test @MainActor
    func moveSiblingDown() throws {
        let (editor, _, _) = try Self.makeEditor(childContents: ["A", "B", "C"])
        // to:3 = insert before position 3 (before C) → B, A, C
        editor.moveLine(from: 1, to: 3)
        editor.reload()
        #expect(editor.entries[1].block.content == "B")
        #expect(editor.entries[2].block.content == "A")
        #expect(editor.entries[3].block.content == "C")
    }

    @Test @MainActor
    func moveSiblingUp() throws {
        let (editor, _, _) = try Self.makeEditor(childContents: ["A", "B", "C"])
        editor.moveLine(from: 3, to: 1)
        editor.reload()
        #expect(editor.entries[1].block.content == "C")
        #expect(editor.entries[2].block.content == "A")
        #expect(editor.entries[3].block.content == "B")
    }

    @Test @MainActor
    func moveSiblingToEnd() throws {
        let (editor, _, _) = try Self.makeEditor(childContents: ["A", "B", "C"])
        editor.moveLine(from: 1, to: 4)
        editor.reload()
        #expect(editor.entries[1].block.content == "B")
        #expect(editor.entries[2].block.content == "C")
        #expect(editor.entries[3].block.content == "A")
    }

    @Test @MainActor
    func moveParentDisallowed() throws {
        let (editor, root, _) = try Self.makeEditor(childContents: ["A", "B"])
        let countBefore = editor.entries.count
        editor.moveLine(from: 0, to: 2)
        #expect(editor.entries[0].block.id == root.id)
        #expect(editor.entries.count == countBefore)
    }

    @Test @MainActor
    func movePreservesParent() throws {
        let (editor, root, _) = try Self.makeEditor(childContents: ["A", "B", "C"])
        editor.moveLine(from: 2, to: 1)
        editor.reload()
        for i in 1..<editor.entries.count {
            #expect(editor.entries[i].block.parent?.id == root.id)
        }
    }

    // MARK: - Edge Cases

    @Test @MainActor
    func parentOnlyNoChildren() throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let root = Block(content: "Root", sortOrder: 1)
        context.insert(root)

        let editor = BlockEditor(root: root, modelContext: context, expanded: false, retainContainer: container)
        _ = editor.insertLine(afterLine: 0)
        editor.reload()
        #expect(editor.entries.count >= 1)
        editor.indentLine(atLine: 0)
        #expect(root.depth == 0)
        editor.outdentLine(atLine: 0)
        #expect(root.depth == 0)
        editor.deleteLine(atLine: 0)
        #expect(editor.entries[0].block.id == root.id)
    }

    @Test @MainActor
    func singleChild() throws {
        let (editor, root, children) = try Self.makeEditor(childContents: ["A"])
        let blockA = children[0]
        editor.indentLine(atLine: 1)
        #expect(blockA.parent?.id == root.id)
        editor.outdentLine(atLine: 1)
        #expect(blockA.parent?.id == root.id)
        let newBlock = editor.insertLine(afterLine: 1)
        #expect(newBlock.parent?.id == root.id)
        editor.deleteLine(atLine: 1)
    }

    @Test @MainActor
    func deepNesting() throws {
        let container = try createTestContainer()
        let context = container.mainContext
        let root = Block(content: "Root", sortOrder: 1)
        context.insert(root)

        var current = root
        var blocks: [Block] = []
        for i in 1...5 {
            let block = Block(content: "L\(i)", parent: current, sortOrder: 1)
            context.insert(block)
            blocks.append(block)
            current = block
        }

        let editor = BlockEditor(root: root, modelContext: context, expanded: true, retainContainer: container)
        #expect(editor.entries.count == 6)

        let l5 = blocks[4]
        let l4 = blocks[3]
        editor.outdentLine(atLine: 5)
        #expect(l5.parent?.id == l4.parent?.id)

        editor.reload()
        let l5Line = editor.entries.firstIndex(where: { $0.block.id == l5.id })!
        editor.indentLine(atLine: l5Line)
        #expect(l5.parent?.id == l4.id)
    }

    // MARK: - Deep Tree Tests (4–5 levels)

    // Shared helper that builds a wide, deep tree:
    //
    //   Root
    //   ├── A (depth 1)
    //   │   ├── A1 (depth 2)
    //   │   │   ├── A1a (depth 3)
    //   │   │   │   └── A1a-i (depth 4)
    //   │   │   └── A1b (depth 3)
    //   │   └── A2 (depth 2)
    //   ├── B (depth 1)
    //   │   └── B1 (depth 2)
    //   │       └── B1a (depth 3)
    //   │           └── B1a-i (depth 4)
    //   └── C (depth 1)
    //       └── C1 (depth 2)
    //
    // Flattened (expanded) lines:
    //   0: Root
    //   1: A
    //   2: A1
    //   3: A1a
    //   4: A1a-i
    //   5: A1b
    //   6: A2
    //   7: B
    //   8: B1
    //   9: B1a
    //  10: B1a-i
    //  11: C
    //  12: C1

    struct DeepTree {
        let container: ModelContainer
        let context: ModelContext
        let editor: BlockEditor
        let root: Block
        let a: Block, a1: Block, a1a: Block, a1ai: Block, a1b: Block, a2: Block
        let b: Block, b1: Block, b1a: Block, b1ai: Block
        let c: Block, c1: Block
    }

    @MainActor
    static func makeDeepTree() throws -> DeepTree {
        let container = try createTestContainer()
        let context = container.mainContext

        let root = Block(content: "Root", sortOrder: 1)
        context.insert(root)

        // Level 1
        let a = Block(content: "A", parent: root, sortOrder: 1)
        context.insert(a)
        let b = Block(content: "B", parent: root, sortOrder: 2)
        context.insert(b)
        let c = Block(content: "C", parent: root, sortOrder: 3)
        context.insert(c)

        // Level 2
        let a1 = Block(content: "A1", parent: a, sortOrder: 1)
        context.insert(a1)
        let a2 = Block(content: "A2", parent: a, sortOrder: 2)
        context.insert(a2)
        let b1 = Block(content: "B1", parent: b, sortOrder: 1)
        context.insert(b1)
        let c1 = Block(content: "C1", parent: c, sortOrder: 1)
        context.insert(c1)

        // Level 3
        let a1a = Block(content: "A1a", parent: a1, sortOrder: 1)
        context.insert(a1a)
        let a1b = Block(content: "A1b", parent: a1, sortOrder: 2)
        context.insert(a1b)
        let b1a = Block(content: "B1a", parent: b1, sortOrder: 1)
        context.insert(b1a)

        // Level 4
        let a1ai = Block(content: "A1a-i", parent: a1a, sortOrder: 1)
        context.insert(a1ai)
        let b1ai = Block(content: "B1a-i", parent: b1a, sortOrder: 1)
        context.insert(b1ai)

        let editor = BlockEditor(root: root, modelContext: context, expanded: true, retainContainer: container)

        return DeepTree(
            container: container, context: context, editor: editor, root: root,
            a: a, a1: a1, a1a: a1a, a1ai: a1ai, a1b: a1b, a2: a2,
            b: b, b1: b1, b1a: b1a, b1ai: b1ai,
            c: c, c1: c1
        )
    }

    // -- Load / structure verification --

    @Test @MainActor
    func deepTreeLoadsCorrectOrder() throws {
        let t = try Self.makeDeepTree()
        let contents = t.editor.entries.map { $0.block.content }
        #expect(contents == ["Root", "A", "A1", "A1a", "A1a-i", "A1b", "A2", "B", "B1", "B1a", "B1a-i", "C", "C1"])
    }

    @Test @MainActor
    func deepTreeIndentLevels() throws {
        let t = try Self.makeDeepTree()
        let levels = t.editor.entries.map { $0.indentLevel }
        // Root=0, A=0, A1=1, A1a=2, A1a-i=3, A1b=2, A2=1, B=0, B1=1, B1a=2, B1a-i=3, C=0, C1=1
        #expect(levels == [0, 0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 0, 1])
    }

    // -- Insert across levels --

    @Test @MainActor
    func insertAfterDeepLeaf() throws {
        let t = try Self.makeDeepTree()
        // Insert after A1a-i (line 4, depth 4). New block should be sibling of A1a-i.
        let newBlock = t.editor.insertLine(afterLine: 4)
        #expect(newBlock.parent?.id == t.a1a.id)
        #expect(newBlock.depth == t.a1ai.depth)
        #expect(newBlock.sortOrder > t.a1ai.sortOrder)
    }

    @Test @MainActor
    func insertAfterMidLevelNode() throws {
        let t = try Self.makeDeepTree()
        // Insert after A1 (line 2). New block should be sibling of A1 (child of A).
        let newBlock = t.editor.insertLine(afterLine: 2)
        #expect(newBlock.parent?.id == t.a.id)
        #expect(newBlock.depth == t.a1.depth)
        // Should sit between A1 (sortOrder 1) and A2 (sortOrder 2)
        #expect(newBlock.sortOrder > t.a1.sortOrder)
        #expect(newBlock.sortOrder < t.a2.sortOrder)
    }

    @Test @MainActor
    func insertAfterLastChildInBranch() throws {
        let t = try Self.makeDeepTree()
        // Insert after B1a-i (line 10, deepest leaf in B branch).
        let newBlock = t.editor.insertLine(afterLine: 10)
        #expect(newBlock.parent?.id == t.b1a.id)
        #expect(newBlock.sortOrder > t.b1ai.sortOrder)
    }

    @Test @MainActor
    func insertAfterC1CreatesC2() throws {
        let t = try Self.makeDeepTree()
        // Insert after C1 (line 12). Should create sibling of C1 under C.
        let newBlock = t.editor.insertLine(afterLine: 12)
        #expect(newBlock.parent?.id == t.c.id)
        #expect(newBlock.sortOrder > t.c1.sortOrder)
        #expect(newBlock.depth == t.c1.depth)
    }

    // -- Delete across levels --

    @Test @MainActor
    func deleteSubtreeAtLevel2() throws {
        let t = try Self.makeDeepTree()
        // Delete A1 (line 2) — should also remove A1a, A1a-i, A1b (4 blocks total).
        let removedIds: Set<UUID> = [t.a1.id, t.a1a.id, t.a1ai.id, t.a1b.id]
        t.editor.deleteLine(atLine: 2)
        let remainingIds = Set(t.editor.entries.map { $0.block.id })
        for id in removedIds {
            #expect(!remainingIds.contains(id))
        }
        // A2 should survive
        #expect(remainingIds.contains(t.a2.id))
        // Total: 13 - 4 = 9
        #expect(t.editor.entries.count == 9)
    }

    @Test @MainActor
    func deleteEntireBranch() throws {
        let t = try Self.makeDeepTree()
        // Delete B (line 7) — removes B, B1, B1a, B1a-i (4 blocks).
        let removedIds: Set<UUID> = [t.b.id, t.b1.id, t.b1a.id, t.b1ai.id]
        t.editor.deleteLine(atLine: 7)
        let remainingIds = Set(t.editor.entries.map { $0.block.id })
        for id in removedIds {
            #expect(!remainingIds.contains(id))
        }
        #expect(t.editor.entries.count == 9)
    }

    @Test @MainActor
    func deleteDeepLeafOnly() throws {
        let t = try Self.makeDeepTree()
        // Delete A1a-i (line 4, a leaf at depth 4). Only that block removed.
        t.editor.deleteLine(atLine: 4)
        let remainingIds = Set(t.editor.entries.map { $0.block.id })
        #expect(!remainingIds.contains(t.a1ai.id))
        #expect(remainingIds.contains(t.a1a.id)) // parent survives
        #expect(t.editor.entries.count == 12)
    }

    // -- Indent across levels --

    @Test @MainActor
    func indentMovesBlockUnderPreviousSibling() throws {
        let t = try Self.makeDeepTree()
        // Indent A2 (line 6). Previous sibling is A1. A2 becomes first child of A1.
        let depthBefore = t.a2.depth
        t.editor.indentLine(atLine: 6)
        #expect(t.a2.parent?.id == t.a1.id)
        #expect(t.a2.depth == depthBefore + 1)
        // A2 should come before A1a (first child of A1 before the indent)
        #expect(t.a2.sortOrder < t.a1a.sortOrder)
    }

    @Test @MainActor
    func indentAtLevel3() throws {
        let t = try Self.makeDeepTree()
        // Indent A1b (line 5). Previous sibling is A1a. A1b becomes first child of A1a.
        let depthBefore = t.a1b.depth
        t.editor.indentLine(atLine: 5)
        #expect(t.a1b.parent?.id == t.a1a.id)
        #expect(t.a1b.depth == depthBefore + 1)
        // Should be placed before A1a-i (first child)
        #expect(t.a1b.sortOrder < t.a1ai.sortOrder)
    }

    @Test @MainActor
    func indentTopLevelBlockWithSubtree() throws {
        let t = try Self.makeDeepTree()
        // Indent B (line 7). Previous sibling is A. B becomes child of A.
        // B1, B1a, B1a-i depths should all increase by 1.
        let bDepthBefore = t.b.depth
        let b1DepthBefore = t.b1.depth
        let b1aDepthBefore = t.b1a.depth
        let b1aiDepthBefore = t.b1ai.depth
        t.editor.indentLine(atLine: 7)
        #expect(t.b.parent?.id == t.a.id)
        #expect(t.b.depth == bDepthBefore + 1)
        #expect(t.b1.depth == b1DepthBefore + 1)
        #expect(t.b1a.depth == b1aDepthBefore + 1)
        #expect(t.b1ai.depth == b1aiDepthBefore + 1)
    }

    @Test @MainActor
    func indentFirstChildAtLevelIsNoOp() throws {
        let t = try Self.makeDeepTree()
        // Indent A1a (line 3). It's the first child of A1 — no previous sibling → no-op.
        let parentBefore = t.a1a.parent?.id
        let depthBefore = t.a1a.depth
        t.editor.indentLine(atLine: 3)
        #expect(t.a1a.parent?.id == parentBefore)
        #expect(t.a1a.depth == depthBefore)
    }

    @Test @MainActor
    func indentC() throws {
        let t = try Self.makeDeepTree()
        // Indent C (line 11). Previous sibling is B. C becomes child of B.
        // C1 depth should also increase.
        let c1DepthBefore = t.c1.depth
        t.editor.indentLine(atLine: 11)
        #expect(t.c.parent?.id == t.b.id)
        #expect(t.c1.depth == c1DepthBefore + 1)
    }

    // -- Outdent across levels --

    @Test @MainActor
    func outdentFromLevel4() throws {
        let t = try Self.makeDeepTree()
        // Outdent A1a-i (line 4, depth 4). Should become sibling of A1a (child of A1).
        t.editor.outdentLine(atLine: 4)
        #expect(t.a1ai.parent?.id == t.a1.id)
        #expect(t.a1ai.sortOrder > t.a1a.sortOrder)
    }

    @Test @MainActor
    func outdentFromLevel3() throws {
        let t = try Self.makeDeepTree()
        // Outdent A1a (line 3, depth 3). Should become sibling of A1 (child of A).
        // A1a-i should cascade: its depth decreases by 1.
        let a1aiDepthBefore = t.a1ai.depth
        t.editor.outdentLine(atLine: 3)
        #expect(t.a1a.parent?.id == t.a.id)
        #expect(t.a1a.sortOrder > t.a1.sortOrder)
        #expect(t.a1ai.depth == a1aiDepthBefore - 1)
    }

    @Test @MainActor
    func outdentFromLevel2() throws {
        let t = try Self.makeDeepTree()
        // Outdent B1 (line 8, depth 2). Should become sibling of B (child of root).
        // B1a and B1a-i depths should decrease by 1.
        let b1aDepthBefore = t.b1a.depth
        let b1aiDepthBefore = t.b1ai.depth
        t.editor.outdentLine(atLine: 8)
        #expect(t.b1.parent?.id == t.root.id)
        #expect(t.b1.sortOrder > t.b.sortOrder)
        #expect(t.b1a.depth == b1aDepthBefore - 1)
        #expect(t.b1ai.depth == b1aiDepthBefore - 1)
    }

    @Test @MainActor
    func outdentDirectChildOfRootIsNoOp() throws {
        let t = try Self.makeDeepTree()
        // Outdent A (line 1). It's a direct child of root → no-op.
        let parentBefore = t.a.parent?.id
        let depthBefore = t.a.depth
        t.editor.outdentLine(atLine: 1)
        #expect(t.a.parent?.id == parentBefore)
        #expect(t.a.depth == depthBefore)
    }

    @Test @MainActor
    func outdentPushesLaterSiblings() throws {
        let t = try Self.makeDeepTree()
        // Outdent A1 (line 2). It becomes sibling of A under root.
        // Its sortOrder should be between A and B.
        t.editor.outdentLine(atLine: 2)
        #expect(t.a1.parent?.id == t.root.id)
        #expect(t.a1.sortOrder > t.a.sortOrder)
        // B's sortOrder should have been pushed forward
        #expect(t.b.sortOrder > t.a1.sortOrder)
    }

    // -- Move across levels --

    @Test @MainActor
    func moveTopLevelSiblingDown() throws {
        let t = try Self.makeDeepTree()
        // Move A (line 1) to after B's subtree. In flattened: move from 1 to 8 (before B1).
        // But moveLine only works with same-parent siblings, so move among top-level.
        // A is at sibling position 0, move to position after B → moveLine(from:1, to:8)
        // Note: moveLine reorders within the parent's children.
        t.editor.moveLine(from: 1, to: 8)
        t.editor.reload()
        // After move, order among root's children should be: B, A, C
        let topLevel = t.editor.entries.filter { $0.block.parent?.id == t.root.id }
        let topContents = topLevel.map { $0.block.content }
        #expect(topContents.first == "B")
    }

    @Test @MainActor
    func moveTopLevelSiblingUp() throws {
        let t = try Self.makeDeepTree()
        // Move C (line 11) to position 1 (before A)
        t.editor.moveLine(from: 11, to: 1)
        t.editor.reload()
        let topLevel = t.editor.entries.filter { $0.block.parent?.id == t.root.id }
        #expect(topLevel.first?.block.content == "C")
    }

    @Test @MainActor
    func movePreservesSubtreeIntegrity() throws {
        let t = try Self.makeDeepTree()
        // Move B (line 7) to beginning. After reload, B's subtree should remain intact.
        t.editor.moveLine(from: 7, to: 1)
        t.editor.reload()
        // B1 should still be child of B
        #expect(t.b1.parent?.id == t.b.id)
        // B1a should still be child of B1
        #expect(t.b1a.parent?.id == t.b1.id)
        // B1a-i should still be child of B1a
        #expect(t.b1ai.parent?.id == t.b1a.id)
    }

    @Test @MainActor
    func moveToSamePositionIsNoOp() throws {
        let t = try Self.makeDeepTree()
        let contentsBefore = t.editor.entries.map { $0.block.content }
        t.editor.moveLine(from: 7, to: 7)
        t.editor.reload()
        let contentsAfter = t.editor.entries.map { $0.block.content }
        #expect(contentsBefore == contentsAfter)
    }

    // -- Combined operations --

    @Test @MainActor
    func indentThenOutdentRestoresOriginal() throws {
        let t = try Self.makeDeepTree()
        let parentBefore = t.a2.parent?.id
        let depthBefore = t.a2.depth

        // Indent A2 → becomes child of A1
        t.editor.indentLine(atLine: 6)
        #expect(t.a2.parent?.id == t.a1.id)

        // Find A2's new line index and outdent it back
        t.editor.reload()
        let a2Line = t.editor.entries.firstIndex(where: { $0.block.id == t.a2.id })!
        t.editor.outdentLine(atLine: a2Line)
        #expect(t.a2.parent?.id == parentBefore)
        #expect(t.a2.depth == depthBefore)
    }

    @Test @MainActor
    func insertThenDeleteRestoresCount() throws {
        let t = try Self.makeDeepTree()
        let countBefore = t.editor.entries.count

        // Insert after A1a-i (deep leaf)
        t.editor.insertLine(afterLine: 4)
        t.editor.reload()
        #expect(t.editor.entries.count == countBefore + 1)

        // Find the new block (empty content, child of A1a)
        let newLine = t.editor.entries.firstIndex(where: { $0.block.content == "" })!
        t.editor.deleteLine(atLine: newLine)
        #expect(t.editor.entries.count == countBefore)
    }

    @Test @MainActor
    func deleteAfterIndentRemovesCorrectSubtree() throws {
        let t = try Self.makeDeepTree()
        // Indent B into A, then delete A → should remove A and everything underneath,
        // including B's subtree that was just moved there.
        t.editor.indentLine(atLine: 7)
        t.editor.reload()

        // Delete A (line 1) — should cascade to A1, A1a, A1a-i, A1b, A2, B, B1, B1a, B1a-i
        t.editor.deleteLine(atLine: 1)
        let remainingIds = Set(t.editor.entries.map { $0.block.id })
        #expect(!remainingIds.contains(t.a.id))
        #expect(!remainingIds.contains(t.b.id))
        #expect(!remainingIds.contains(t.b1ai.id))
        // Only Root, C, C1 should remain
        #expect(remainingIds.contains(t.root.id))
        #expect(remainingIds.contains(t.c.id))
        #expect(remainingIds.contains(t.c1.id))
    }

    @Test @MainActor
    func multipleOutdentsToTop() throws {
        let t = try Self.makeDeepTree()
        // Outdent B1a-i repeatedly until it's a direct child of root.
        // Start: B1a-i is at depth 4, child of B1a.
        // 1st outdent: child of B1
        // 2nd outdent: child of B
        // 3rd outdent: child of root
        // 4th outdent: no-op (already direct child of root)

        // Outdent 1: B1a-i → child of B1
        var line = t.editor.entries.firstIndex(where: { $0.block.id == t.b1ai.id })!
        t.editor.outdentLine(atLine: line)
        #expect(t.b1ai.parent?.id == t.b1.id)

        // Outdent 2: B1a-i → child of B
        t.editor.reload()
        line = t.editor.entries.firstIndex(where: { $0.block.id == t.b1ai.id })!
        t.editor.outdentLine(atLine: line)
        #expect(t.b1ai.parent?.id == t.b.id)

        // Outdent 3: B1a-i → child of root
        t.editor.reload()
        line = t.editor.entries.firstIndex(where: { $0.block.id == t.b1ai.id })!
        t.editor.outdentLine(atLine: line)
        #expect(t.b1ai.parent?.id == t.root.id)

        // Outdent 4: already direct child of root → no-op
        t.editor.reload()
        line = t.editor.entries.firstIndex(where: { $0.block.id == t.b1ai.id })!
        t.editor.outdentLine(atLine: line)
        #expect(t.b1ai.parent?.id == t.root.id)
    }

    @Test @MainActor
    func multipleIndentsToMaxDepth() throws {
        let t = try Self.makeDeepTree()
        // Indent C under B. Since indent places as first child, C becomes
        // first child of B (before B1). A second indent would be a no-op
        // because C has no previous sibling under B.
        //
        // To go deeper, we'd need C to be AFTER a sibling. So this test
        // verifies: indent once works, second indent is a no-op.

        // 1. Indent C (child of root → first child of B)
        var line = t.editor.entries.firstIndex(where: { $0.block.id == t.c.id })!
        t.editor.indentLine(atLine: line)
        #expect(t.c.parent?.id == t.b.id)

        // 2. Indent C again — no-op (C is first child of B, no previous sibling)
        t.editor.reload()
        line = t.editor.entries.firstIndex(where: { $0.block.id == t.c.id })!
        t.editor.indentLine(atLine: line)
        #expect(t.c.parent?.id == t.b.id) // unchanged

        // C1 should have cascaded with C
        #expect(t.c1.depth == t.c.depth + 1)
    }
}
