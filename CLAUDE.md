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

Thin UI shell — SwiftUI views + UIKit TextKit 1 bridge for the editor.

```
Noto/
  NotoApp.swift              # App entry: vault setup → main app flow
  Storage/
    VaultLocationManager     # Persists vault location via security-scoped bookmark
    MarkdownNoteStore        # Note CRUD: list, create, read, write, delete .md files
    NoteTemplate             # Templates for note creation (daily note prompts)
  Editor/
    MarkdownTextStorage      # NSTextStorage subclass — live markdown syntax highlighting
    MarkdownEditorView       # UIKit UITextView wrapped for SwiftUI
  Views/
    NoteListView             # Main list of notes with folder navigation
    NoteEditorScreen         # Full editor screen (wraps MarkdownEditorView)
    VaultSetupView           # First-launch vault picker
    SettingsView             # App settings
```

### macOS-specific runtime rules

Two macOS rules matter for current app behavior:

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

3. **iOS iCloud note loading should trust real readability over metadata.**
   - Do not gate note opening only on `ubiquitousItemDownloadingStatus`.
   - Try a coordinated read first.
   - If the file is already readable, open it immediately.
   - Only use the iCloud download flow when the file is genuinely unreadable.
   - Root-level notes can fail differently from notes in subfolders if the app over-trusts metadata instead of actual file access.

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

Currently only one package. New packages will be added as features grow (search index, mentions, embeddings — see brainstorm doc).

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

## Build & Test

Use the `/flowdeck` skill for **all** build, test, simulator, and device operations. Do not use xcodebuildmcp MCP tools directly.

```bash
# Package-level (preferred for logic testing — no simulator needed)
cd Packages/NotoVault && swift test

# Test all packages
for pkg in Packages/*/; do (cd "$pkg" && swift test); done
```

For app-level builds, tests, simulator management, UI automation, log capture, device install — use `/flowdeck`.

### Simulator Isolation

Multiple Claude Code sessions may run concurrently. Each session MUST create and use its own dedicated simulator to avoid conflicts:

1. **Create:** `flowdeck simulator create --name "Noto-Test-<short-id>" --device-type "iPhone 16 Pro" --runtime "iOS 26"`
2. **Build/run to it:** `flowdeck run -S "Noto-Test-<short-id>"`
3. **Maestro against it:** `maestro --device <UDID> test .maestro/`
4. **Clean up when done**

Never use the default/shared simulator for testing. Use the first 8 chars of `$CLAUDE_SESSION_ID` as `<short-id>`.

## Unit Testing

Uses Swift Testing framework (`@Test` macro, `#expect`), not XCTest assertions.

## Conventions

- **Logging**: Always use `os_log` (`Logger`) instead of `print()`. Pattern: `private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "ClassName")`
- **SwiftLint**: `line_length` and `identifier_name` rules are disabled
- **Design docs**: PRD and brainstorm documents live in `.claude/` directory
- **Build & Simulator**: Use `/flowdeck` for all simulator build/run/test/UI inspection and device workflows.
- **UI/UX tasks**: Always build and deploy to the simulator after making UI changes, then visually verify with screenshots. Do not consider a UI/UX task complete without visual confirmation.
