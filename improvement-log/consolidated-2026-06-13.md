# Improvement Log Digest — 2026-06-13

**Logs processed:** 14 (since the 2026-05-04 digest)
**Date range:** 2026-05-07 to 2026-06-13
**Observations found:** ~24 (5 empty logs; ~22 substantive items)

## Patterns (recurring across 2+ sessions / instances)

### 1. Instrument the boundary with one os_log BEFORE cycling passive hypotheses or sweeping inputs
- **Frequency:** 3 instances in 20260610-touchtargets (image-load placeholder bug; ~40 blind citation-tap probes; explicitly "same lesson as the image-load bug earlier this session") + related 20260603 (lldb ObjC introspection beat screenshots/logs for AppKit state).
- **Summary:** For runtime data-flow / tap / event bugs, reading code in a loop or sweeping coordinates converges far slower than one cheap probe at the failure/branch point. In every case the single os_log immediately bisected the pipeline and showed the real cause (often "the thing never failed / never fired").
- **Root cause:** Defaulting to passive code-reading or blind interaction instead of making the runtime emit ground truth at the suspect boundary.
- **Current coverage:** `feedback_visual_bugs_first` covers *visual* bugs (reproduce + exaggerate). No memory covers *runtime data-flow / event* bugs (the instrument-first rule). Gap.
- **Recommended fix:** New memory: instrument the handler/branch with one os_log first, rebuild once, let evidence pick the branch. Inside automation loops, assert the expected screen anchor before each action.
- **Mechanism:** memory (feedback)

### 2. Capture full test output to a file — never truncate with `tail`
- **Frequency:** 2 instances in the SAME session (20260610-touchtargets) — flagged explicitly as "should graduate from improvement-log entry to a durable rule".
- **Summary:** Ran `flowdeck test`/`swift test` piped to `tail -8/-15`, lost the failing test names, and kicked off a full re-run (one suite is ~9 min). Repeated the exact mistake hours after logging it.
- **Root cause:** Truncating output discards the entire point of the run (failure detail); the lesson never became a default habit.
- **Current coverage:** None.
- **Recommended fix:** New memory: always `… > /tmp/<name>.log 2>&1` then grep the file; never lose the first run's output.
- **Mechanism:** memory (feedback)

### 3. "Done" requires validating the RIGHT thing on the RIGHT surface
- **Frequency:** 20260610-041239 (Core ML spike declared done on host runtime, not iOS sim/device) + 20260610-120000 (shipped imperceptible 2px spacing change and called it done) + this session 20260613 (verified keyboard change blocked on iPhone; moved to iPad).
- **Summary:** Deployable artifacts (Core ML models, binaries) are only done when run on the target runtime; perceptual changes are only done when the *composed* visual delta is perceptible, not when "the constant changed and it renders."
- **Current coverage:** `ios-development` skill mandates simulator verification for UI; `feedback_visual_bugs_first` partially. Neither states "compute the full composed spacing gap and check the delta is perceptible" nor "deployable artifacts must run on target runtime."
- **Recommended fix:** Light augment — fold the "perceptible composed-delta" nuance into `feedback_visual_bugs_first`; note runtime-artifact validation. (Lower priority than #1/#2.)
- **Mechanism:** memory (augment existing)

### 4. Stale project CLAUDE.md simulator runtime / device-type names
- **Frequency:** 20260610-120000 (`--runtime "iOS 26"` fails; installed is `iOS 26.2`) + 20260610-041239 (device-type display names with parentheses fail; use the dash identifier `iPad-mini-A17-Pro`).
- **Summary:** Following the project CLAUDE.md simulator-create command literally wastes a command + a lookup every session.
- **Current coverage:** Project CLAUDE.md "Simulator Isolation" still says `--runtime "iOS 26"`.
- **Recommended fix:** Update project CLAUDE.md to `--runtime "iOS 26.2"` (or "latest installed 26.x from `flowdeck simulator runtime list`") and note the parens→dash device-type identifier quirk.
- **Mechanism:** project CLAUDE.md

### 5. Sandboxed macOS app: runtime data lives in the container, and the test host shares the real defaults domain
- **Frequency:** 20260610-041239 (queried non-container Application Support, nearly misdiagnosed a healthy index as broken) + 20260610-120000 (`flowdeck test -D "My Mac"` wiped the real app's vault bookmark; FlowDeck builds are unsandboxed).
- **Summary:** For the sandboxed Noto Mac app, real runtime data is under `~/Library/Containers/com.eugenechan.Noto/Data/…`; non-container paths only hold non-sandboxed-debug data. App-hosted unit tests (`flowdeck test -D "My Mac"`) run the real lifecycle against the real defaults domain and can destroy the daily-driver vault config.
- **Current coverage:** `feedback_macos_debug_runtime_first` covers "run + DebugTrace first" but not the container data path or the destructive-test-host warning.
- **Recommended fix:** Augment `feedback_macos_debug_runtime_first` with the container path; add a safety note (memory or project CLAUDE.md) that `flowdeck test -D "My Mac"` can wipe the real vault state — back up `~/Library/Preferences/com.eugenechan.Noto.plist` first or fix `VaultLocationManager` to isolate UserDefaults under XCTest.
- **Mechanism:** memory (augment) + optional code fix tracked

## One-Off Observations (single session)

- **Swift Testing parallel races on shared static mock** (20260606): suites mutating `static var` (URLProtocol mocks) need `@Suite(.serialized)`. Worth persisting — YES (recurs with any static mock).
- **Adding an overlapping agent tool requires rewriting the OLD tool's description** (20260610-041239): tool selection is zero-sum; narrow the old tool's niche + system-prompt routing rule + empirical verification on the cheapest model. Worth persisting — YES (NotoChat-relevant).
- **CJK input via `flowdeck ui simulator type` silently fails** (20260610-041239): use pasteboard injection. Worth persisting — YES; consolidate with `reference_maestro_e2e` keyboard quirks.
- **LocalSecrets.xcconfig carries NOTO_READWISE_TOKEN → test sims auto-sync ~775 real captures mid-run** (20260610-041239): blank unwanted tokens in test/worktree copies. Worth persisting — YES (test-env hygiene).
- **claude.ai/design: use the UI download flow, not the preview-token API** (20260606): rabbit hole; honor the 2–3-failed-attempts browser rule. Already partly in `reference_claude_design_download`; reinforce.
- **Started in local Design/v2 files instead of the live webapp** (20260606): `reference_noto_design_project` existed but didn't prevent it. NO new mechanism — memory exists; the miss was application, not a gap.
- **Pre-existing macOS test failures on main** (20260610-120000): 7 baseline failures (OwnershipDependency ×2, SearchIndexController ×3, popover inset, editorInteractionBaseline). Worth persisting — borderline; better fixed than memorialized.
- **DebugTrace concurrent-write race loses events** (20260610): serialize `record()`. Code fix, not a system rule.
- **Each NoteEditorSession spins up its own VaultController/rootStore** (20260509): architectural follow-up. Code, not a system rule.
- **This session (20260613):** app reads the *nested* `…/File Provider Storage/Noto/Noto` vault (disambiguate by matching folder item counts to the UI); software keyboard is suppressed after FlowDeck HID injection — verify keyboards on a HID-clean (tap-only) simulator. Project-specific tooling notes.

## Already Addressed

- [x] Search-sheet beachball from main-thread full-file reads (20260507) — fixed in-session (trust the index; I/O off main).

## Recommended Actions

| # | Action | Mechanism | Location | Priority |
|---|--------|-----------|----------|----------|
| 1 | New memory: instrument boundary with one os_log first for runtime/tap/event bugs; assert screen anchor in automation loops | memory | `feedback_instrument_runtime_first.md` | HIGH |
| 2 | New memory: capture full test output to a file, never `tail`-truncate | memory | `feedback_capture_test_output.md` | HIGH |
| 3 | Fix project CLAUDE.md simulator runtime → `iOS 26.2` + parens→dash device-type note | project CLAUDE.md | `CLAUDE.md` Simulator Isolation | HIGH |
| 4 | Augment `feedback_macos_debug_runtime_first`: container data path + destructive test-host warning | memory | existing memory | MEDIUM |
| 5 | New memory: Swift Testing suites with shared static mocks need `@Suite(.serialized)` | memory | `feedback_swift_testing_serialized.md` | MEDIUM |
| 6 | Augment `feedback_visual_bugs_first`: compute composed visual delta / target-runtime validation | memory | existing memory | LOW |
| 7 | Note CJK pasteboard-injection + HID-clean keyboard verification | memory | extend `reference_maestro_e2e` | LOW |

## Logs to Archive (delete — captured in this digest)

All 14 processed logs:
- 20260507-070315, 20260509-044553, 20260512-032808 (substantive, captured)
- 20260603-080335, 20260604-iosredesign, 20260606-150843 (substantive, captured)
- 20260610-041239, 20260610-120000, 20260610-touchtargets, 20260613-1018 (substantive, captured)
- 20260512-041054, 20260512-041642, 20260514-041613, 20260514-095113, 20260610-000001 (empty templates)

Note: 20260604-iosredesign was scanned for net-new items beyond the design/runtime patterns already captured; nothing additional. Keep `consolidated-2026-05-04.md` and this digest as the permanent record.
