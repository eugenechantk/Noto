import Foundation
import Testing
@testable import NotoEdit

// Test index
//  - Resolution: each edit type happy path / not-found / ambiguous / empty
//  - Additions: start, end, after-anchor, before-anchor
//  - Grouping: same-spot delete+add → 1 block; line 9 + line 12 → 2 blocks; adjacent merge
//  - Apply: single block, multiple blocks, offset correctness, overlap rejected, stale range
//  - Deletion: trailing-newline cleanup
//  - Context lines: clamped at note bounds; expand flags
//  - Per-block accept independence
//  - Unicode / multi-byte range correctness
//  - LineDiff: pure add, pure remove, replace, mixed

private let sampleNote = """
# Pricing notes

## Intro
The pricing page is honestly our most important conversion surface.

## Tiers
- Free
- Pro $29

## Open questions
- [ ] confirm annual discount with finance

## Legacy
Legacy $9 tier stays available to all grandfathered accounts.
"""

// MARK: - Resolution: edit

@Test("edit resolves a unique target to a replace op")
func editHappyPath() {
    let (blocks, unresolved) = EditApplier.plan(
        [.edit(target: "Pro $29", replacement: "Pro $25")], in: sampleNote)
    #expect(unresolved.isEmpty)
    #expect(blocks.count == 1)
    #expect(blocks[0].ops.count == 1)
    #expect(blocks[0].ops[0].kind == .edit)
    #expect(blocks[0].ops[0].status == .resolved)
}

@Test("edit with no match is unresolved notFound")
func editNotFound() {
    let (blocks, unresolved) = EditApplier.plan(
        [.edit(target: "does not exist", replacement: "x")], in: sampleNote)
    #expect(blocks.isEmpty)
    #expect(unresolved.count == 1)
    #expect(unresolved[0].status == .unresolved(.notFound))
}

@Test("edit with multiple matches is unresolved ambiguous")
func editAmbiguous() {
    // "## " appears before several headings — ambiguous.
    let (blocks, unresolved) = EditApplier.plan(
        [.edit(target: "## ", replacement: "### ")], in: sampleNote)
    #expect(blocks.isEmpty)
    #expect(unresolved.count == 1)
    if case .unresolved(.ambiguous(let count)) = unresolved[0].status {
        #expect(count > 1)
    } else {
        Issue.record("expected ambiguous, got \(unresolved[0].status)")
    }
}

@Test("empty target is unresolved empty")
func editEmpty() {
    let (_, unresolved) = EditApplier.plan([.edit(target: "", replacement: "x")], in: sampleNote)
    #expect(unresolved.first?.status == .unresolved(.empty))
}

// MARK: - Resolution: deletion + trailing newline

@Test("deletion removes the target and its trailing newline when it owns the line")
func deletionTrailingNewline() throws {
    let edits: [ProposedEdit] = [.deletion(target: "- Free")]
    let (blocks, _) = EditApplier.plan(edits, in: sampleNote)
    #expect(blocks.count == 1)
    let result = try EditApplier.apply(blocks, to: sampleNote)
    #expect(!result.contains("- Free"))
    // The "- Pro $29" line must remain and not be merged onto the previous line.
    #expect(result.contains("\n- Pro $29"))
}

// MARK: - Additions

@Test("addition at end of document")
func additionEnd() throws {
    let edits: [ProposedEdit] = [.addition(anchor: .endOfDocument, content: "\n\n## New\nhi")]
    let (blocks, _) = EditApplier.plan(edits, in: sampleNote)
    #expect(blocks.count == 1)
    let result = try EditApplier.apply(blocks, to: sampleNote)
    #expect(result.hasSuffix("## New\nhi"))
}

@Test("addition at start of document")
func additionStart() throws {
    let edits: [ProposedEdit] = [.addition(anchor: .startOfDocument, content: "TOP\n")]
    let (blocks, _) = EditApplier.plan(edits, in: sampleNote)
    let result = try EditApplier.apply(blocks, to: sampleNote)
    #expect(result.hasPrefix("TOP\n# Pricing notes"))
}

@Test("addition after an anchor inserts a new line shown as a pure + row")
func additionAfterAnchor() throws {
    let edits: [ProposedEdit] = [
        .addition(anchor: .after("- [ ] confirm annual discount with finance"),
                  content: "\n- [ ] revisit Q3 tiers before the August review")
    ]
    let (blocks, unresolved) = EditApplier.plan(edits, in: sampleNote)
    #expect(unresolved.isEmpty)
    #expect(blocks.count == 1)
    // The inserted line should appear as an added row, the anchor line as context.
    let added = blocks[0].preview.lines.filter { $0.kind == .added }
    #expect(added.contains { $0.text.contains("revisit Q3 tiers") })
    #expect(blocks[0].preview.lines.contains { $0.kind == .context && $0.text.contains("confirm annual discount") })
    let result = try EditApplier.apply(blocks, to: sampleNote)
    #expect(result.contains("confirm annual discount with finance\n- [ ] revisit Q3 tiers"))
}

@Test("addition before an anchor")
func additionBeforeAnchor() throws {
    let edits: [ProposedEdit] = [.addition(anchor: .before("## Legacy"), content: "## Spotlight\nnew\n\n")]
    let (blocks, _) = EditApplier.plan(edits, in: sampleNote)
    let result = try EditApplier.apply(blocks, to: sampleNote)
    #expect(result.contains("## Spotlight\nnew\n\n## Legacy"))
}

@Test("addition after a non-unique anchor is ambiguous")
func additionAmbiguousAnchor() {
    let (blocks, unresolved) = EditApplier.plan(
        [.addition(anchor: .after("\n\n"), content: "x")], in: sampleNote)
    #expect(blocks.isEmpty)
    #expect(unresolved.count == 1)
    if case .unresolved(.ambiguous) = unresolved[0].status {} else {
        Issue.record("expected ambiguous")
    }
}

// MARK: - Grouping

@Test("same-spot replace expressed as delete+add coalesces into ONE block")
func sameSpotMergesToOneBlock() {
    let edits: [ProposedEdit] = [
        .deletion(target: "- Pro $29"),
        .addition(anchor: .after("- Free"), content: "\n- Pro $25")
    ]
    let (blocks, unresolved) = EditApplier.plan(edits, in: sampleNote)
    #expect(unresolved.isEmpty)
    #expect(blocks.count == 1)          // adjacent lines → one spot
    #expect(blocks[0].ops.count == 2)
}

@Test("changes at distant spots produce SEPARATE blocks (Eugene's line-9 / line-12 rule)")
func distantSpotsAreSeparateBlocks() {
    // Two edits several lines apart → two blocks.
    let edits: [ProposedEdit] = [
        .edit(target: "The pricing page is honestly our most important conversion surface.",
              replacement: "Pricing is our top conversion surface."),
        .deletion(target: "Legacy $9 tier stays available to all grandfathered accounts.")
    ]
    let (blocks, unresolved) = EditApplier.plan(edits, in: sampleNote)
    #expect(unresolved.isEmpty)
    #expect(blocks.count == 2)
}

// MARK: - Apply: multiple blocks + offsets + overlap

@Test("applying multiple blocks together preserves offsets")
func applyMultipleBlocks() throws {
    let edits: [ProposedEdit] = [
        .edit(target: "Pro $29", replacement: "Pro $25"),
        .edit(target: "Legacy $9", replacement: "Legacy $5")
    ]
    let (blocks, _) = EditApplier.plan(edits, in: sampleNote)
    #expect(blocks.count == 2)
    let result = try EditApplier.apply(blocks, to: sampleNote)
    #expect(result.contains("Pro $25"))
    #expect(result.contains("Legacy $5"))
}

@Test("accepting one block applies only that spot")
func acceptOneBlockOnly() throws {
    let edits: [ProposedEdit] = [
        .edit(target: "Pro $29", replacement: "Pro $25"),
        .edit(target: "Legacy $9", replacement: "Legacy $5")
    ]
    let (blocks, _) = EditApplier.plan(edits, in: sampleNote)
    let result = try EditApplier.apply([blocks[0]], to: sampleNote)
    #expect(result.contains("Pro $25"))
    #expect(result.contains("Legacy $9"))   // untouched
}

@Test("overlapping ops are rejected")
func overlappingRejected() {
    let body = "alpha beta gamma"
    let opA = ResolvedOp(kind: .edit, range: NSRange(location: 0, length: 10), replacement: "X",
                         status: .resolved, source: .edit(target: "a", replacement: "X"))
    let opB = ResolvedOp(kind: .edit, range: NSRange(location: 6, length: 5), replacement: "Y",
                         status: .resolved, source: .edit(target: "b", replacement: "Y"))
    let preview = DiffPreview(lines: [], canExpandUp: false, canExpandDown: false)
    let block = EditBlock(ops: [opA, opB], span: NSRange(location: 0, length: 11), preview: preview, locationHint: nil)
    #expect(throws: EditApplyError.overlappingEdits) {
        _ = try EditApplier.apply([block], to: body)
    }
}

@Test("a stale out-of-bounds range throws rather than corrupting")
func staleRangeThrows() {
    let body = "short"
    let op = ResolvedOp(kind: .edit, range: NSRange(location: 100, length: 5), replacement: "X",
                        status: .resolved, source: .edit(target: "x", replacement: "X"))
    let block = EditBlock(ops: [op], span: op.range,
                          preview: DiffPreview(lines: [], canExpandUp: false, canExpandDown: false), locationHint: nil)
    #expect(throws: EditApplyError.rangeOutOfBounds) {
        _ = try EditApplier.apply([block], to: body)
    }
}

// MARK: - Empty document boundary

@Test("addition into an empty document works")
func additionIntoEmptyDocument() throws {
    let (blocks, _) = EditApplier.plan(
        [.addition(anchor: .endOfDocument, content: "first line")], in: "")
    #expect(blocks.count == 1)
    let result = try EditApplier.apply(blocks, to: "")
    #expect(result == "first line")
}

// MARK: - Context lines + expand flags

@Test("context lines are clamped at the start of the note and flag no expand-up")
func contextClampedAtStart() {
    let (blocks, _) = EditApplier.plan(
        [.edit(target: "# Pricing notes", replacement: "# Pricing")], in: sampleNote, contextRadius: 5)
    #expect(blocks.count == 1)
    #expect(blocks[0].preview.canExpandUp == false)         // nothing above line 1
    #expect(blocks[0].preview.canExpandDown == true)        // plenty below
}

@Test("expand toggle re-renders with more context")
func expandAddsContext() {
    let (blocks, _) = EditApplier.plan(
        [.edit(target: "Pro $29", replacement: "Pro $25")], in: sampleNote, contextRadius: 1)
    let tight = blocks[0].preview.lines.count
    let expanded = EditApplier.preview(for: blocks[0], in: sampleNote, contextBefore: 6, contextAfter: 6)
    #expect(expanded.lines.count > tight)
}

// MARK: - Location hint

@Test("block carries the nearest preceding heading as a location hint")
func locationHint() {
    let (blocks, _) = EditApplier.plan(
        [.edit(target: "Pro $29", replacement: "Pro $25")], in: sampleNote)
    #expect(blocks[0].locationHint == "Tiers")
}

// MARK: - Unicode

@Test("multi-byte characters keep ranges correct")
func unicodeRanges() throws {
    let body = "café ☕️ notes\nsecond café line"
    let (blocks, unresolved) = EditApplier.plan(
        [.edit(target: "second café line", replacement: "second espresso line")], in: body)
    #expect(unresolved.isEmpty)
    let result = try EditApplier.apply(blocks, to: body)
    #expect(result == "café ☕️ notes\nsecond espresso line")
}

// MARK: - LineDiff unit

@Test("LineDiff: pure addition keeps the anchor line as context")
func lineDiffPureAdd() {
    let rows = LineDiff.diff(before: ["A"], after: ["A", "B"])
    #expect(rows == [DiffLine(kind: .context, text: "A"), DiffLine(kind: .added, text: "B")])
}

@Test("LineDiff: replace shows removed then added")
func lineDiffReplace() {
    let rows = LineDiff.diff(before: ["old"], after: ["new"])
    #expect(rows == [DiffLine(kind: .removed, text: "old"), DiffLine(kind: .added, text: "new")])
}

@Test("LineDiff: pure deletion")
func lineDiffDelete() {
    let rows = LineDiff.diff(before: ["A", "B"], after: ["A"])
    #expect(rows == [DiffLine(kind: .context, text: "A"), DiffLine(kind: .removed, text: "B")])
}
