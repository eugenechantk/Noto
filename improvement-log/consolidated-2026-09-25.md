# Improvement Log Digest — 2026-09-25

**Logs processed:** 36 session logs
**Date range:** 2026-07-12 to 2026-09-23
**Substantive logs:** 14
**Observations found:** 67 (61 open, 6 already addressed)

## Patterns

### 1. Simulator and FlowDeck state must be treated as explicit inputs

- **Frequency:** 9 sessions
- **Summary:** Runs repeatedly lost time to shared/wiped simulators, literal-UDID guard behavior, stale capture sessions, degraded accessibility translation, recorder failures, and unverified chained UI actions.
- **Root cause:** Automation state was inferred from recency or tool success rather than captured from the current session and re-verified after each transition.
- **Current coverage:** Project instructions now require the guard-assigned simulator, literal UDIDs, explicit seeding, and short verified action chains. FlowDeck and Noto validation skills cover the normal path.
- **Recommended fix:** Add a repo script that performs the standard Noto 2 rebuild/reseed/relaunch/session-start loop and emits the exact session directory. Add a preflight that rejects source-tree sync-conflict files.
- **Mechanism:** script plus pre-build check

### 2. Runtime evidence should precede speculative code changes

- **Frequency:** 6 sessions
- **Summary:** Investigations chased recent diffs, GUI theories, parser projections, or SwiftUI modifier guesses before checking actual file readability, real vault data, current Apple documentation, measured frames, or runtime logs.
- **Root cause:** Code inspection was used as a substitute for cheap observation even when the real data and runtime were locally available.
- **Current coverage:** The iOS debug workflow requires reproduction and evidence; project architecture documents iCloud/readability behavior. Several lessons remain scattered across logs.
- **Recommended fix:** Extend the debug checklist with: real-data audit for subset failures, shell readability probe for blocked file I/O, frame measurement before control-layout changes, and current-doc lookup before iOS chrome experiments.
- **Mechanism:** ios-debug-flow skill update

### 3. UI verification must exercise state transitions and composition boundaries

- **Frequency:** 8 sessions
- **Summary:** Green unit suites missed broken navigation reuse, stale one-shot screens, swallowed accessibility children, inert controls, wrong second-load behavior, and media spacing hidden by end-of-document fixtures.
- **Root cause:** Verification proved isolated states instead of transitions and integration points.
- **Current coverage:** The iOS development and visual-audit workflows now emphasize simulator evidence and navigation wiring, but project-specific edge cases remain useful.
- **Recommended fix:** Standardize a Noto UI matrix covering root/already-open/different-note navigation, content above-and-below embedded media, second URL/state transition, menu behavior after styling changes, and accessibility-tree presence for child controls.
- **Mechanism:** project skill checklist

### 4. Shared and multi-target code needs a platform-parity gate

- **Frequency:** 4 sessions
- **Summary:** Noto 2-only builds allowed Noto iOS/macOS failures, missing macOS todo rendering, and synced conflict sources to persist unnoticed.
- **Root cause:** The shared-source architecture has no cheap mandatory compile/parity check across all consumers.
- **Current coverage:** README and project instructions clearly define shared ownership; `scripts/check_platform_parity.py` exists but is not a routine gate.
- **Recommended fix:** Add a fast pre-commit check that scans compiled directories for `*.sync-conflict-*` and compiles Noto2, Noto-iOS, and Noto-macOS with signing disabled where appropriate.
- **Mechanism:** script or hook

### 5. Release success must come from canonical remote verification

- **Frequency:** 3 sessions
- **Summary:** Deploy work misreported wrapper exit status, guessed the lane-owned build number, and encountered second-target/internal-group/signing capability pitfalls.
- **Root cause:** Local process status and precomputed values were mistaken for the release system's ground truth.
- **Current coverage:** `testflight-deploy` now requires rbenv, lane-derived build numbers, IPA inspection, highest-train checks, `VALID`, and `IN_BETA_TESTING`; it also documents Noto 2's second-target handling.
- **Recommended fix:** Keep the canonical deploy and verifier as the only accepted path; add resource-backed capability assignment guidance when the skill is next revised.
- **Mechanism:** existing skill, small future update

### 6. Silent degradation should be visible product state

- **Frequency:** 3 sessions
- **Summary:** Search, AI summaries, iCloud reads, and other fallbacks returned degraded output while presenting it as a normal result.
- **Root cause:** Fallback reasons were discarded between service and view-model layers.
- **Current coverage:** Recent search work surfaces some degradation, but this is not a project-wide convention.
- **Recommended fix:** Require every fallback tier to carry a user-visible reason and verification case.
- **Mechanism:** project architecture guideline

## One-Off Observations

- The live Readwise token must never be bundled into an app build; rotate any exposed token and keep development credentials outside resources.
- The Hermes Readwise job and Noto 2 were observed using different iCloud vaults; verify ownership before changing either path.
- macOS menu geometry and behavior require AppKit/AX measurement rather than assuming SwiftUI label frames define control hit areas.
- Region screenshots can capture unrelated private windows; use app/window-scoped capture or explicitly verify the target is frontmost.
- Official MCP/API/CLI surfaces should be preferred over website scraping when a service advertises one.
- Never use `path` as a zsh variable because it aliases `PATH`.
- Device-only debugging remains blocked when Xcode is older than the attached device OS; keep toolchains aligned or expose diagnostic state in-app.

## Already Addressed

- [x] Runtime-first macOS diagnosis is established and proved effective.
- [x] idb was installed as a fallback input driver.
- [x] Noto simulator-isolation and reseeding rules were added to project instructions.
- [x] FlowDeck automation fallback coverage was made discoverable in memory.
- [x] Noto 2 TestFlight second-target and internal-group gotchas were added to `testflight-deploy`.
- [x] Stale synced Swift conflict copies were moved out of compiled source directories.

## Recommended Actions

| # | Action | Mechanism | Location | Priority |
|---|--------|-----------|----------|----------|
| 1 | Add a multi-target compile and sync-conflict preflight | script/hook | `scripts/` | High |
| 2 | Add a deterministic Noto 2 rebuild/reseed/relaunch helper | script | `scripts/` | High |
| 3 | Add transition-focused Noto UI verification cases | project skill | `.codex/skills/noto-ios-editor-validation/` | High |
| 4 | Expand runtime-first diagnosis with real-data and filesystem probes | skill | global `ios-debug-flow` | Medium |
| 5 | Make fallback reasons a project-wide UI contract | guideline | `README.md` or project instructions | Medium |
| 6 | Add resource-backed entitlement guidance to TestFlight deployment | skill | global `testflight-deploy` | Medium |

## Logs to Archive

No logs were deleted. System changes, memory updates, and log deletion require separate explicit approval. Empty session logs and observations captured above can be archived after that review.
