# Noto 2 — a separate three-screen iOS app, reusing Noto's parts

**Date:** 2026-08-23 · **Status (2026-08-24):** Stage 1 built — see `.codex/feature/noto2-app.md` for what shipped, tests, and residual risks. UI follows `.claude/design/noto2/noto2-ui-brief.md`. Stage 2 (packages) still open.
**Ask:** an independent iOS app ("Noto 2") with exactly three screens — Capture (editor + send), Search (hybrid results + streamed LLM summary), Explorer — reusing the editor, search, storage already built.

## Reuse inventory (measured, not assumed)

| Piece | Location | Coupling | Verdict |
|---|---|---|---|
| Markdown editor | `Noto/Editor/TextKit2EditorView.swift` (8.2k) + `NoteEditorSession`, `TodoMarkdown`, `EditableFrontmatter`, `EditorFind`, `NoteContentCache`, `FrontmatterBlockLayout` | `Noto/Support/DebugTrace.swift` + packages `NotoVault` `NotoSearch` `NotoTags` | reuse as-is |
| Storage | `Noto/Storage/*` (VaultLocationManager, MarkdownNoteStore, VaultController, CoordinatedFileManager, VaultFileWatcher) | no UI deps | reuse as-is (should be a package per CLAUDE.md — Stage 2) |
| Search engine | `Packages/NotoSearch` (FTS5 + semantic + `SearchIndexCoordinator`) | package | free |
| LLM streaming | `Packages/NotoChat` `OpenRouterClient` + `Noto/Chat/OpenRouterKeyStore.swift`, `OpenRouterBaseURLStore.swift` | package + 2 files | free |
| Search UI | `NoteSearchSheet` at `NoteListView.swift:2111` inside a 3.8k-line file | tangled (Settings, Chat, deep links) | write a lean new one |
| Explorer UI | `Noto/Views/Shared/NotoSidebarView.swift` (643) clean; `NoteListView.swift` (3.8k) tangled | — | reuse sidebar + `MarkdownNoteStore`; thin new screen |

## The fork

| Option | Independence | Cost to first screen | Sharing |
|---|---|---|---|
| **A. Second app target in `Noto.xcodeproj`, same repo** — recommended | separate bundle id / icon / entitlements / sandbox / TestFlight; coexists on device | ~1 day | dual file membership + shared packages |
| B. Second Xcode project, same repo | + own pbxproj | must package editor/storage first (days) | local packages only |
| C. Separate repo | maximal | B + git-pinned packages, two checkouts | versioned packages |

**Decision: A, staged.**
- **Stage 1** — target `Noto2` (iOS only), bundle id `com.eugenechan.Noto2`, own `Noto2/` source folder with `Noto2App.swift` + three screens. Add Editor/Storage/Support(DebugTrace)/Chat key-store files to both targets. Packages already shared.
- **Stage 2** (once Noto 2 is real) — extract `Packages/NotoStorage` (no UI) and `Packages/NotoEditorKit` (TextKit2 editor + session; UI in a package is fine), both apps import them. Dual-membership in Stage 1 is what surfaces the couplings to cut.

## Screens

1. **Capture** — `TextKit2EditorView` full-screen, Send → `inbox/<YYYY-MM-DD>-<sha8>.md`, frontmatter `type: note`, `created`, `status: inbox` (same shape as `gbrain capture`; see `gbrain-noto-capabilities.md`). Clear editor after send; haptic; undo-able via Explorer.
2. **Search** — `NotoSearch` hybrid (keyword ∪ semantic, RRF). Results list renders first; then `OpenRouterClient` streams a summary of the top-N bodies into a header card. Settings *sheet* (not screen) for OpenRouter key via `OpenRouterKeyStore`.
3. **Explorer** — `NotoSidebarView` folders + note rows from `MarkdownNoteStore`; tap → same editor. No properties/tags/chat/deep-links day one.

Vault: own sandbox → first-launch folder pick via `VaultLocationManager` (point at `Brain/`); own search index built on first run.

## Mechanics / risks
- Add the target with the `xcodeproj` Ruby gem (ships with fastlane), not hand-edits to `project.pbxproj`.
- Working tree is heavily dirty (deep links, tags, CLI, vault pkgs). Land it via `/session-cleanup` first, or start Noto 2 in a worktree off `main`.
- Multiplatform `#if os(macOS)` branches in shared files compile out on an iOS-only target — fine.
- Separate sandbox means separate search index + separate vault bookmark; both expected.

## Build order
1. Scaffold target + Capture screen → on device.
2. Explorer (sidebar + list + open in editor).
3. Search (results) → then streamed summary + key sheet.
4. Stage 2 package extraction.
