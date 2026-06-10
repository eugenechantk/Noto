# iOS Visual Evidence Audit

Verdict: PARTIAL
Timestamp: 2026-06-10 18:10 HKT
Repository: /Users/eugenechan/dev/personal/Noto-semantic-search (branch feature/semantic-search)
Simulator: Noto-ChatTool — iPhone 16 Pro, iOS 26.2, UDID 974F0FEA-1B52-4F66-8F7C-4DFF80FC7284
App: com.eugenechan.Noto (Debug, freshly rebuilt from the worktree via `flowdeck run`)
Chat model in use: google/gemini-3.1-flash-lite (from saved chat transcript frontmatter)

## Change Audited

Phase 4 of `.codex/feature/semantic-search.md` (SC12–SC13): the AI chat agent gains a `search`
tool running the same hybrid keyword+semantic pipeline as the in-app search sheet
(`HybridNoteSearch.run`, confirmed in `Noto/SemanticSearchService.swift` →
`HybridChatSearchProvider`), with created/updated ISO date filters. Tool hits feed the expandable
tool-trace row; surfaced paths feed citations/SOURCES.

## Important environment deviations (affect interpretation)

1. The vault was NOT the briefed 9-note seed: it contained **783 notes** (a `Captures/` folder
   with 773 real capture notes), and **782 of 783 notes had file-modified dates within the last
   5 days** (seeding touched them). Only `Projects/Legacy CMS Migration.md` (2026-05-01) was old.
   Verified read-only in the index DB (`search.sqlite` notes table).
2. The semantic index was only **215/783 notes embedded** when the audit started. The seeded
   root/Projects/Chinese notes embed last (path sort puts them after `Captures/`). I waited until
   the embed finished (786 notes · 10,200 chunks, `20-settings-semantic-index-complete.jpg`)
   before judging semantic criteria. Criterion-2 attempt 1 failed purely because of this
   (the in-app search sheet failed identically at that moment — `06`, `07`).
3. Saved chat transcripts in `Chats/` are themselves indexed, so later turns surface earlier
   conversations among hits (visible in `09`, `19`).

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| 1a. "what did I talk about my projects in the last 5 days" → trace shows a `Search` call | PARTIAL — search invoked in **1 of 4** fresh-chat runs; the other 3 used only grep's date-listing ("Searched · 50 notes") | 10 (search fired, run 3); 02, 21 (grep-only runs 1 and 4) |
| 1b. Hits/SOURCES include "Noto Search Rollout" + recent notes, NOT "Legacy CMS Migration" | PARTIAL — Legacy CMS Migration never appeared (correct); all hits/sources were recent notes; but **Noto Search Rollout never surfaced** — crowded out by 773 recently-modified captures (environment deviation, not a date-filter failure) | 11 (hits all recent sections), 12 (sources, no Legacy, no Rollout) |
| 1c. Answer has inline citations + SOURCES | PASS — answer computed the cutoff ("since June 5, 2026"), inline numbered citations, SOURCES list | 10, 12 |
| 2. Semantic reach: "did I negotiate anything with my landlord recently?" surfaces 续租谈判 and cites it | PASS — single `Search` call; answer recounts the lease renewal (8% increase, refrigerator, repaint) citing 续租谈判 as the only source | 08 (answer + SOURCES), 09 (expanded trace) |
| 3. No date scope: "what projects have I written about?" → Legacy CMS Migration appears | PASS — answer names "Legacy CMS Migration and Noto Search Rollout" with citation; `Search` + `Listed Projects` in trace | 13, 14, 15 |
| Auditor differential (date filter through `search`, zero ranking noise) | PASS — unscoped "did I write anything about a CMS migration?" → single `Search` call, Legacy CMS Migration is hits #1–#2 and the sole cited source; scoped "…in the last 5 days?" → answer: "you have not written anything new about a CMS migration in the last 5 days" | 17, 16 (unscoped, hits expanded); 18, 19 (scoped) |

## Artifacts

All under `.codex/evidence/20260610-171839-ios-visual-audit-chattool/`:

- `01-launch.jpg` — app launched, seeded vault visible (Projects folder, 续租谈判)
- `02/03` — criterion-1 attempt 1: grep-only trace, capture-dominated sources
- `04/05` — criterion-2 attempt 1 (failed while semantic index incomplete): search hits keyword-only, no 续租谈判
- `06` — in-app search sheet failing the same query at the same moment (proves environment, not chat-tool, issue)
- `07` — Settings: semantic index at 215 notes mid-build
- `08/09` — criterion-2 PASS after embed completed
- `10/11/12` — criterion-1 attempt 3: grep + Search trace, "since June 5, 2026" answer, recent-only hits/sources, Legacy absent
- `13/14/15` — criterion-3 PASS: both project notes named, Search + list trace
- `16/17` — unscoped CMS question: Legacy CMS Migration as top search hits + sole source
- `18/19` — scoped CMS question: "nothing new in the last 5 days" conclusion
- `20` — Settings: semantic index complete (786 notes · 10,200 chunks)
- `21` — criterion-1 attempt 4: grep-only again (model behavior)
- `c1-final-tree.json` — accessibility tree of criterion-1 sources list

## Commands

- `flowdeck config get --json` (saved config targets a different sim; caller's `-S` override used throughout, config untouched)
- `flowdeck run -S 974F0FEA-1B52-4F66-8F7C-4DFF80FC7284 --json` (build + install + launch)
- `flowdeck ui simulator session start -S 974F0FEA-... --json` (session A1463330)
- `flowdeck ui simulator tap / type / swipe -S 974F0FEA-...` for all chat turns
- Read-only sqlite inspection of `search.sqlite` / `semantic.sqlite` in the app container (diagnostics only; no simctl/xcrun used)

## Notes

- **Why PARTIAL:** the tool, pipeline, date filters, citations, and trace UI all demonstrably work
  (criteria 2, 3, and the CMS differential are clean passes). The gap is SC13's exact wording: the
  canonical "last 5 days projects" question triggered the `search` tool in only 1 of 4 fresh-chat
  runs on gemini-3.1-flash-lite — the model usually satisfies it with grep's date-only listing
  (whose own description advertises "notes modified in the last few days"). That is prompt-steering
  /model behavior, not broken code, but it makes SC13 unreliable as a live demo. "Noto Search
  Rollout" never surfacing is attributable to the 773 recently-touched captures, which the briefed
  environment said would not be there.
- The search tool's collapsed trace row renders as bare "Search" (wrench icon, no query/filters)
  because `ChatSheet.ToolStepView` and `ChatSession.ToolStep.humanize` only special-case
  grep/read/list — the `search` case falls to `default`. Cosmetic gap worth fixing (showing the
  query and date filters would also have made this audit's filter verification direct).
- Tool arguments are not persisted in chat transcripts and never shown in UI, so the computed
  `updated_after` value on the one successful SC13 run is evidenced only indirectly (answer text
  "since June 5, 2026"; hits/sources all recent; Legacy absent). Package tests (SearchToolTests,
  13 green per implementer) cover the arg plumbing.
- Saved chats polluting search results is by design (chats are notes) but degrades repeated-question
  demos; auditors/implementers should expect prior turns to appear as hits.
