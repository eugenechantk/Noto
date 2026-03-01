# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Noto is a universal Apple (iOS/macOS) outline-based note-taking app. Each note entry is a **Block** that can be infinitely nested. The app uses SwiftUI + SwiftData for the UI/data layer, with a custom UIKit TextKit 1 stack for rich text editing.

No external dependencies — pure Apple frameworks only.

## Simulator Isolation (IMPORTANT)

Multiple Claude Code sessions and worktrees may run concurrently. **Each session MUST use its own dedicated simulator** to avoid conflicts.

### Setup (do this once before first build/test/simulator use in a session)

```bash
# 1. Create a dedicated simulator clone (generates a unique UDID)
SIM_UDID=$(xcrun simctl clone "iPhone 16 Pro" "Noto-$(uuidgen | head -c 8)")
echo "Session simulator UDID: $SIM_UDID"

# 2. Boot it
xcrun simctl boot "$SIM_UDID"
```

**Store `$SIM_UDID` and use it for ALL subsequent commands in the session.** Never use `name=iPhone 16 Pro` or `booted` — always use `id=$SIM_UDID`.

### Cleanup (do this when all testing/building is done)

```bash
xcrun simctl shutdown "$SIM_UDID"
xcrun simctl delete "$SIM_UDID"
```

### Housekeeping (remove orphaned session simulators)

```bash
xcrun simctl list devices | grep "Noto-" | grep -oE '[0-9A-F-]{36}' | xargs -I{} xcrun simctl delete {}
```

## Build & Test Commands

All commands use `id=$SIM_UDID` where `$SIM_UDID` is the session's dedicated simulator (see Simulator Isolation above).

```bash
# Build for iOS simulator
xcodebuild -project Noto.xcodeproj -scheme Noto -destination "id=$SIM_UDID"

# Run all unit tests (Swift Testing framework)
xcodebuild test -project Noto.xcodeproj -scheme Noto -destination "id=$SIM_UDID" -only-testing:NotoTests

# Run a specific test class
xcodebuild test -project Noto.xcodeproj -scheme Noto -destination "id=$SIM_UDID" -only-testing:NotoTests/BlockTests

# Run UI tests (visible in simulator with -parallel-testing-enabled NO)
xcodebuild test -project Noto.xcodeproj -scheme Noto -destination "id=$SIM_UDID" -only-testing:NotoUITests -parallel-testing-enabled NO

# View os_log output from session's simulator
xcrun simctl spawn "$SIM_UDID" log stream --predicate 'subsystem == "com.noto"'
```

### MCP Tool Usage

When using xc-build, xc-testing, xc-launch, xc-interact, or xc-ai-assist MCP tools:
- Pass `destination: "id=$SIM_UDID"` for build/test tools
- Pass `target: "$SIM_UDID"` (the UDID) for IDB-based tools (idb_tap, idb_describe, simulator_screenshot, etc.)
- **Never** use `"booted"` as target — multiple simulators may be booted across sessions

## Architecture

### Three-Layer Design

1. **Data layer** (`Models/`): SwiftData `@Model` classes — Block, BlockLink, Tag, BlockTag, MetadataField, BlockEmbedding, SearchIndex. All registered in `NotoApp.swift` schema.

2. **Text editing layer** (`TextKit/`): UIKit TextKit 1 stack wrapped for SwiftUI:
   - `NoteTextStorage` (NSTextStorage) — markdown-like formatting (bold, italic, strikethrough, code), `deformatted()` extracts plain text
   - `NoteTextView` (UITextView) — keyboard toolbar (indent/outdent/move up/move down/dismiss), long-press drag-to-reorder gesture
   - `NoteTextEditor` (UIViewRepresentable) — bridges UIKit↔SwiftUI via Coordinator pattern; tracks `isEditing` to prevent feedback loops in `updateUIView`

3. **UI layer**: `ContentView.swift` manages the flat text↔Block tree sync. Text is tab-indented lines; each line maps to a Block with depth derived from leading `\t` count.

### Key Data Patterns

- **Fractional indexing**: `Block.sortOrder` (Double) avoids rewriting siblings on reorder. Use `sortOrderBetween(_:_:)` for insertions.
- **Denormalized depth**: `Block.depth` cached for query efficiency; must be updated via `move(to:sortOrder:)` which cascades to descendants.
- **Parent finding**: Walk backward through flat list for nearest block at `depth - 1`.
- **Content sync** (`ContentView.syncContent`): Parses `editableContent` lines → updates/creates/deletes Blocks to match. Guarded by `isSyncing` flag to prevent re-entrancy.
- **Reorder** (`ContentView.reorderBlock`): Removes block from flat list, reinserts at destination, adjusts depth, reconciles all parents, reassigns sequential sortOrders.

### UI Testing

- `NotoApp.swift` checks for `-UITesting` launch argument or `UITESTING=1` env var to use in-memory ModelContainer
- UI tests use `app.launchArguments = ["-UITesting"]` + `app.launchEnvironment["UITESTING"] = "1"` for isolation
- Coordinate-based `tapOnLine()` is unreliable for non-zero line indices in XCUITest; prefer natural cursor position (always on last line after `typeText`)
- After `loadNote()`, cursor resets to end of text

### Unit Testing

Uses Swift Testing framework (`@Test` macro, `#expect`), not XCTest assertions. Test container helper:
```swift
@MainActor
func createTestContainer() throws -> ModelContainer  // in-memory, all models registered
```

## Conventions

- **Logging**: Always use `os_log` (`Logger`) instead of `print()`. Pattern: `private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noto", category: "ClassName")`
- **SwiftLint**: `line_length` and `identifier_name` rules are disabled
- PRD documents live in `.claude/` directory (PRD-data-structure.md, PRD-user-interface-v1.md)
- **Testing & Simulator**: Always invoke the `/ios-dev-testing` skill instead of directly using `xcodebuild` or `xcrun simctl` CLI commands. The skill ensures simulator isolation (per-session dedicated simulator), clean builds, and proper teardown. Never run build/test commands manually — let the skill manage the full lifecycle.
