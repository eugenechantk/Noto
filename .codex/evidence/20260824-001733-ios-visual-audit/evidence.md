# iOS Visual Evidence Audit

Verdict: PARTIAL
Timestamp: 2026-08-24 00:17–00:27 HKT
Repository: /Users/eugenechan/dev/personal/Noto
Simulator: cc-7b98f5d6 — EC2E027D-1349-4371-99B0-C59EB4069E7E (iPhone 17 Pro, iOS 26.5, 402×874 pt, hardware keyboard attached)
App: com.eugenechan.Noto2 ("Noto 2"), scheme Noto2, installed build already on the simulator (not rebuilt; vault pre-seeded by `.maestro/seed-vault.sh`)
Vault on disk: `…/Containers/Data/Application/96194AE0-3CE8-4521-9DC9-A554AC3301AD/Documents/Noto`

## Change Audited

New second iOS app target "Noto2" in `Noto.xcodeproj` with three tabs — Capture (full-bleed TextKit2 editor → `inbox/<date>-<sha8>.md`), Search (system `.searchable`, hybrid results, streamed OpenRouter summary, ellipsis menu), Browse (folders-first explorer → shared editor with autosave). Shared code moved to `NotoShared/`. Feature doc: `.codex/feature/noto2-app.md` (SC1–SC7); design brief `.claude/design/noto2/noto2-ui-brief.md` §4.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| SC1 Capture writes `inbox/<date>-<hash8>.md`, hash8 = SHA-256 prefix of normalized body | PASS | Typed "Marble countertop quote came in under budget" → `inbox/2026-08-24-52479890.md`; `shasum -a 256` of the body = `52479890…`. `03-capture-sent-status.png`, `inbox-2026-08-24-52479890.md.txt`, `rec-01-capture-send-status.mp4` |
| SC1 frontmatter `id`, `created`, `updated`, `type: note`, `status: inbox`; body verbatim | PASS | `inbox-2026-08-24-52479890.md.txt` (id/created/updated/type/status, blank line, body verbatim) |
| SC1 idempotent: same text same day → same path, no second file | PASS | Re-sent identical text → status "Already filed · inbox/2026-08-24-52479890.md"; inbox still has 2 files. `05-capture-resend-already-filed.png` / `-tree.json` |
| SC2 Empty / whitespace-only rejected (Send disabled) | PASS | Empty: grey ✓ (`01-capture-empty.png`). Whitespace-only "   ": ✓ stays grey, tapping it writes nothing, no status line (`22-capture-whitespace-only.png`, inbox listing unchanged) |
| SC2 After send editor is empty and file indexed | PASS | `03`/`04` screenshots: editor cleared, placeholder back. Index proof: the open "Kitchen stone surfaces" search auto-re-ran on index change and now lists both inbox captures (`06-search-tab-state.png`); "granite" finds the inbox capture (`08-search-granite.png`) |
| SC3 Hybrid search lists title/breadcrumb/snippet; empty query → no results; tap → editor | PASS | `08-search-granite.png` (1 result, snippet with **granite** bold, breadcrumb "inbox"); `07-search-empty-prompt.png` (empty query → ContentUnavailableView "Search your notes · 8 notes indexed"); `15-search-result-opens-editor.png` (row tap → editor showing the inbox note, back chevron + Find) |
| SC4 Summary streams over top-N via OpenRouter; caption + provenance | PASS (streaming) / UNVERIFIED (needs-key, failure, cancel) | `rec-02-search-type-results-summary-stream.mp4` (typing → "Reading the top notes…" + spinner → streamed paragraph → "From the top 5 notes · AI-generated"); `09-search-meeting-streaming.png`, `10-search-meeting-done.png`. Bundled key present so needs-key/failed states could not be reached; stream-cancel only indirectly evidenced (each new query produced a fresh summary) |
| SC5 Browse: folders first then notes, by title, root + subfolder; tap → editor; autosave | PASS | `16-browse-root.png` (Archive, Captures, inbox, Projects, then 4 notes by title); `17-browse-inbox-subfolder.png`; `18`/`19` editor open + typed " Audit edit AUD1"; `shopping-list-after-edit.md.txt` shows the edit on disk before and after navigating back; `20-browse-after-back-tree.json` row "Shopping List, 25 seconds ago" |
| SC6 Separate app: bundle id, display name, icon, entitlements, runs on iOS 26 sim; Noto still builds/tests | PARTIAL | Installed `Noto2.app` Info.plist: `CFBundleIdentifier=com.eugenechan.Noto2`, `CFBundleDisplayName=Noto 2`, `MinimumOSVersion=26.0`, `Noto2Icon*.png`; `21-home-screen-icons.png` (own orange "N" icon labelled "Noto 2"); app runs on the iOS 26.5 sim throughout. **No `Noto2.entitlements` exists and no `CODE_SIGN_ENTITLEMENTS` on the Noto2 configs** (feature doc residual-risk line admits "no entitlements file yet"). Noto-iOS build + NotoTests not re-run by the auditor (implementer reports build OK, 301/313 with 10 pre-existing failures) |
| SC7 Shared code in `NotoShared/`, compiled into both targets; nothing from `Noto/Views` or `NotoApp.swift` in Noto2 | PASS (static) | pbxproj: Noto target syncs `Noto` + `NotoShared`; Noto2 target syncs only `NotoShared` + `Noto2` (PBXFileSystemSynchronizedRootGroup, no exceptions); 33 files under `NotoShared/`; `git status` shows the `R` renames from `Noto/` |
| Brief §4 Capture: no nav title; ✓ disabled when empty, enabled on first char; send clears + status line ≤1.5 s; placeholder only when empty | PASS | `01` (no title, grey ✓, placeholder), `02` (orange ✓ + ✕ discard, placeholder gone), `03` (status line "Filed · inbox/…" footnote above the accessory bar), `04` (status gone ~2 s later), `rec-01` |
| Brief §4 Search: system `.searchable`, title/date/snippet with bolded term, "N results for “q”", summary paragraph with "Summary" caption and no card, ContentUnavailableView for both empty states | PARTIAL | Field/rows/count/caption/no-card: PASS (`08`, `09`, `10`, `12-search-idle-with-menu.png`). Empty-query state: PASS (`07`). **No-results state could not be reached**: "zzzzqq", "xq7zv9", "qwxzjk plmnb" all return 1–4 semantic hits and an LLM summary saying nothing matches (`11-search-zzzzqq-no-empty-state.png`) |
| Ellipsis menu "OpenRouter key…" / "Rebuild index" | PASS | `13-search-menu-open.png`, `14-openrouter-key-sheet.png` (sheet says "Using the key bundled with this build") |

## Artifacts

All under `/Users/eugenechan/dev/personal/Noto/.codex/evidence/20260824-001733-ios-visual-audit/`:

- `01-capture-empty.png` — Capture empty: no title, grey ✓, placeholder, no ✕
- `02-capture-typed.png` — draft typed: orange filled ✓, ✕ discard, placeholder gone
- `03-capture-sent-status.png` — after Send: editor cleared, "Filed · inbox/2026-08-24-52479890.md"
- `04-capture-after-status-cleared.png` — status line gone
- `05-capture-resend-already-filed.png` — idempotent re-send
- `06-search-tab-state.png` — live query re-ran after index change, inbox captures listed
- `07-search-empty-prompt.png` — ContentUnavailableView "Search your notes"
- `08-search-granite.png` — 1 result, "granite" bolded, breadcrumb "inbox"
- `09-search-meeting-streaming.png`, `10-search-meeting-done.png` — summary streaming / done
- `11-search-zzzzqq-no-empty-state.png` — nonsense query still returns semantic hits
- `12-search-idle-with-menu.png`, `13-search-menu-open.png`, `14-openrouter-key-sheet.png`
- `15-search-result-opens-editor.png` — row → editor
- `16-browse-root.png`, `17-browse-inbox-subfolder.png`, `18-browse-open-shopping-list.png`, `19-browse-note-edited.png`, `20-browse-after-back.png`
- `21-home-screen-icons.png` — "Noto 2" icon on the home screen
- `22-capture-whitespace-only.png` — whitespace draft, ✓ still disabled
- `rec-01-capture-send-status.mp4` (43 s) — focus → type → Send → status line → clear
- `rec-02-search-type-results-summary-stream.mp4` (33 s) — clear → type "meeting roadmap" → results → "Reading the top notes…" → streamed summary → provenance
- `*-tree.json` — accessibility trees for every screenshot
- `inbox-2026-08-24-52479890.md.txt`, `shopping-list-after-edit.md.txt` — on-disk proof

## Commands

- `flowdeck config get --json` (saved config points at another sim; overridden with the caller's literal UDID on every command, config not modified)
- `flowdeck ui simulator session start -S "EC2E027D-…" --json`
- `flowdeck ui simulator screen --screenshot --json`, `tap` (by id / label / `--point`), `type`, `key delete`
- `flowdeck simulator record -o <evidence-dir> -t 40s|30s --codec h264`
- `flowdeck simulator button home`, `flowdeck simulator launch com.eugenechan.Noto2`
- `xcrun simctl get_app_container` (only as instructed by the caller, to locate the data/app containers for on-disk proof)

Tab switches were done by coordinate (Capture 115,812 / Search 200,812 / Browse 287,812) because tab items are not exposed by label while the editor accessory bar is up; search field focus by 200,139.

## Notes

Defects / residual risk found:

1. **No-results empty state is effectively unreachable.** With the semantic leg on (`semanticMinScore` 0.76, `semanticRelativeGap` 0.12), gibberish queries still return 1–4 neighbours, so `ContentUnavailableView.search` never shows and an OpenRouter summary request is spent telling the user nothing matches. Brief §4 "ContentUnavailableView for both empty states" unproven in practice.
2. **Summary renders raw Markdown.** The model returns `**bold**` and `*   ` bullets; `Text(model.summary)` shows the asterisks literally (`08`, `09`, `10`, `11`). Either ask for plain prose in the prompt or render via `AttributedString(markdown:)`. Brief §2.4 "plain paragraph" intent is met structurally but reads unpolished.
3. **SC6 "own entitlements" not met** — no `Noto2.entitlements`, no `CODE_SIGN_ENTITLEMENTS` on the target (documented by the implementer as a residual risk).
4. Minor: semantic-only hits carry `updatedAt: nil` (`HybridSearchFusion.swift:99/117`), so some result rows show no date while keyword hits do (`06`, `09`); capture notes with no heading are titled by filename in Search ("2026-08-24-6156e49a") but by first line in Browse ("Quartzite sample…").
5. Minor: with the hardware keyboard attached the editor accessory bar floats over the tab bar (`02`, `03`); expected to be hidden by the software keyboard on device — not verified.
6. Not independently re-run: `flowdeck build -s Noto-iOS` / NotoTests (to avoid parallel builds on shared DerivedData); needs-key / failure / stream-cancel summary states (bundled key present); SC4 top-N ≤ 8 and truncation (unit-tested only).
