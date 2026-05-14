# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Noto is an iOS note-taking app where every note is a **markdown file on disk**. Folders are real directories. The filesystem is the source of truth — no database for content storage.

The app is a **clean-sheet rewrite** (v2) of an earlier outline-based version. V1 code is preserved in `archive/` for reference but is not imported or compiled. The v2 brainstorm and design docs live in `.claude/Noto v2/`.

**Key concepts:**

- Notes are `.md` files with YAML frontmatter (UUID, timestamps)
- A "vault" is a user-chosen root directory containing all notes
- Daily notes auto-create in a `Daily Notes/` folder, one per day
- Note templates pre-populate content for specific note types (e.g. daily reflections)
- Markdown rendering with live syntax highlighting (headings, bold, italic, lists, checkmarks, code)
- All actions can be done by AI agents as well, not just by the user using GUI

**No external dependencies.** Pure Apple frameworks only.

## Principles

1. **Packages for all non-UI logic.** Any code that doesn't require UIKit/SwiftUI/AppKit must live in a local Swift package under `Packages/`. This ensures it can be built and tested independently via `swift build` / `swift test` — no Xcode project or simulator needed. The app target is a thin UI shell that imports packages; it should never contain business logic, data transformations, or service code.

2. **Test everything, regress nothing.** All work must be validated before it's considered done:
   - Write or update unit tests for any new or changed logic (package-level tests via `swift test`, app-level tests via `test_sim`).
   - Run the full relevant test suite — not just the new tests — to catch regressions against existing features.
   - For UI changes, build and deploy to the simulator, then visually verify with `snapshot_ui` and `screenshot`.

## Development Workflow

These are the standard workflows for all development work on this project. Follow them every time.

### Read the Architecture First

Before doing implementation, debugging, refactoring, or architecture work, read `README.md`. Treat it as the current architecture and lifecycle map for this repo, and use it to choose the right abstraction level, ownership boundary, and established pattern before editing code.

### New features → `/ios-development` skill

When asked to build any new feature or enhancement, always load and follow the `/ios-development` skill. This ensures a consistent flow: feature doc → tests → implementation → simulator verification.

### Bug fixes and corrections → `/ios-debug-flow` skill

When asked to fix a bug, or when something built doesn't work as expected, always load and follow the `/ios-debug-flow` skill. This ensures structured debugging: reproduce → diagnose → fix → verify.

### Editor code

- The live iOS/iPadOS editor is `TextKit2EditorView`, not `BlockEditorView`. Confirm through `Noto/Views/NoteEditorScreen.swift` before editing editor behavior.
- For Noto iOS editor, markdown rendering, bullet/list indentation, or keyboard toolbar work, use the project skill at `.codex/skills/noto-ios-editor-validation/SKILL.md`.

### Simulator UI validation

- Build and install first, then seed the isolated simulator vault with `.maestro/seed-vault.sh <simulator-udid>` before expecting note-list or editor UI.
- For bullet/list rendering changes, test and visually validate multiline wrapped bullets, not only single-line bullets; include nested levels when indent progression changes.
- For keyboard toolbar visual changes, capture a keyboard-visible screenshot and check pill shape, translucency, and icon contrast before concluding.

### Maestro

When running Maestro in this repo, prefer `scripts/run_maestro_isolated.sh` so parallel agents do not collide on the same simulator.

## Architecture

### Storage Model: Filesystem + Markdown

```
Vault/                          # user-chosen root folder
  Daily Notes/
    2026-03-16.md
  Projects/
    Project Alpha.md
```

Each `.md` file has YAML frontmatter:

```yaml
---
id: 550e8400-e29b-41d4-a716-446655440000
created: 2026-03-16T09:30:00Z
modified: 2026-03-16T14:22:00Z
---
```

The frontmatter UUID is the note's permanent identity. Filenames can change freely.

### App Target (`Noto/`)

Thin UI shell — SwiftUI views + UIKit TextKit 2 bridge for the editor.

```
Noto/
  NotoApp.swift              # App entry: vault setup → main app flow
  Storage/
    VaultLocationManager     # Persists vault location via security-scoped bookmark
    MarkdownNoteStore        # Note CRUD: list, create, read, write, delete .md files
    NoteTemplate             # Templates for note creation (daily note prompts)
  Editor/
    TextKit2EditorView       # UIKit UITextView (TextKit 2) wrapped for SwiftUI
  Views/
    NoteListView             # Main list of notes with folder navigation
    NoteEditorScreen         # Full editor screen (wraps TextKit2EditorView)
    VaultSetupView           # First-launch vault picker
    SettingsView             # App settings
```

### Runtime rules — macOS

1. **External vault access is a sandbox permission problem first, not an editor problem first.**
   - If the app can open notes but cannot save/delete them, check for `NSCocoaErrorDomain Code=513`.
   - The app must have `com.apple.security.files.user-selected.read-write`.
   - The saved security-scoped bookmark is the real access token.
   - Do not silently reopen an external vault from a remembered raw path if writability cannot be re-established.
   - If the bookmark/token is broken, force a clean folder re-pick.

2. **Same-app multi-window sync is separate from filesystem sync.**
   - Use the in-process note sync path for one window updating another window in the same running app.
   - Use `VaultFileWatcher` for true external changes: iCloud, Finder, or another process.
   - Do not rely on the debounced file watcher alone for same-process editor sync.

### Runtime rules — iOS iCloud

- Do not gate note opening only on `ubiquitousItemDownloadingStatus`. Try a coordinated read first.
- If the file is already readable, open it immediately. Only use the iCloud download flow when the file is genuinely unreadable.
- Root-level notes can fail differently from notes in subfolders if the app over-trusts metadata instead of actual file access.
- Prefer real filesystem outcomes over inferred metadata: actual write success on macOS, actual read success on iOS.

### Packages (`Packages/`)

Business logic extracted into local Swift packages, independently testable via CLI.

```
Packages/
  NotoVault/                 # Filesystem I/O: read/write .md files, frontmatter parsing
    Sources/NotoVault/
      VaultManager           # File CRUD: list, read, write, delete notes in vault dir
      NoteFile               # Note model: id, content, title (derived from first line), dates
      Frontmatter            # YAML frontmatter parser/serializer (id, created, modified)
```

New packages will be added as features grow (search index, mentions, embeddings — see brainstorm doc).

### When to Create a New Package vs. Add to Existing

- **New package**: Distinct responsibility with its own testable surface (e.g. search index, mention resolution, embedding pipeline).
- **Add to existing**: Utility or extension within an existing package's domain.
- **Never in app target**: If the code doesn't require UIKit/SwiftUI/AppKit, it belongs in a package.

### Archive (`archive/`)

V1 code preserved for reference. Not compiled, not imported.

```
archive/
  Noto/          # V1 app code (outline editor, AI chat views, TextKit stack)
  Packages/      # V1 packages (NotoModels, NotoCore, NotoFTS5, NotoHNSW, etc.)
  NotoUITests/   # V1 UI tests
  NotoTests/     # V1 unit tests
```

### Sharing Architecture

Default principle: make behavior as shared as possible across iOS, iPadOS, and macOS. Put non-UI logic in Swift packages such as `Packages/NotoVault` when it can stand alone. For UI, prefer shared SwiftUI views, shared view models/session objects, and small platform adapters over duplicating whole screens. Split by platform only when UIKit/AppKit APIs, navigation models, input systems, or platform conventions make sharing materially worse.

#### Note List and Sidebar

- Shared responsibilities include vault/directory loading, item ordering, note title resolution, filename/title rules, date formatting inputs, persistence contracts, and any reusable row/sidebar state not tied to a platform widget. Implement these in `Packages/NotoVault` or `Noto/Views/Shared/` when UI-bound.
- `NoteListView` is the platform entry point and may branch for compact iOS navigation, regular iPad layouts, and macOS split-window behavior. Keep those branches thin: navigation shell, toolbar placement, selection binding, and platform presentation differences only.
- `NotoSidebarView`, shared rows, loaders, and title/count helpers should remain cross-platform unless a concrete platform behavior requires a separate implementation.
- iOS and iPadOS should share list/sidebar logic by default. Separate iPad behavior only for size-class/navigation presentation differences, not for data loading or note/folder semantics.
- macOS-specific list/sidebar code is acceptable for native split view, commands, multi-window behavior, keyboard shortcuts, context menus, or AppKit/macOS conventions. Do not fork note list data rules just because the visual container differs.

#### Editor

- Shared editor responsibilities include `NoteEditorSession`, load/save/autosave, title updates, note renaming, same-process sync, iCloud/readability handling, markdown parsing, markdown editing transforms, todo markdown behavior, word/character counting, and styling rules that can be expressed platform-neutrally.
- `TextKit2EditorView.swift` has a shared upper layer for markdown block detection, frontmatter handling, visual specs, paragraph/inline styling, editing transforms coordination, and TextKit delegate behavior. Prefer adding new markdown/text semantics there first so iOS, iPadOS, and macOS benefit together.
- The concrete TextKit stacks are platform-specific: iOS/iPadOS use `UITextView` and its TextKit 2 stack; macOS uses `NSTextView` with its own AppKit TextKit setup. Platform-specific code should stay limited to native view construction, keyboard/input behavior, selection quirks, accessory/toolbars, click/tap handling, and AppKit/UIKit delegate differences.
- iOS/iPadOS-specific editor chrome lives in `Noto/Views/iOS/`; macOS-specific editor chrome lives in `Noto/Views/macOS/`; shared editor composition lives in `Noto/Views/Shared/`. Prefer moving common chrome concepts into shared abstractions before adding parallel platform implementations.
- The editor More actions menu is currently implemented separately for iOS/iPadOS and macOS. Do not assume changing one updates the other; either update both intentionally or explicitly keep the behavior platform-specific.
- For new editor features (hyperlinks, lists, inline marks, counters, note links): put parsing, transforms, models, and styling intent in shared code first; add only the minimum iOS/iPadOS and macOS adapters needed for native interaction.
- When replacing backing markdown/text with a visual element (e.g. rendering `- [ ] ` as a todo circle), keep the backing text and visual metrics aligned. The insertion boundary next to editable content must keep body-font metrics so caret, selection rects, hit testing, wrapping, and overlay placement remain stable on both `UITextView` and `NSTextView`. Add regression tests for the empty-content boundary, not only the populated case.

## Build & Test

Use the `/flowdeck` skill for **all** build, test, simulator, and device operations. Do not use xcodebuildmcp MCP tools directly.

```bash
# Package-level (preferred for logic testing — no simulator needed)
cd Packages/NotoVault && swift test

# Test all packages
for pkg in Packages/*/; do (cd "$pkg" && swift test); done
```

For app-level builds, tests, simulator management, UI automation, log capture, device install — use `/flowdeck`.

**Do not run multiple `flowdeck build`, `flowdeck run`, or `flowdeck test` invocations in parallel for this workspace.** They share DerivedData and can lock the build database.

### Simulator Isolation

Multiple Claude Code sessions may run concurrently. Each session MUST create and use its own dedicated simulator to avoid conflicts:

1. **Create:** `flowdeck simulator create --name "Noto-Test-<short-id>" --device-type "iPhone 16 Pro" --runtime "iOS 26"`
2. **Build/run to it:** `flowdeck run -S "Noto-Test-<short-id>"`
3. **Maestro against it:** `maestro --device <UDID> test .maestro/`
4. **Clean up when done**

Never use the default/shared simulator for testing. Use the first 8 chars of `$CLAUDE_SESSION_ID` as `<short-id>`.

When the user asks to test on simulator without naming a narrower device, install and launch on both an iPhone simulator and an iPad simulator. Prefer an iPad mini simulator for iPad unless the user specifies otherwise.

## Unit Testing

Uses Swift Testing framework (`@Test` macro, `#expect`), not XCTest assertions.

## Conventions

- **Logging**: Always use `os_log` (`Logger`) instead of `print()`. Pattern: `private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "ClassName")`
- **SwiftLint**: `line_length` and `identifier_name` rules are disabled
- **Design docs**: PRD and brainstorm documents live in `.claude/` directory
- **Build & Simulator**: Use `/flowdeck` for all simulator build/run/test/UI inspection and device workflows.
- **UI/UX tasks**: Always build and deploy to the simulator after making UI changes, then visually verify with screenshots. Do not consider a UI/UX task complete without visual confirmation.

## Operational Rules

### Notifications

Send macOS banner notifications only when:
1. Work is finished, or
2. User input is required to proceed.

Command: `~/.codex/bin/codex-notify "<status + needed input>" "Noto" "/Users/eugenechan/dev/personal/Noto"`

### Install behavior

When the user says "install", "install to all devices", or "install on my devices" without naming a narrower target, install on:
- Eugene's physical iPhone
- Eugene's physical iPad mini
- macOS

Do not use simulators for install requests unless the user explicitly says "simulator".

When installing the macOS app, always replace `/Applications/Noto.app` with the latest build — not merely run from DerivedData. Flow: build → stop running Noto processes → remove existing `/Applications/Noto.app` → copy freshly built `Noto.app` → `touch` it → re-register with Launch Services → launch `/Applications/Noto.app` → verify process path is `/Applications/Noto.app/Contents/MacOS/Noto`.

### Code changes

When the user reports a bug or asks for a code change, do the work directly unless blocked by a real ambiguity or a destructive tradeoff that requires confirmation. Do not ask for permission to make routine code changes, tests, or verification runs.

### Task completion

At the end of any completed task, report:
1. The actions taken
2. The files changed (grouped as created, edited, or deleted)

Keep the report concise and factual. If no files changed, say so.
