# iOS Visual Evidence Audit

Verdict: PASS
Timestamp: 2026-08-24 00:35–00:43 HKT
Repository: /Users/eugenechan/dev/personal/Noto
Simulator: cc-7b98f5d6 — EC2E027D-1349-4371-99B0-C59EB4069E7E (iPhone 17 Pro, iOS 26.5, 402×874 pt, hardware keyboard attached)
App: com.eugenechan.Noto2 ("Noto 2"), scheme Noto2. Installed build verified identical to the DerivedData product (`md5 d29b7ac9…` for both `Noto2.app/Noto2`, built Aug 24 00:31). Not rebuilt or reinstalled by the auditor.
Vault on disk: `…/Containers/Data/Application/41C24096-79AE-4157-AFF8-38D04B6943D8/Documents/Noto` (reseeded: 6 notes, no `inbox/` at start)

## Change Audited

Re-audit of the "Noto 2" iOS target after the three fixes for the defects raised in `.codex/evidence/20260824-001733-ios-visual-audit/evidence.md` (PARTIAL): (1) semantic "peak margin" gate so gibberish queries reach the no-results state and spend no summary; (2) summary rendered as clean prose via `AttributedString(markdown:)` with a "plain prose" prompt and a pluralized provenance line; (3) `Noto2/Noto2.entitlements` + `CODE_SIGN_ENTITLEMENTS` on both Noto2 configs. Plus a brief re-confirmation of the §4 acceptance list (Capture empty/typed/sent, Search bolded term, Browse → note → edit persists).

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| Fix 1: gibberish "zzzzqq" → system ContentUnavailableView.search "No Results for “…”" | PASS | `01-search-zzzzqq.jpg` + tree: `searchNoResults` "No Results for “Zzzzqq”" / "Check the spelling or try a new search."; no `searchSummaryCaption`, no spinner, no result rows |
| Fix 1: "xq7zv9" → no results | PASS | `02-search-xq7zv9.jpg` / tree (same shape) |
| Fix 1: "qwxzjk plmnb" → no results | PASS | `03-search-qwxzjk-plmnb.jpg` / tree (same shape) |
| Fix 1: no summary spent on gibberish | PASS (UI + code) | Trees for 01–03 captured 3–4 s after typing show no summary caption/"Reading the top notes…"/spinner; `SearchModel.startSummary` returns `.idle` before touching the key when `results.isEmpty` |
| Fix 1: real queries still return hits — "farmers market" | PASS | `06-search-farmers-market-streaming.jpg`, `07-search-farmers-market-done.jpg`: "3 results for “Farmers market”", Shopping List first with **farmers market** bold, summary streamed |
| Fix 1: real queries still return hits — "meeting roadmap" | PASS | `00-start-search-meeting-roadmap.jpg` (5 results, summary, "From the top 5 notes · AI-generated") — state found on screen at session start, from the implementer's own run on this build |
| Fix 1: real queries still return hits — "granite" | PASS (after seeding) | Reseeded vault had no note containing "granite" (`grep -ril granite` on the vault = nothing), so the first "granite" query correctly showed No Results (`04-search-granite-no-note-in-vault.jpg`). After filing two inbox captures containing "granite", the same query returns "2 results for “Granite”" with **granite**/**Granite** bold and breadcrumb "inbox" (`12-search-granite-after-capture.jpg`) |
| Fix 2: summary is clean prose, no literal `*`/`**` | PASS | `00` (meeting roadmap, paragraph), `07` (farmers market, paragraph), `12` (granite — model returned two list lines; rendered as "•" bullets, no asterisks), `13-search-wireframes-7-hits.jpg` (paragraph). Full `summaryText` labels in the `*-tree.json` files contain no `*` characters |
| Fix 2: provenance "From the top N note(s) · AI-generated" | PASS (plural) / code-only (singular) | "From the top 5 notes", "From the top 3 notes", "From the top 2 notes", "From the top 7 notes" observed. A 1-hit query could not be produced on this corpus (semantic neighbours always join a keyword hit, e.g. "wireframes" → 7); singular branch is `note\(count == 1 ? "" : "s")` in `SearchScreen.swift:256` and covered by the implementer's unit tests |
| Fix 3: `Noto2/Noto2.entitlements` exists | PASS | File present (empty `<dict/>` plist) |
| Fix 3: `CODE_SIGN_ENTITLEMENTS = Noto2/Noto2.entitlements` on both Noto2 configs | PASS | `project.pbxproj` lines 958 (Release, `PRODUCT_BUNDLE_IDENTIFIER = com.eugenechan.Noto2`) and 993 (Debug) |
| Fix 3: built product carries an entitlements dict | PASS | `codesign -d --entitlements - …/Debug-iphonesimulator/Noto2.app` → `[Dict]` (saved as `codesign-entitlements-Noto2.app.txt`; the `:-` form prints the XML plist with an empty dict) |
| §4 Capture empty: no nav title, grey ✓, placeholder, no ✕ | PASS | `08-capture-empty.jpg` / tree (`capturePlaceholder`, `captureSendButton`, no `captureDiscardButton`) |
| §4 Capture typed: orange filled ✓ + ✕ discard, placeholder gone | PASS | `09-capture-typed.jpg` / tree (`captureDiscardButton` present, no `capturePlaceholder`) |
| §4 Send → editor cleared + status line; file on disk with correct hash8 | PASS | `11-capture-sent-status-line.jpg` / tree: `captureStatusLine` "Filed · inbox/2026-08-24-9e2156e9.md", editor empty, placeholder back. On disk: `inbox-2026-08-24-6b65ab34.md.txt` and `inbox-2026-08-24-9e2156e9.md.txt` (frontmatter id/created/updated/type: note/status: inbox, body verbatim); `shasum -a 256` of each body = `6b65ab34…` / `9e2156e9…` |
| §4 Search row shows bolded term | PASS | `12-search-granite-after-capture.jpg` (**granite** in both rows), `07` (**farmers market**) |
| §4 Browse root → note → edit persists on disk | PASS | `14-browse-root.jpg` (Archive, Captures, inbox, Projects, then 4 notes by title); `15-browse-project-plan-open.jpg`; typed " AUD2 edit" → `16-browse-project-plan-edited.jpg`; `project-plan-after-edit.md.txt` line 15 `- [x] Review requirements AUD2 edit` on disk within 3 s and still after back (`17-browse-after-back.jpg`, row "Project Plan, 18 seconds ago") |

## Artifacts

All under `/Users/eugenechan/dev/personal/Noto/.codex/evidence/20260824-003537-ios-visual-audit/`:

- `00-start-search-meeting-roadmap.jpg` — state at session start: clean-prose summary, "From the top 5 notes · AI-generated"
- `01-search-zzzzqq.jpg`, `02-search-xq7zv9.jpg`, `03-search-qwxzjk-plmnb.jpg` — system no-results state for all three gibberish queries
- `04-search-granite-no-note-in-vault.jpg` — "granite" before any granite note existed → No Results (gate working on a keyword miss)
- `06-search-farmers-market-streaming.jpg`, `07-search-farmers-market-done.jpg` — real query: 3 results, bold term, prose summary, provenance
- `08-capture-empty.jpg`, `09-capture-typed.jpg`, `10-capture-sent-status.jpg` (after status cleared), `11-capture-sent-status-line.jpg` (status line visible)
- `12-search-granite-after-capture.jpg` — 2 inbox hits, bold term, "•" bullets rendered (no asterisks)
- `13-search-wireframes-7-hits.jpg` — prose summary; shows semantic neighbours joining a keyword hit
- `14-browse-root.jpg`, `15-browse-project-plan-open.jpg`, `16-browse-project-plan-edited.jpg`, `17-browse-after-back.jpg`
- `rec-01-gibberish-no-results-then-farmers-market-summary.mp4` (80 s, h264) — clear → "zzzzqq" → No Results → "xq7zv9" → No Results → "qwxzjk plmnb" → No Results → "granite" (no note yet) → No Results → "farmers market" → results → streamed summary → provenance
- `*-tree.json` — accessibility tree for every screenshot
- `inbox-2026-08-24-6b65ab34.md.txt`, `inbox-2026-08-24-9e2156e9.md.txt`, `project-plan-after-edit.md.txt` — on-disk proof
- `codesign-entitlements-Noto2.app.txt` — codesign output for the built product

## Commands

- `flowdeck ui simulator session start -S "EC2E027D-1349-4371-99B0-C59EB4069E7E" --json` (session A95F0E4A)
- `flowdeck ui simulator screen --screenshot -S "EC2E…" --json`; `tap --point x,y` / `tap "<id>" --by-id` / `tap "<label>"`; `type "<text>"`
- `flowdeck simulator record -S "EC2E…" -o <evidence-dir> -t 75s --codec h264 --json`
- `flowdeck simulator list --json`, `flowdeck apps`, `flowdeck ui simulator session stop`
- `xcrun simctl get_app_container EC2E… com.eugenechan.Noto2 app|data` (as instructed by the caller, to locate the bundle/data containers)
- `codesign -d --entitlements - <Noto2.app>` (caller-requested static check)

Tab switches by coordinate (Capture 115,812 / Search 200,812 / Browse 287,812), search field focus 200,92, clear via ⓧ at 306,92, per the caller's notes. No `flowdeck run`/build was issued; the app was never reinstalled.

## Notes

- The three prior defects are fixed on the installed build: no-results state reachable for all three gibberish strings with no summary spent; summaries render without literal Markdown; entitlements file + setting + signed dict present.
- Residual (not a regression, informational): the prompt still permits "•" bullets "if the notes are unrelated", and the model used them for the granite query — rendered cleanly but not a single paragraph. The singular "From the top 1 note" branch was not reachable on this corpus; verified by code/unit test only.
- Residual: semantic neighbours still join a keyword hit within the relative gap ("wireframes" → 7 results incl. Shopping List; "farmers market" → 3). The peak test only gates the all-semantic/weak case, as designed.
- Observation: the Capture draft persists in `@AppStorage("noto2.capture.draft")` by design, so the whitespace-only draft ("   ") from the previous audit was still in the editor at session start (placeholder still showed, ✓ still grey); my first typed capture therefore had three leading spaces, which `normalizedBody` trimmed before hashing/writing (file body and sha8 match the trimmed text).
- Observation (pre-existing, shared editor): editing a note in Browse does not bump frontmatter `modified:` (stays 2026-03-15), same as in the previous audit's Shopping List edit.
- Tooling: the session's flowdeck guard hook created and booted an extra simulator `cc-7b98f5d6-afbf5b21` (9D4041F7-85E5-4D2D-B049-06404F60DAA1) when it saw a shell-variable `-S`; it was not used. Flowdeck `tap --id <x>` is not valid syntax (`tap "<id>" --by-id` is) — one early "tap send on empty" attempt was a no-op for that reason and was discarded; the empty-draft send-disabled behaviour rests on the previous audit's whitespace test plus the unchanged grey ✓.
- Not re-run: Noto2Tests / NotoSearch tests (caller reports 21/21 and package tests green), Noto-iOS build.
