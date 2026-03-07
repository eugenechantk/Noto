# SPEC: WS-J — Edit Apply Flow

## Files to Create/Modify

### New: `Packages/NotoAIChat/Sources/NotoAIChat/AIEditApplier.swift`
- `EditApplyError` enum with 4 cases
- `AppliedOp` struct tracking what was done
- `ApplyResult` struct with `appliedOps` and `appliedAt`
- `AIEditApplier.apply()` static method — validate-then-execute

### Modified: `Packages/NotoAIChat/Sources/NotoAIChat/AIChatViewModel.swift`
- Add `acceptEdit(messageId:)` and `dismissEdit(messageId:)` methods
- Both find the edit block, call applier/update status, refresh messages array

### Modified: `Noto/Views/AIChat/SuggestedEditCard.swift`
- Add `onAccept` and `onDismiss` closures
- For updateBlock ops: show old content (red) + new content (green)
- Wire buttons to closures

### New: `Packages/NotoAIChat/Tests/NotoAIChatTests/AIEditApplierTests.swift`
- 9 test cases covering happy path, staleness, permissions, all-or-nothing, accept/dismiss

## Algorithm: AIEditApplier.apply()

```
function apply(proposal, proposalCreatedAt, context, dirtyTracker):
  // Phase 1: Validate
  for each op in proposal.operations:
    if op is addBlock:
      fetch parent by parentId — if nil, throw blockNotFound(parentId)
      if afterBlockId specified:
        fetch afterBlock — if nil, throw invalidParentChild
    if op is updateBlock:
      fetch block by blockId — if nil, throw blockNotFound(blockId)
      if !block.isContentEditableByUser, throw blockNotEditable(blockId)
      if block.updatedAt > proposalCreatedAt, throw staleBlock(...)

  // Phase 2: Execute (only reached if ALL validations pass)
  var appliedOps = []
  for each op in proposal.operations:
    if op is addBlock:
      newBlock = BlockBuilder.addBlock(content, parent, afterSibling, nil, context)
      dirtyTracker.markDirty(newBlock.id)
      appliedOps.append(.added(newBlock.id))
    if op is updateBlock:
      oldContent = block.content
      BlockBuilder.updateBlock(block, newContent)
      dirtyTracker.markDirty(block.id)
      appliedOps.append(.updated(block.id, oldContent))

  return ApplyResult(appliedOps, Date())
```

## Test Matrix

| Test | Input | Expected |
|------|-------|----------|
| addBlock happy path | valid parentId | new block created under parent |
| updateBlock happy path | valid blockId, editable | content changed |
| combo add+update | both valid | both applied |
| stale block | block.updatedAt > proposalCreatedAt | throws staleBlock |
| not editable | isContentEditableByUser=false | throws blockNotEditable |
| block not found | nonexistent UUID | throws blockNotFound |
| all-or-nothing | 2 ops, second fails validation | neither applied |
| accept flow | call acceptEdit | status = .accepted |
| dismiss flow | call dismissEdit | status = .dismissed |
