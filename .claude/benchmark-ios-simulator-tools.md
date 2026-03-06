# iOS Simulator Tool Benchmark

**Date:** 2026-03-06
**Project:** Noto (SwiftUI + SwiftData, local Swift packages)
**Machine:** macOS Darwin 24.6.0 (Apple Silicon)
**Tools Tested:**
1. **XcodeBuildMCP** v2.1.0 (CLI via Homebrew)
2. **ios-dev-testing** (xc-build / xc-launch / xc-interact / xc-testing MCP servers)
3. **FlowDeck** (CLI)

---

## 1. Simulator Boot Time

| Tool | Time | Notes |
|------|------|-------|
| **XcodeBuildMCP** | **2.86s** | `xcodebuildmcp simulator boot --simulator-id` |
| **ios-dev-testing** | N/A | No native boot command; relies on `xcrun simctl` or FlowDeck |
| **FlowDeck** | **0.93s** | `flowdeck simulator boot <udid>` |

**Winner: FlowDeck** (3x faster). ios-dev-testing has no boot capability of its own.

---

## 2. Build Time (compile only, no launch)

| Tool | Time | Notes |
|------|------|-------|
| **XcodeBuildMCP** | **22.6s** | `xcodebuildmcp simulator build` |
| **ios-dev-testing** | **17.8s** | `mcp__xc-build__xcode_build` (MCP call) |
| **FlowDeck** | **9.5s** | `flowdeck build` |

**Winner: FlowDeck** (2-3x faster). Likely uses incremental/cached build optimizations.

---

## 3. Build & Run (compile + install + launch)

| Tool | Time | Notes |
|------|------|-------|
| **XcodeBuildMCP** | **12.2s** | `xcodebuildmcp simulator build-and-run` (single command) |
| **ios-dev-testing** | **17.8s + 1.5s** | Build MCP call + separate install + launch calls (~19.3s total) |
| **FlowDeck** | **7.5s** | `flowdeck run` (single command) |

**Winner: FlowDeck**. XcodeBuildMCP is a strong second with its single-command approach. ios-dev-testing requires 3 separate MCP calls (build, install, launch).

---

## 4. UI Accessibility Tree Snapshot

| Tool | Time | Output Quality | Notes |
|------|------|----------------|-------|
| **XcodeBuildMCP** | **2.6-5.8s** | Full JSON tree with AXFrame, AXLabel, AXUniqueId, role, children hierarchy | Deep nested hierarchy with all AX attributes |
| **ios-dev-testing** | **~1s** (MCP) | Flat list of elements with centerX/centerY and frame | 7 elements, compact JSON, center coords for tapping |
| **FlowDeck** | **1.6s** | Element count + screenshot file path | Also captures screenshot simultaneously |

**Winner (speed): ios-dev-testing** (MCP call returns fastest).
**Winner (detail): XcodeBuildMCP** (full hierarchical tree with all AX attributes).
**Winner (visual): FlowDeck** (screenshot + elements in one call).

---

## 5. Screenshot Capture

| Tool | Time | Format | Notes |
|------|------|--------|-------|
| **XcodeBuildMCP** | **3.9s** | JPEG (optimized) | Returns file path |
| **ios-dev-testing** | N/A | No dedicated screenshot tool | Must use xc-interact's idb_describe or xc-ai-assist |
| **FlowDeck** | **0.5s** | PNG | Bundled with `screen` command |

**Winner: FlowDeck** (8x faster). ios-dev-testing lacks a standalone screenshot tool.

---

## 6. Tap Interaction

### By coordinates

| Tool | Time | Notes |
|------|------|-------|
| **XcodeBuildMCP** | **2.8s** | `tap --x 233 --y 784` |
| **ios-dev-testing** | **~0.5s** (MCP) | `idb_tap x:233 y:784` |
| **FlowDeck** | **0.35s** | `tap --point "233,784"` |

### By label (natural language)

| Tool | Time | Notes |
|------|------|-------|
| **XcodeBuildMCP** | **2.7s** | `tap --label "Search"` (exact AXLabel match) |
| **ios-dev-testing** | **~0.5s** (MCP) | `idb_find_element query:"Search"` (semantic search, but found 0 matches in test) |
| **FlowDeck** | **0.37s** | `tap "Search"` (label argument, natural) |

**Winner: FlowDeck** (fastest). ios-dev-testing is fast via MCP but find_element had reliability issues.

---

## 7. Type Text

| Tool | Time | Notes |
|------|------|-------|
| **XcodeBuildMCP** | **3.7s** | `type-text --text "benchmark test"` |
| **ios-dev-testing** | **~0.5s** (MCP) | `idb_input text:"benchmark test"` |
| **FlowDeck** | **0.7s** | `type "benchmark test"` |

**Winner: ios-dev-testing** (MCP direct call). FlowDeck close second.

---

## 8. Test Execution (NotoTests/BlockTests)

| Tool | Time | Notes |
|------|------|-------|
| **XcodeBuildMCP** | **40.5s** | `simulator test --json '{"extraArgs":["-only-testing:NotoTests/BlockTests"]}'` |
| **ios-dev-testing** | **43.6s** | `mcp__xc-testing__xcode_test only_testing:["NotoTests/BlockTests"]` |
| **FlowDeck** | **334s** | `flowdeck test` (ran ALL tests, no filter option observed) |

**Winner: XcodeBuildMCP** (slightly faster, supports test filtering via JSON). ios-dev-testing comparable. FlowDeck ran the full suite because test filtering wasn't applied.

---

## 9. Simulator Isolation (per-agent dedicated simulator)

| Tool | Creates Simulators? | Isolation Support | Notes |
|------|---------------------|-------------------|-------|
| **XcodeBuildMCP** | No (needs `xcrun simctl clone`) | Yes, via `--simulator-id` on every command | All commands accept simulator UDID |
| **ios-dev-testing** | No (needs `xcrun simctl clone`) | Yes, via `target` param on MCP calls | MCP tools accept device UDID |
| **FlowDeck** | Yes (`flowdeck simulator create`) | Yes, via `-S <udid>` on every command | Native create + all commands accept UDID |

**Winner: FlowDeck** (only tool with native simulator creation). All three support isolation once a UDID exists.

---

## 10. Natural Language to Action Capability

| Tool | Approach | Strengths | Weaknesses |
|------|----------|-----------|------------|
| **XcodeBuildMCP** | `tap --label` / `tap --id` for exact AX match | Precise label/id targeting, full AX tree for context | Requires exact label match, no fuzzy search |
| **ios-dev-testing** | `idb_find_element query` for semantic search | Designed for semantic/fuzzy matching | Found 0 results in our test (reliability concern) |
| **FlowDeck** | `tap "label"` positional argument | Most natural CLI syntax, just pass the label | Exact match only |

**Winner: XcodeBuildMCP** (best AX tree detail for agent reasoning). FlowDeck has the most ergonomic CLI syntax. ios-dev-testing's semantic search concept is good but needs reliability work.

---

## 11. UI Attribute Inspection (font size, color, sizing)

| Tool | Capability | Notes |
|------|------------|-------|
| **XcodeBuildMCP** | AXFrame, AXLabel, AXValue, AXUniqueId, role, role_description, enabled, content_required, custom_actions, **nested children hierarchy** | Full AX attributes with parent-child tree |
| **ios-dev-testing** | frame, centerX, centerY, type | Minimal - coordinates and type only |
| **FlowDeck** | frame, center (precomputed), label, id, role, enabled, **visible**, flat list (`--tree --json`) | Good AX attributes; flat list is easier to parse; includes `visible` flag |

**Winner: XcodeBuildMCP** (most detailed — nested hierarchy + AXValue + custom_actions). **FlowDeck is a close second** with `--tree --json` providing label, id, role, enabled, visible, frame, and precomputed center coords. ios-dev-testing is minimal. None provide font size or color natively — these require screenshot visual analysis or runtime LLDB inspection (`po view.font`).

---

## Summary Scorecard

| Benchmark | XcodeBuildMCP | ios-dev-testing | FlowDeck |
|-----------|:---:|:---:|:---:|
| Sim Boot | 2nd | N/A | 1st |
| Build | 3rd | 2nd | 1st |
| Build & Run | 2nd | 3rd | 1st |
| UI Snapshot (speed) | 3rd | 1st | 2nd |
| UI Snapshot (detail) | 1st | 2nd | 3rd |
| Screenshot | 2nd | N/A | 1st |
| Tap (coords) | 3rd | 2nd | 1st |
| Tap (label) | 2nd | 3rd | 1st |
| Type Text | 3rd | 1st | 2nd |
| Test Execution | 1st | 2nd | 3rd |
| Sim Isolation | 2nd | 2nd | 1st |
| NL-to-Action | 1st | 3rd | 2nd |
| UI Attributes | 1st | 3rd | 2nd |

### Overall Rankings

1. **FlowDeck** - Fastest across most operations. Best for build/run/screenshot/tap workflows. Native simulator lifecycle management. Weakest in UI attribute detail and test filtering.

2. **XcodeBuildMCP** - Best UI inspection detail (full AX tree). Good test filtering support. Single-command build-and-run. Slower per-operation due to Node.js overhead (~2-4s per call). Best documentation/skill ecosystem.

3. **ios-dev-testing** (xc-* MCP servers) - Fast MCP calls for UI interaction. Good test runner. But requires multiple separate calls for build+install+launch workflow, lacks screenshot and boot commands, and semantic find_element had reliability issues.

### Recommendation

- **For speed-critical CI/automation:** FlowDeck
- **For detailed UI debugging/inspection:** XcodeBuildMCP
- **For MCP-native agent integration:** ios-dev-testing (when MCP protocol is preferred over CLI)
- **For per-agent simulator isolation:** All three work, but FlowDeck is the only one with native simulator create/delete
