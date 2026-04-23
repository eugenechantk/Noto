# Workspace Agent Instructions

- Send macOS banner notifications only in these cases:
  `1)` when work is finished, or
  `2)` when user input is required to proceed.
- Command:
  `~/.codex/bin/codex-notify "<status + needed input>" "Noto" "/Users/eugenechan/dev/personal/Noto"`
- Keep title as `Codex-Noto`.
- For simulator-based testing or automation, always use an isolated simulator instance instead of a shared booted device.
- When running Maestro in this repo, prefer `scripts/run_maestro_isolated.sh` so parallel agents do not collide on the same simulator.
- For Noto iOS editor, markdown rendering, bullet/list indentation, or keyboard toolbar work, use the project skill at `.codex/skills/noto-ios-editor-validation/SKILL.md`.
- Before editing editor code, confirm the active editor path through `Noto/Views/NoteEditorScreen.swift`; the live iOS editor is currently `TextKit2EditorView`, not `BlockEditorView`.
- For iOS simulator UI validation, build/install first, then seed the isolated simulator vault with `.maestro/seed-vault.sh <simulator-udid>` before expecting note-list or editor UI.
- For bullet/list rendering changes, test and visually validate multiline wrapped bullets, not only single-line bullets; include nested levels when indent progression changes.
- For keyboard toolbar visual changes, capture a keyboard-visible screenshot and check pill shape, translucency, and icon contrast before concluding.
- Do not run multiple `flowdeck build`, `flowdeck run`, or `flowdeck test` invocations in parallel for this workspace; they share DerivedData and can lock the build database.
- When the user asks to `install` the macOS app, always treat that as replacing `/Applications/Noto.app` with the latest macOS build, not merely running the app from DerivedData. Use the deterministic install flow: build with FlowDeck, stop running Noto processes, remove the existing `/Applications/Noto.app`, copy in the freshly built `Noto.app`, `touch` it, re-register it with Launch Services, launch `/Applications/Noto.app`, and verify the running process path is `/Applications/Noto.app/Contents/MacOS/Noto`.
- At the end of any completed task, explicitly report:
  `1)` the actions taken, and
  `2)` the files changed, grouped as created, edited, or deleted when applicable.
- Keep that completion report concise and factual. If no files changed, say so.
- When the user reports a bug or asks for a code change, do the work directly unless blocked by a real ambiguity or a destructive tradeoff that requires confirmation.
- Do not ask for permission to make routine code changes, tests, or verification runs when the user has already asked for the problem to be solved.
- For macOS external-vault save/delete bugs, do not assume the editor is at fault first. Check sandbox entitlements, security-scoped bookmark resolution, and actual write errors before changing editor code.
- For multi-window note behavior, distinguish same-process window sync from external filesystem sync. Same-app windows should use the in-process sync path; `VaultFileWatcher` is only the fallback for external changes.
- For iOS iCloud note-open failures, do not assume the file is missing just because iCloud metadata says it needs download. Check whether the file is actually readable first.
- For iCloud-backed notes in general, prefer real filesystem outcomes over inferred metadata: actual write success on macOS, actual read success on iOS.

## Sharing Architecture

- Default principle: make behavior as shared as possible across iOS, iPadOS, and macOS. Put non-UI logic in Swift packages such as `Packages/NotoVault` when it can stand alone. For UI, prefer shared SwiftUI views, shared view models/session objects, and small platform adapters over duplicating whole screens. Split by platform only when UIKit/AppKit APIs, navigation models, input systems, or platform conventions make sharing materially worse.

### Note List and Sidebar

- Shared responsibilities should include vault/directory loading, item ordering, note title resolution, filename/title rules, date formatting inputs, persistence contracts, and any reusable row/sidebar state that is not tied to a platform widget. Prefer implementing these in `Packages/NotoVault` or in `Noto/Views/Shared/` when UI-bound.
- `NoteListView` is the platform entry point and may branch for compact iOS navigation, regular iPad layouts, and macOS split-window behavior. Keep those branches thin: navigation shell, toolbar placement, selection binding, and platform presentation differences belong there.
- `NotoSidebarView`, `NotoSplitView`, shared rows, loaders, and title/count helpers should remain cross-platform unless a concrete platform behavior requires a separate implementation.
- iOS and iPadOS should share list/sidebar logic by default. Separate iPad behavior only for size-class/navigation presentation differences, not for data loading or note/folder semantics.
- macOS-specific list/sidebar code is acceptable for native split view, commands, multi-window behavior, keyboard shortcuts, context menus, or AppKit/macOS conventions. Do not fork note list data rules just because the visual container differs.

### Editor

- Shared editor responsibilities include `NoteEditorSession`, load/save/autosave, title updates, note renaming, same-process sync, iCloud/readability handling, remote-update conflict UI intent, markdown parsing, markdown editing transforms, todo markdown behavior, word/character counting, and styling rules that can be expressed platform-neutrally.
- The live iOS/iPadOS editor is `TextKit2EditorView`, not `BlockEditorView`. Confirm through `Noto/Views/NoteEditorScreen.swift` before editing editor behavior.
- `TextKit2EditorView.swift` has a shared upper layer for markdown block detection, frontmatter handling, visual specs, paragraph/inline styling, editing transforms coordination, and TextKit delegate behavior. Prefer adding new markdown/text semantics there first so iOS, iPadOS, and macOS benefit together.
- The concrete TextKit stacks are platform-specific: iOS/iPadOS use `UITextView` and its TextKit 2 stack; macOS uses `NSTextView` with its own AppKit TextKit setup. Platform-specific code should stay limited to native view construction, keyboard/input behavior, selection quirks, accessory/toolbars, click/tap handling, and AppKit/UIKit delegate differences.
- iOS/iPadOS-specific editor chrome lives in `Noto/Views/iOS/`; macOS-specific editor chrome lives in `Noto/Views/macOS/`; shared editor composition lives in `Noto/Views/Shared/`. Prefer moving common chrome concepts into shared abstractions before adding parallel platform implementations.
- The editor More actions menu is currently implemented separately for iOS/iPadOS and macOS in their platform chrome files. Do not assume changing one updates the other; either update both intentionally or explicitly keep the behavior platform-specific.
- For new editor features such as hyperlinks, lists, inline marks, counters, or note links: put parsing, transforms, models, and styling intent in shared code first; add only the minimum iOS/iPadOS and macOS adapters needed for native interaction.
- When replacing backing markdown/text with a visual element, such as rendering `- [ ] ` as a todo circle before editable text, keep the backing text and visual metrics deliberately aligned. Hidden structural characters may be clear or visually collapsed, but the insertion boundary next to editable content must keep body-font metrics so the caret, selection rects, hit testing, wrapping, and overlay placement remain stable on both `UITextView` and `NSTextView`. Add regression tests for the empty-content boundary, not only the populated case.
