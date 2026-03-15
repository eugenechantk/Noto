# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Noto is a universal Apple (iOS/macOS) outline-based note-taking app. Each note entry is a **Block** that can be infinitely nested. The app uses SwiftUI + SwiftData for the UI/data layer, with a custom UIKit TextKit 1 stack for rich text editing.

All business logic lives in **local Swift packages** (`Packages/`) that are independently buildable and testable via CLI (`swift build` / `swift test`). The Xcode app target is a thin UI shell. See the Architecture section for the full package map and design rationale.

Minimal external dependencies — only USearch (via NotoHNSW) for vector search. Everything else uses pure Apple frameworks.

## Simulator Isolation (IMPORTANT)

Multiple Claude Code sessions and worktrees may run concurrently. **Each session MUST use its own dedicated simulator** to avoid conflicts. Use XcodeBuildMCP MCP tools for all simulator and build operations.

### Setup (do this once before first build/test/simulator use in a session)

```bash
# 1. Create a dedicated simulator clone with a unique name
SIM_NAME="Noto-$(uuidgen | head -c 8)"
SIM_UDID=$(xcrun simctl clone "iPhone 16 Pro" "$SIM_NAME" | tail -1)
echo "Session simulator: $SIM_NAME ($SIM_UDID)"
```

Then set session defaults via the `session_set_defaults` MCP tool:
```
session_set_defaults({
  projectPath: "/Users/eugenechan/dev/personal/Noto/Noto.xcodeproj",
  scheme: "Noto",
  simulatorId: "$SIM_UDID"
})
```

Then boot the simulator via the `boot_sim` MCP tool.

**Store `$SIM_UDID` and use it for ALL subsequent commands in the session.** Never use a shared simulator name or `booted`.

### Cleanup (do this when all testing/building is done)

```bash
xcrun simctl shutdown "$SIM_UDID"
xcrun simctl delete "$SIM_UDID"
```

Then clear session defaults via the `session_clear_defaults` MCP tool.

### Housekeeping (remove orphaned session simulators)

```bash
xcrun simctl list devices | grep "Noto-" | grep -oE '[0-9A-F-]{36}' | xargs -I{} xcrun simctl delete {}
```

## Build & Test Commands

All commands use session defaults set via `session_set_defaults` MCP tool (see Simulator Isolation above).

```bash
# ── Package-level (preferred for logic testing — no simulator needed) ──
# Test a single package
cd Packages/NotoCore && swift test

# Test all packages
for pkg in Packages/*/; do (cd "$pkg" && swift test); done
```

**App-level (requires simulator — use for UI integration):**

Use XcodeBuildMCP MCP tools (session defaults provide project/scheme/simulator automatically):

| Task | MCP Tool |
|------|----------|
| Build only (compile check) | `build_sim` |
| Build + install + launch | `build_run_sim` |
| Run all unit tests | `test_sim` |
| Run specific tests | `test_sim` with `extraArgs: ["-only-testing:NotoTests/BlockTests"]` |
| Start log capture | `start_sim_log_cap` with `subsystemFilter: "app"` |
| Stop log capture + get logs | `stop_sim_log_cap` with the `logSessionId` |
| Launch app (already built) | `launch_app_sim` or `launch_app_logs_sim` |
| Stop running app | `stop_app_sim` |

### UI Inspection

Use XcodeBuildMCP MCP tools:

| Task | MCP Tool |
|------|----------|
| Accessibility tree (AXLabel, AXValue, role, frame, etc.) | `snapshot_ui` |
| Screenshot (returns path or base64) | `screenshot` |

For UI automation via the CLI:
```bash
# Tap by accessibility label
xcodebuildmcp ui-automation tap --simulator-id "$SIM_UDID" --label "Search"

# Tap by accessibility identifier
xcodebuildmcp ui-automation tap --simulator-id "$SIM_UDID" --id "searchButton"

# Type text
xcodebuildmcp ui-automation type-text --simulator-id "$SIM_UDID" --text "hello"

# Swipe/scroll
xcodebuildmcp ui-automation gesture --simulator-id "$SIM_UDID" --preset scroll-down
```

### Physical Device (iPhone)

Use the XcodeBuildMCP CLI for device workflows:
```bash
# List connected devices
xcodebuildmcp device list

# Build for device
xcodebuildmcp device build --scheme Noto --project-path ./Noto.xcodeproj

# Get built app path and bundle ID
xcodebuildmcp device get-app-path --scheme Noto --project-path ./Noto.xcodeproj
xcodebuildmcp device get-app-bundle-id --app-path /path/to/Noto.app

# Install and launch on device
xcodebuildmcp device install --device-id <DEVICE_UDID> --app-path /path/to/Noto.app
xcodebuildmcp device launch --device-id <DEVICE_UDID> --bundle-id <BUNDLE_ID>
```

## Architecture

### Core Principle: Swift Packages with CLI-Testable Logic, Thin UI Shell

All business logic, data models, and services are extracted into **local Swift packages** under `Packages/`. The Xcode app target (`Noto/`) is a **thin shell** containing only UI views, controllers, and TextKit bridging code that imports and calls into these packages. Nothing in `Noto/` should contain business logic that could live in a package.

**Why this architecture:**
- **Independent testability**: Each package can be built and tested via `swift build` / `swift test` from the CLI, without Xcode or a simulator. This makes tests fast, parallelizable, and CI-friendly.
- **Clear boundaries**: Packages enforce explicit dependency graphs. A package can only use what it declares in its `Package.swift` dependencies — no implicit coupling.
- **Faster iteration**: Changes to a package only recompile that package and its dependents, not the entire app. CLI tests run in seconds vs. minutes for simulator-based tests.
- **Reusability**: Packages can be shared across targets (app, extensions, widgets) without duplicating code.

### Package Dependency Graph

```
Packages/
├── NotoModels          ← SwiftData @Model classes (Block, Tag, BlockLink, etc.)
├── NotoCore            ← Core utilities (BlockBuilder, BreadcrumbBuilder, PlainTextExtractor)
│   └── depends on: NotoModels
├── NotoDirtyTracker    ← Change tracking for incremental indexing
│   └── depends on: NotoModels, NotoCore
├── NotoEmbedding       ← CoreML embedding model + BERT tokenizer (no deps on other Noto packages)
├── NotoFTS5            ← SQLite FTS5 full-text search engine
│   └── depends on: NotoModels, NotoCore, NotoDirtyTracker
├── NotoHNSW            ← HNSW vector index (USearch) for semantic search
│   └── depends on: NotoModels, NotoCore, NotoDirtyTracker, NotoEmbedding, USearch (external)
├── NotoSearch          ← Hybrid search orchestrator (FTS5 + semantic + date filtering)
│   └── depends on: NotoModels, NotoCore, NotoDirtyTracker, NotoFTS5, NotoHNSW, NotoEmbedding
└── NotoTodayNotes      ← "Today" notes service
    └── depends on: NotoModels, NotoCore
```

**Note:** `NotoHNSW` (via USearch) is the only package with an external dependency. All others use pure Apple frameworks.

### App Target (`Noto/`) — UI & Controllers Only

The Xcode app target contains only:
- **Views** (`Views/`, `ContentView.swift`): SwiftUI views that call package methods
- **TextKit bridge** (`TextKit/`): UIKit TextKit 1 stack wrapped for SwiftUI (NoteTextStorage, NoteTextView, NoteTextEditor)
- **App entry** (`NotoApp.swift`): SwiftData schema registration, container setup

### Building & Testing Packages from CLI

```bash
# Build a single package
cd Packages/NotoModels && swift build

# Test a single package
cd Packages/NotoCore && swift test

# Test all packages (from repo root)
for pkg in Packages/*/; do (cd "$pkg" && swift test); done
```

This is the **preferred way to test logic** — only use `xcodebuild` / simulator when testing UI integration.

### When to Create a New Package vs. Add to Existing

- **New package**: When the feature has a distinct responsibility and its own testable surface (e.g., a new search engine, a sync service, a new data pipeline).
- **Add to existing**: When the code is a utility or extension that naturally belongs to an existing package's domain (e.g., a new query helper belongs in NotoCore).
- **Never in app target**: If the code doesn't require UIKit/SwiftUI/AppKit, it belongs in a package.

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
- **Testing & Simulator**: Use XcodeBuildMCP MCP tools (`build_sim`, `build_run_sim`, `test_sim`, `snapshot_ui`, `screenshot`, etc.) for all simulator build/run/test/UI inspection. Use the `xcodebuildmcp` CLI for device workflows and UI automation (tap, type, swipe). Set session defaults via `session_set_defaults` at session start to avoid repeating project/scheme/simulator on every call.
- **UI/UX tasks**: When working on any UI or UX related task (layout changes, styling, new views, design implementation, visual updates), always build and deploy to the simulator after making changes, then use `snapshot_ui` and `screenshot` MCP tools to visually verify the result. Do not consider a UI/UX task complete without visual confirmation on the simulator.
