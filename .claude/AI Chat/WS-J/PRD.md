# PRD: WS-J — Edit Apply Flow

## Problem
When the AI suggests edits (add/update blocks), the user needs to preview the diff and accept or dismiss it. Currently the SuggestedEditCard only toggles local state — no actual block mutations happen.

## Goals
1. **AIEditApplier** — transactional applier that validates ALL operations before executing ANY (all-or-nothing)
2. **ViewModel wiring** — `acceptEdit` and `dismissEdit` methods that call the applier and update persistence
3. **Enhanced diff card** — show old vs new content for updates, context lines for additions

## Non-Goals
- Undo/redo support (future)
- Partial apply (explicitly rejected — all-or-nothing)
- Archive/delete operations (only add and update for v1)

## Design

### AIEditApplier
- `apply(proposal:proposalCreatedAt:context:dirtyTracker:) throws -> ApplyResult`
- **Phase 1 — Validate ALL**: for each op, check existence, editability, staleness
- **Phase 2 — Execute ALL**: only runs if all validations pass; uses BlockBuilder extensions
- Staleness check: `block.updatedAt <= proposalCreatedAt` (block not modified after proposal was created)

### Error Types
- `.blockNotFound(UUID)` — target block doesn't exist
- `.blockNotEditable(UUID)` — block has `isContentEditableByUser == false`
- `.staleBlock(blockId:blockUpdatedAt:proposalCreatedAt:)` — block was edited after proposal
- `.invalidParentChild(parentId:afterBlockId:)` — parent or afterSibling doesn't exist

### ViewModel Integration
- `acceptEdit(messageId:)` — calls applier, updates edit status to `.accepted`
- `dismissEdit(messageId:)` — updates edit status to `.dismissed`
- Both update the ChatMessage in the messages array

### SuggestedEditCard Enhancement
- Accept/Dismiss buttons call ViewModel methods via closures
- For updateBlock: show red deletion line (old) + green addition line (new)
- For addBlock: show green addition line with `+` marker
- After action: collapse to status label ("Edit accepted" / "Edit dismissed")
