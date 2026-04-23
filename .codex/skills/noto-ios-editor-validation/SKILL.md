---
name: noto-ios-editor-validation
description: Use for Noto iOS editor, markdown rendering, bullet/list indentation, keyboard toolbar, or simulator UI validation work. Prevents editing inactive editor paths, forgetting seeded vault setup, and under-testing multiline list behavior.
---

# Noto iOS Editor Validation

Use this skill whenever changing Noto's iOS editor rendering, list indentation, markdown styling, keyboard accessory toolbar, or simulator validation flows.

## Required workflow

1. Confirm the active editor path before editing.
   - Read `Noto/Views/NoteEditorScreen.swift`.
   - The live iOS editor is currently `TextKit2EditorView`, not `BlockEditorView`.
   - Only edit `BlockEditorView` when intentionally keeping legacy/inactive paths consistent.

2. For simulator UI validation, seed a vault before expecting note UI.
   - Build/install/run first so the app container exists.
   - Run `.maestro/seed-vault.sh <simulator-udid>`.
   - Relaunch with FlowDeck, then open a seeded note such as `Shopping List`.
   - Do not assume the first-run vault setup screen will initialize data by itself.

3. For bullet/list changes, validate all affected cases.
   - Single-line bullets.
   - Multiline wrapped bullets where continuation lines must align with first-line text.
   - Nested bullets/todos/ordered lists when indent progression changes.
   - Marker styling, including whether the intended marker is a muted dash or a dot.
   - Return-key continuation for list items, including empty-list exit behavior.
   - Hardware keyboard shortcuts: Tab indents selected/current lines and Shift-Tab outdents them.
   - Undo/redo after toolbar actions and keyboard shortcuts; programmatic transforms must participate in the native undo stack.
   - Todo rendering and interactions: unchecked empty circle, checked green circle with checkmark, and circle tap toggles markdown state.

4. For toolbar visual changes, capture the keyboard-visible state.
   - Tap the editor to show the keyboard.
   - Capture evidence with `flowdeck ui simulator screen`.
   - Check contrast, translucency, and pill shape against the requested Liquid Glass direction.

## Visual replacement pattern

Use this when backing markdown/text remains in the document but is replaced visually by a native control or overlay, such as `- [ ] ` becoming a todo circle followed by editable text.

- Keep the backing text as the source of truth for persistence, commands, undo/redo, and cross-platform sync.
- Separate semantic hiding from layout metrics. Structural marker characters can be clear or visually collapsed, but the insertion boundary next to editable content must keep normal body-font metrics.
- Always test the empty-content boundary. For todos, `- [ ] |` is a distinct case from `- [ ] text|`; the caret, selection rect, line height, and overlay position may be computed from different attributed runs.
- Preserve stable geometry for wrapping and hit testing: first-line indent, continuation indent, control frame, caret rect, and text start should all derive from shared visual specs.
- Validate on both platform text systems when the behavior affects attributed text metrics. `UITextView` and `NSTextView` can use different sources for insertion-point height and selection geometry.
- Prefer focused rendering tests that inspect attributed runs and paragraph styles, then add UI validation when the risk is visual or interaction-heavy.

## Test expectations

- Add or update focused unit tests for rendering math when possible.
- For TextKit2 markdown layout, prefer tests in `NotoTests/TextKit2MarkdownLayoutTests.swift`.
- After tests, run a FlowDeck simulator build and visual capture for UI-impacting changes.
- Run FlowDeck build/test/run commands sequentially in this workspace. Do not parallelize them unless each command has isolated DerivedData.

## Debug mode

If the user includes `[DEBUG]`, create `debug/noto-ios-editor-validation-<YYYYMMDD-HHMMSS>.md` in the current working directory.

Record:
- Active editor path inspected and conclusion.
- Files edited and why.
- Test commands and results.
- Simulator UDID, vault seeding command, and screenshots captured.
- Any skipped validation and why.

Report the debug file path in the conversation.
