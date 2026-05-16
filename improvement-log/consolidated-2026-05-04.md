# Improvement Log Digest — 2026-05-04

**Logs processed:** 26
**Date range:** 2026-03-19 to 2026-05-03
**Observations found:** 28 (5 unaddressed, 4 partially addressed)

---

## Already Addressed (nothing to do)

Every item below has a corresponding memory file, CLAUDE.md rule, or skill that covers it. These log files can be deleted.

| Observation | Covered By |
|-------------|------------|
| Not loading /ios-development + /ios-debug-flow before iOS work | `feedback_use_ios_development_skill.md` |
| Using xcodebuildmcp instead of /flowdeck | `feedback_use_flowdeck.md` + CLAUDE.md |
| Over-investigating visual bugs with logging instead of visual test | `feedback_visual_bugs_first.md` |
| Stopping mid-loop waiting for user input | `feedback_dont_stop_mid_loop.md` |
| Fixing bugs without being asked | `feedback_fix_bugs_autonomously.md` |
| macOS sandbox — run app + check logs before code analysis | `feedback_macos_debug_runtime_first.md` |
| Creating redundant test suites for internal abstractions | `feedback_no_redundant_tests.md` |
| TextKit 2 re-entrancy / processEditing mutation crash | `feedback_textkit1_safety.md` |
| Maestro iOS 26 keyboard + pressKey quirks | `reference_maestro_e2e.md` |
| Flowdeck device build fails → xcodebuildmcp fallback | `reference_flowdeck_device_install.md` |
| Improvement log format, per-turn cadence | CLAUDE.md turn footer rules |
| Execute first, don't over-ask | CLAUDE.md + `feedback_fix_bugs_autonomously.md` |
| Test documentation (index + per-test annotations) | `feedback_test_documentation.md` |
| Route navigation lost isNew flag, new store instance | Caught + fixed; Maestro covers regression |
| Debounced save → SwiftUI race condition crash | `feedback_textkit1_safety.md` |
| macOS build broken (deleteFrontmatterField iOS-scope only) | Fixed; addressed in 20260502 log |
| iOS metadata block surface too dark | Fixed in same session |

---

## Gaps — Need Action

### 1. Fell back to training knowledge when WebFetch fails on JS-rendered pages
- **Sessions:** 20260420-session
- **Summary:** WebFetch returned title-only for Apple HIG page (JS-rendered). Instead of trying `/browse` or claude-in-chrome, answered from training knowledge — which was ~6 months stale. Led to recommending a wrong SwiftUI API (`.prominentDetail`) that would have shipped non-HIG-compliant code.
- **Current coverage:** None
- **Recommended fix:** New memory: "When WebFetch returns empty/stub, immediately try `/browse`; never substitute training knowledge as authoritative on living specs (Apple HIG, Apple APIs). Explicitly flag staleness if no fetch tool works."
- **Mechanism:** feedback memory → `feedback_fetch_before_training.md`
- **Priority:** HIGH

### 2. Wrong API recommendation for Liquid Glass / visual material effects
- **Sessions:** 20260420-session
- **Summary:** Recommended `.prominentDetail` for the "sidebar with content underneath" pattern. Actual API is `.backgroundExtensionEffect()` from iOS 26 / WWDC 2025. The `/ios-design-liquid-glass` skill exists precisely for this — wasn't loaded.
- **Current coverage:** Skill exists (`ios-design-liquid-glass`) but nothing in memory or CLAUDE.md says to load it when the task involves a visual material effect.
- **Recommended fix:** Add trigger to `feedback_use_ios_development_skill.md`: "When task involves any visual/material effect on iOS/macOS 26, load `/ios-design-liquid-glass` before making any API recommendations."
- **Mechanism:** update existing feedback memory
- **Priority:** HIGH

### 3. Perceptual symptoms — don't try to reproduce literally
- **Sessions:** 20260426-072922
- **Summary:** User reported "search hangs indefinitely." I spent time trying to reproduce the literal hang on simulator, but the vault was too small to trigger it. Should have read the code path, found the O(N) file reads, and gone straight to the fix.
- **Current coverage:** None
- **Recommended fix:** New memory: "When a symptom is perceptual ('hangs', 'freezes', 'is broken'), read the code path first. If a perf anti-pattern is visible, fix it — don't keep trying to reproduce the exact user phrasing on a fast simulator."
- **Mechanism:** feedback memory → `feedback_perceptual_symptoms.md`
- **Priority:** MEDIUM

### 4. Trace all consumers before changing how an entity's ID is derived
- **Sessions:** 20260426-072922
- **Summary:** Optimized search to use `.fileOnly` mode, which caused `note.id` to become a path-hash instead of a frontmatter UUID. The tap-open path called `note(withID:)`, which reads every file in the vault on UUID mismatch — worst-case crash on real devices.
- **Current coverage:** None
- **Recommended fix:** New memory: "Before changing how an entity's ID is derived, `git grep` every consumer of that field. Especially `id`, `noteID`, `fileURL`. Trace all call sites to verify the change of derivation doesn't silently break downstream invariants."
- **Mechanism:** feedback memory → `feedback_trace_identity_consumers.md`
- **Priority:** MEDIUM

### 5. SwiftUI toolbar buttons not in accessibility tree → use `flowdeck simulator back`
- **Sessions:** 20260503-144638
- **Summary:** Spent 10 minutes trying to tap the history-back ToolbarItem by ID, label, and point coordinates. `flowdeck ui simulator back` worked immediately. SwiftUI nav bar buttons aren't surfaced in the in-process accessibility query.
- **Current coverage:** In improvement log only; not in memory or flowdeck skill.
- **Recommended fix:** Update `feedback_use_flowdeck.md` to add: "SwiftUI ToolbarItem buttons in the nav bar aren't in the accessibility tree. If `tap --by-id` or `tap --by-label` returns not_found for a nav bar button, use `flowdeck ui simulator back` / `key` / edge swipe — don't brute-force coordinates."
- **Mechanism:** update existing feedback memory
- **Priority:** MEDIUM

---

## Open — Needs Investigation

### 6. NotoTests has 8 pre-existing failing tests
- **Session:** 20260502-162732
- **Summary:** 3× SearchIndexController timeouts, OwnershipRearchitecturePhase0 baseline timeout, page-mention popover layout, others. Flagged as likely unrelated to frontmatter changes.
- **Status:** Still open. Should confirm by running `swift test` (package level) and `flowdeck test` (app level) on current main.
- **Action needed:** Run tests and either fix or close as known-flaky.

---

## Recommended Actions (priority order)

| # | Action | Mechanism | Location | Priority |
|---|--------|-----------|----------|----------|
| 1 | New memory: fetch before falling back to training knowledge | feedback memory | `feedback_fetch_before_training.md` | HIGH |
| 2 | Update memory: load /ios-design-liquid-glass for visual/material effects | feedback memory | `feedback_use_ios_development_skill.md` | HIGH |
| 3 | Update memory: SwiftUI toolbar nav buttons → use `flowdeck simulator back` | feedback memory | `feedback_use_flowdeck.md` | MEDIUM |
| 4 | New memory: perceptual symptoms → read code, don't reproduce literally | feedback memory | `feedback_perceptual_symptoms.md` | MEDIUM |
| 5 | New memory: trace all ID consumers before changing identity derivation | feedback memory | `feedback_trace_identity_consumers.md` | MEDIUM |
| 6 | Investigate 8 pre-existing failing NotoTests | — | NotoTests | LOW |

## Logs to Archive (delete after actions are applied)

All logs are safe to delete — all actionable items are either already in the system or captured in this digest:

- `improvement-log-.md` — empty
- `improvement-log-20260319-043131.md` — empty
- `improvement-log-20260319-043137.md` — empty
- `improvement-log-20260319-045237.md` — empty placeholder
- `improvement-log-20260319-045243.md` — empty
- `improvement-log-20260321-155331.md` — empty
- `improvement-log-20260322-155651.md` — fully addressed
- `improvement-log-20260323-session.md` — fully addressed
- `improvement-log-20260325-123936.md` — empty
- `improvement-log-20260325-124014.md` — empty
- `improvement-log-20260326-140622.md` — empty
- `improvement-log-20260328-093222.md` — empty
- `improvement-log-20260328-115527.md` — fully addressed
- `improvement-log-20260328-icloud-sync.md` — fully addressed
- `improvement-log-20260401-000000.md` — empty
- `improvement-log-20260401-014839.md` — fully addressed
- `improvement-log-20260401-021403.md` — empty
- `improvement-log-20260401-032913.md` — empty
- `improvement-log-20260404-000000.md` — fully addressed
- `improvement-log-20260419-104325.md` — empty
- `improvement-log-20260420-111141.md` — empty
- `improvement-log-20260420-session.md` — gaps captured in digest (items 1–2 above)
- `improvement-log-20260423-073304.md` — empty
- `improvement-log-20260426-072922.md` — gaps captured in digest (items 3–4 above)
- `improvement-log-20260502-162732.md` — mostly addressed; open item (failing tests) captured in digest
- `improvement-log-20260503-144638.md` — gap captured in digest (item 5 above)
