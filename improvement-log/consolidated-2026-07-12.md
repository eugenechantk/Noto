# Improvement Log Digest — 2026-07-12

**Logs processed:** 7 (3 substantive, 4 empty templates)
**Date range:** 2026-06-16 to 2026-07-12
**Observations found:** 15 (13 unaddressed at time of logging)

## Patterns (recurring across 2+ sessions)

### 1. FlowDeck edge cases keep costing build/test cycles
- **Frequency:** 3 sessions (2026-06-24/25, 2026-06-30, 2026-07-12)
- **Summary:** Repeated friction with flowdeck's less-traveled paths: test filtering syntax (`--only Target/Class`, not `-only-testing:` via `--xcodebuild-options`), `flowdeck test` reporting "scheme has no tests" (fall back to XcodeBuildMCP `test_sim`), `--xcodebuild-options` splitting on spaces (breaks `CODE_SIGN_IDENTITY=Apple Development`), `flowdeck run` reinstalling and churning the sim data container (loses seeded vaults), and per-session sim auto-creation compounding disk pressure.
- **Root cause:** These gotchas were logged but never persisted anywhere the next session would read.
- **Current coverage:** `feedback_use_flowdeck.md` memory says *use* flowdeck but records no quirks.
- **Recommended fix:** New reference memory `reference_flowdeck_quirks.md` consolidating all known workarounds.
- **Mechanism:** memory (reference) — **APPLIED this digest**

### 2. Signing/deployment standardization vs local builds
- **Frequency:** 2 sessions (TestFlight standardization session ~2026-07-08, install session 2026-07-12)
- **Summary:** The TestFlight standardization set the Noto target to Manual/"match AppStore" signing for BOTH Debug and Release in project.pbxproj. That profile exists only in CI, so every local build broke. Recovered with a temp xcconfig (Automatic signing, Apple Development, team 39GJBP8V5A) + `-allowProvisioningUpdates` + ASC API key, and registered this Mac (UDID 00008112-000A30583645401E) in the developer account.
- **Root cause:** The standardization applied archive-time signing at the project level instead of at gym/export time.
- **Current coverage:** none (testflight-deploy skill templates don't guard against this).
- **Recommended fix:** (a) memory `project_macos_local_build_signing.md` with the working local-build recipe — **APPLIED**; (b) when finishing the fastlane standardization: revert Debug to Automatic signing in pbxproj and apply match signing in the lane at archive time; add that rule to the testflight-deploy skill templates — **left as follow-up** (touches in-progress work).
- **Mechanism:** memory now; skill template fix later

## One-Off Observations (single session)

### 1. Claude Design canvas capture friction (2026-06-24)
- **Summary:** Burned many turns fighting edit-mode canvas zoom/pan for artboard captures; long `type` into the composer auto-submitted mid-string.
- **Worth persisting?** YES (partly covered) — `reference_noto_design_project.md` already notes edit-mode pan resistance; the actionable additions (give Eugene the file URL + section name instead of captures; relay the design AI's own screenshots; chunk long composer input) noted here as the permanent record.

### 2. LLM tool-call text contains literal `\n` (2026-06-25)
- **Summary:** Model-emitted escaped `\n` was saved verbatim into notes; unit tests missed it (they used real newlines). Fixed in code (normalization) same session.
- **Worth persisting?** Digest record sufficient — lesson: test the double-escaped case whenever a tool writes free-form model text to files.

### 3. `modified` stamped at file-IO boundary (2026-06-25, design call by Eugene)
- **Summary:** Metadata like `modified` is stamped at the write boundary (`NoteFrontmatter.stampingModified`), not derived from editor actions, so AI/automation edits bump it too. Implemented.
- **Worth persisting?** Architecture is in code + README; digest record sufficient.

### 4. Chat errors swallowed into generic message (2026-06-30)
- **Summary:** `ChatSession.friendly()` hid HTTP status/body, making the HK geo-block diagnosis guesswork. Fixed same session (surface real error detail).
- **Worth persisting?** Digest record sufficient (code fixed).

### 5. Disk-full blocked UI verification (2026-06-30)
- **Summary:** Host data volume hit 100%; vault seeding and UI automation failed. Stale per-session simulators compound disk pressure.
- **Worth persisting?** Folded into `reference_flowdeck_quirks.md` (check `df -h` before heavy sim work; clean stale session sims).

### 6. `@_exported import` avoids pbxproj surgery for transitive local packages (2026-06-24)
- **Summary:** Adding NotoEdit without editing pbxproj worked cleanly via `@_exported import`.
- **Worth persisting?** Folded into digest; pattern is discoverable in code.

## Already Addressed

- [x] Chat error transparency — fixed in ChatSession (session 20260629)
- [x] `\n` normalization for model edit text — fixed + visual audit (session 20260624)
- [x] `modified`-at-write-boundary architecture — implemented (session 20260624)
- [x] Mac registered in developer account — done (session 20260711)

## Recommended Actions

| # | Action | Mechanism | Location | Priority | Status |
|---|--------|-----------|----------|----------|--------|
| 1 | Consolidate flowdeck quirks/workarounds | memory (reference) | memory/reference_flowdeck_quirks.md | HIGH | DONE |
| 2 | Record local macOS build+signing recipe | memory (project) | memory/project_macos_local_build_signing.md | HIGH | DONE |
| 3 | Fix Debug signing in pbxproj + testflight-deploy templates when standardization lands | skill + repo | testflight-deploy skill, project.pbxproj | HIGH | OPEN — coordinate with in-progress fastlane work |

## Logs to Archive

Deleted with this digest (captured above or empty):
- `improvement-log-20260624-doc-edit.md`, `improvement-log-20260629-163831.md`, `improvement-log-20260711-000001.md` — substantive, captured
- `improvement-log-20260616-134306.md`, `improvement-log-20260624-h2spacing.md`, `improvement-log-20260626-120044.md`, `improvement-log-20260711-155830.md` — empty templates
- All logs on the archive lists of `consolidated-2026-05-04.md` and `consolidated-2026-06-13.md` (never deleted at the time), plus empty templates `20260504-040751`, `20260504-041203`.

The three `consolidated-*.md` digests remain as the permanent record.
