# iOS Visual Evidence Audit

Verdict: PASS
Timestamp: 2026-06-10 14:43 local (audit run 14:34–14:42)
Repository: /Users/eugenechan/dev/personal/Noto-semantic-search (branch feature/semantic-search)
Simulator: Noto-SemSearch (iPhone 16 Pro, iOS 26.2, UDID 673FEE6E-1E2D-4550-88A6-472C2895162A)
App: com.eugenechan.Noto (scheme Noto, Debug)

## Change Audited

Hybrid semantic search: existing instant FTS keyword leg + new on-device semantic leg (multilingual embeddings, ≥3 chars, "Title + body" scope, ~250ms debounce) RRF-fused into one blended result list. Incremental background embedding derived from the keyword index lifecycle. Settings gains a "Rebuild semantic index" row with note/chunk stats.

All queries were run by this auditor from a clean sheet state (the implementer's leftover search sheet was closed first). Result list renders top-down: first item under "SEARCH RESULTS" is rank #1 (confirmed consistent across probes).

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| 1. Cross-lingual: EN query "rent negotiation with landlord" surfaces 续租谈判 in top 3 (expected #1) | PASS — 续租谈判 is rank #1 with its Chinese snippet (房东/续租/租金), zero query keywords in the note; "Title + body" scope selected | 02-crosslingual-rent.jpg |
| 2. Second cross-lingual probe (auditor's own): "recipe for chinese slow cooked pork" → 红烧肉 in top 3 | PASS — 红烧肉 is rank #1 (snippet 五花肉切块焯水…冰糖…). Query deliberately differs from implementer's probe; note is entirely Chinese so no literal overlap | 03-crosslingual-pork.jpg |
| 3. Keyword search not regressed: "Meeting" instant + usual highlighted snippet | PASS — two "Meeting Notes" results already painted ~0.7s after typing (04); list stable after semantic fuse settles (05); body-match highlight confirmed with second probe "wireframes" → Project Plan instant with yellow-highlighted "wireframes" in snippet (06) | 04-keyword-meeting-instant.jpg, 05-keyword-meeting-settled.jpg, 06-keyword-wireframes-highlight.jpg |
| 4. Settings shows "Rebuild semantic index" row with notes·chunks count | PASS — Search section shows "Rebuild semantic index — 9 notes · 60 chunks" plus explanatory footer; counts match semantic.sqlite (semantic_notes=9, semantic_chunks=60) | 07-settings.jpg |
| 5. Incremental indexing: append new-topic paragraph on disk → relaunch → paraphrase search finds it | PASS — appended "## Trip planning" (Reykjavik / northern lights / tripod) to Shopping List.md in the vault on disk; relaunched via `flowdeck run --no-build`; within ~20s the Shopping List chunk in semantic.sqlite contained the new text; UI query "aurora borealis viewing vacation" (zero word overlap with the note, old or new content) returned Shopping List at rank #1 | 08-incremental-aurora.jpg, 00-postrelaunch-vault.jpg |

## Artifacts

Directory: /Users/eugenechan/dev/personal/Noto-semantic-search/.codex/evidence/20260610-143423-ios-visual-audit/

- 00-postrelaunch-vault.jpg — vault list after relaunch (pre criterion-5 search)
- 01-launch.jpg — initial state found (implementer's leftover sheet, closed before auditing)
- 02-crosslingual-rent.jpg — criterion 1
- 03-crosslingual-pork.jpg — criterion 2
- 04-keyword-meeting-instant.jpg — criterion 3 (instant paint, ~0.7s)
- 05-keyword-meeting-settled.jpg — criterion 3 (post-fusion stability)
- 06-keyword-wireframes-highlight.jpg — criterion 3 (highlighted snippet)
- 07-settings.jpg — criterion 4
- 08-incremental-aurora.jpg — criterion 5
- evidence.md — this report

## Commands

- `flowdeck config get --json` (saved config reused: scheme Noto, sim Noto-SemSearch)
- `flowdeck ui simulator session start -S 673FEE6E-... --json`
- `flowdeck ui simulator tap --by-id search_button` / `tap "Settings"` / `tap --point 365,804` (sheet close ✕, coordinate per caller instructions)
- `flowdeck ui simulator type "<query>"`
- `flowdeck run --no-build --json` (relaunch for criterion 5)
- `xcrun simctl get_app_container … data` — used only to locate the vault/semantic.sqlite for criterion 5, as explicitly instructed by the caller (no FlowDeck equivalent exists)
- `sqlite3 semantic.sqlite` — count verification (9 notes / 60 chunks; Reykjavik chunk present after reindex)

## Notes

- Typing appends in the search field, so each query was run after closing and reopening the sheet (fresh state per probe).
- Criterion 3 highlight nuance: "Meeting" matches note titles, which do not render a yellow body highlight; a body-matching probe ("wireframes") was added to prove the highlighted-snippet behavior explicitly. Keyword results painted before the semantic debounce window — no regression observed.
- Criterion 5 nuance: relaunch via `flowdeck run --no-build` reinstalled the app, which rotated the data-container UUID and created a second SearchIndexes hash directory; both index DBs ended consistent (9/60, new chunk text present). The store-level incremental-vs-full distinction is covered by package tests (SC3); this audit proves the user-visible behavior: disk edit → relaunch → new topic searchable semantically within ~20s.
- Side effects left in place: Shopping List.md in the simulator vault retains the appended "Trip planning" paragraph (this was the instructed test edit). No source files, project files, or FlowDeck config were modified.
- Residual risk (unchanged from feature doc): real-device ANE latency/memory not verifiable on simulator.
