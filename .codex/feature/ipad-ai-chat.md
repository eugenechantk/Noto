# Feature: iPadOS AI Chat

## User Story
As an iPad user, I want the same AI chat as on iPhone — same sheet UI, same styling, same behavior — reachable from the iPad layout (sidebar + editor).

## User Flow
1. iPad regular layout (NotoSplitView). User taps a chat entry control (sidebar; editor toolbar).
2. The shared `ChatSheet` presents (same large sheet, glass header, composer, tool trace, citations).
3. Tapping a citation/source dismisses the sheet and opens the note in the split detail.
4. Reopening chat shows the same conversation (shared `ChatSessionStore` via environment).

## Success Criteria
- SC1: On iPad (regular size class), a chat entry control exists and presents `ChatSheet`.
- SC2: The presented chat looks/behaves identically to compact iOS (same `chatSheetContent`).
- SC3: Opening a citation/source from chat opens the note in the iPad detail and dismisses the sheet.
- SC4: Chat state persists across dismiss/reopen and across navigation (shared store already wired).
- SC5: No API key → routes to Settings (consistent with compact).
- SC6: Editor on iPad can also open chat (with the current note pre-seeded if no session yet).

## Test Strategy
This is UI integration of already-tested components (`ChatSheet`, `ChatSession`, `ChatSessionStore`,
`ChatAgent`). No new platform-neutral logic → no new Swift unit tests. Proof is visual on an iPad
simulator (FlowDeck) + the existing 39 NotoChat package tests remaining green.

## Tests
- Existing: `Packages/NotoChat/Tests/NotoChatTests/*` (39 tests) — must stay green.
- Visual (iPad sim): entry present, sheet presents, citation opens note in detail, reopen retains state.

## Implementation Details
- Add `.sheet(isPresented: $showChat) { chatSheetContent }` to the `NotoSplitView` (regular) branch.
- Add a chat entry control in the iPad chrome (sidebar action row and/or split editor toolbar) firing
  `handleWorkspaceIntent(.openChat)`.
- Reuse `presentChat()` / `chatSheetContent` unchanged (already `.presentationDetents([.large])`).

## Status — DONE (verified live on iPad sim E2706BF2, iPad mini)
- SC1 ✓ sidebar header chat button (`sidebar_chat_button`, bubble.left) + editor dock `chat_button`.
- SC2 ✓ ChatSheet presents as a centered page sheet with identical styling (glass header, empty
  state, composer, tool trace with left rule, inline citations, SOURCES).
- SC3 ✓ tapping the SOURCES row dismissed the sheet and opened the note in the iPad detail pane.
- SC4 ✓ reopening chat after navigating to another note showed the same conversation (shared store).
- SC5 ✓ no key → routed to Settings; entered key → chat opens.
- SC6 ✓ editor dock chat button opens chat and retains the conversation.
- 39 NotoChat package tests still green.

## Residual Risks
- iPad sheet renders as a native centered page sheet (not full-bleed). Looks correct/native; if a
  full-width panel is later desired, revisit `.presentationDetents`/sizing for regular width.
- Discovery: the iPad editor already had a working dock chat entry (`onOpenChat` wired); the gap was
  the list/sidebar entry + the split-branch `.sheet`, both now added.

## Bugs
_None._
