# Improvement Log — Session 20260624-doc-edit

## Tracker

- [ ] 2026-06-24 — Long `type` into Claude Design composer auto-submitted mid-string, leaving a ~200-char tail stuck in the composer
- [ ] 2026-06-24 — Burned many turns fighting the Claude Design canvas to capture artboards (zoom/pan resist programmatic control; drag-pan only registers intermittently)
- [ ] 2026-06-24 — Used `@_exported import` to avoid pbxproj surgery when adding a new local package (NotoEdit) the app needs transitively — worked cleanly
- [ ] 2026-06-24 — flowdeck test filter: use `--only Target/Class`, NOT `--xcodebuild-options '-only-testing:...'` (the latter prints help / "no tests")
- [ ] 2026-06-25 — `flowdeck test` reports "scheme has no tests" even though build succeeds + discovery finds them (broken test-run phase for this project); fell back to XcodeBuildMCP `test_sim` which worked. Direct `xcodebuild`/`xcrun` are blocked by the flowdeck guard hook.
- [ ] 2026-06-25 — XcodeBuildMCP `test_sim` method-level `-only-testing:Target/Class/method` runs 0 tests for Swift Testing (vacuous "succeeded"); filter at CLASS level. It also truncates stdout + deletes the xcresult, so failures are hard to read — add `-quiet` to surface Swift Testing failure lines.
- [ ] 2026-06-25 — Test-data bug: expected 2 edit cards but used ADJACENT lines, which correctly merge into 1 block (engine right, test wrong). Use genuinely distant spots when asserting multi-block.
- [ ] 2026-06-25 — Design call (Eugene): metadata like `modified` should be stamped at the FILE-IO write boundary, not derived from editor actions — so future programmatic edits (AI, automations) all bump it. Implemented `NoteFrontmatter.stampingModified` + publish `NoteSyncCenter` snapshot for live editor sync; removed the editor bridge.
- [ ] 2026-06-25 — LLMs emit literal `\n` (escaped backslash-n) in tool-call text → saved verbatim into notes. Normalize `\n`/`\t` in model-provided edit text. Independent visual audit caught this; unit tests didn't (they used real newlines). Lesson: when a tool consumes free-form model text destined for files, test the double-escaped case.
- [ ] 2026-06-25 — Sim container churn: every `flowdeck run` reinstalls → NEW data container, losing the seeded vault. To keep a seeded vault: `flowdeck run` once, seed, then relaunch via XcodeBuildMCP `stop_app_sim`+`launch_app_sim` (no reinstall) instead of `flowdeck run` again.

## Log

### 2026-06-24 — Long `type` into Claude Design composer auto-submitted partway

**What happened:** Typed a ~2600-char design brief into the claude.ai/design composer via the `type` action. The tool submitted the message partway through, leaving the final ~200 chars (a style-reinforcement paragraph) stranded in the composer. Had to inspect the DOM to confirm the bulk was sent and then clear the leftover to avoid an accidental second send.
**Why this matters:** A long single `type` can trip an auto-submit boundary, splitting the prompt. The sent message ended up missing its trailing paragraph.
**What better looks like:** For long prompts in web composers, either (1) paste via JS `value` set + input event, or (2) type the prompt MINUS the final newline-triggering content, verify nothing auto-sent, then send explicitly. Always verify composer length + thread occurrence after typing.

### 2026-06-24 — Fought the Claude Design canvas to capture new artboards

**What happened:** After the design AI generated 6 new artboards, spent many tool calls trying to get legible captures. The edit-mode canvas resists programmatic zoom/pan: scroll zooms but sticks near content and recenters on empty space; shift+1/shift+2 fit shortcuts did nothing; drag-to-pan worked only every other attempt. Eventually got legible 70% views by drag-panning, but `save_to_disk` on screenshot/zoom did not surface a file path, so couldn't SendUserFile the crops.
**Why this was slow:** Re-derived the known gotcha ([[reference_noto_design_project]]: "canvas resists programmatic pan/scroll in EDIT mode — Present mode allows scroll/pan"). I tried Present mode but it fit-to-width the whole multi-section page so artboards were tiny; didn't find a per-artboard present. Also tried the preview-origin raw HTML (MintPreviewToken) but token-as-query-param gave an error page.
**What better looks like:** (1) For reviewing/sharing Design artboards, the authoritative surface is the file itself — give Eugene the URL + section name rather than burning turns on lossy canvas captures. (2) If captures are truly needed, the design AI's own verification screenshots (it self-screenshots) are already legible — quote/relay those. (3) Investigate the correct MintPreviewToken auth (likely a cookie/redirect, not `?token=`) and document it, OR find Design's single-artboard present/export. Update the design memory with whichever works.
