# iOS Visual Evidence Audit

Verdict: PASS
Timestamp: 2026-06-10 20:22 (local)
Repository: /Users/eugenechan/dev/personal/Noto-semantic-search (branch feature/semantic-search)
Simulator: Noto-ImgSearch — A66F9A95-06B5-4983-816B-7907C7E917A1 (iPhone 16 Pro, booted, app pre-installed/running per caller)
App: com.eugenechan.Noto

## Change Audited

Stage-1 image search (describe-then-embed), feature doc `.codex/feature/semantic-search.md` SC14–SC18: images referenced in notes (vault `.attachments/` and remote http(s) URLs) are OCR'd + labeled on-device via Apple Vision; the text is embedded with the granite model as `kind='image'` chunks in `semantic.sqlite`. Image-sourced search results show breadcrumb "in image: <alt>" with OCR snippet and navigate to the owning note.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| 1. Vault-attachment OCR search: "rebuild semantic index" (Title + body) surfaces "Design Reference" with breadcrumb "in image: settings screen" + OCR snippet; body lacks those words | PASS | `03-design-reference-result.jpg` (breadcrumb "in image: settings screen", snippet "2:39 Settings Storage Vault Location On This Device Change Vault … "); `design-reference-note-body.md` (body = one sentence, no "rebuild"/"semantic"/"index"); `db-verification.txt` (image chunk snippet contains "Refresh search index Rebuild semantic index") |
| 2. Remote-image OCR search: "solar energy dashboard output" surfaces owning capture with "in image:" breadcrumb; matched chunk's image_path is pbs.twimg.com | PASS | `05-query-solar-dashboard.jpg` (result #2 "The $120K Blueprint…" with "in image: Image", snippet "9. Suno Solar Energy Hub … Total System Output 312 …"); `db-verification.txt` (image_path = `https://pbs.twimg.com/media/G_Ma125W8AEGVIw.jpg`, line 296) |
| 3. Tapping an image-sourced result opens the owning note | PASS | `04-tapped-design-reference.jpg` (Design Reference note open, image rendered); `06-tapped-remote-image-result.jpg` / `06b` ($120K Blueprint note open — lands at top of note; line-level bonus NOT observed for this long note) |
| 4. Incremental: sweeps do not re-describe unchanged images | PASS | `db-image-chunks-T0.txt` (20:14:53) vs `db-image-chunks-T1.txt` (20:18:36): all 155 T0 image paths unchanged at 1 chunk each, 0 dropped, 0 duplicated; growth (+21) only from new Readwise images. Row-identity check `db-image-rows-A-201855.txt` vs `db-image-rows-B-202035.txt`: all 181 rows bit-identical (rowid + chunk_id + content_hash), +26 new-only — no delete/reinsert churn |
| 5. Cross-lingual: 重建搜索索引 surfaces Design Reference via English OCR text | PASS | `07-query-chinese.jpg` (Chinese query pasted via simulator pasteboard); `08-chinese-design-reference.jpg` (Design Reference with "in image: settings screen" + English OCR snippet in results) |

## Artifacts

All under `.codex/evidence/20260610-200935-ios-visual-audit-imagesearch/`:

- `01-launch.jpg` — app running, search sheet open, Readwise captures syncing
- `02-query-rebuild-semantic-index.jpg` — query typed, Title + body scope, top results
- `03-design-reference-result.jpg` — Design Reference row with "in image: settings screen" breadcrumb + OCR snippet (also two other image-sourced rows: "in image: Image", "顶级的 Skill 长什么样")
- `04-tapped-design-reference.jpg` — navigation into Design Reference note
- `05-query-solar-dashboard.jpg` — remote-image hit with "in image:" breadcrumb + Suno solar OCR snippet
- `06-tapped-remote-image-result.jpg`, `06b-remote-image-result-settled.jpg` — navigation into owning capture note (lands at top)
- `07-query-chinese.jpg`, `08-chinese-design-reference.jpg` — cross-lingual probe
- `db-verification.txt` — semantic.sqlite read-only queries (chunk kind/image_path/describer_version/snippet)
- `db-image-chunks-T0.txt`, `db-image-chunks-T1.txt` — per-image_path chunk counts, two sweeps ~4 min apart
- `db-image-rows-A-201855.txt`, `db-image-rows-B-202035.txt` — rowid/chunk_id/content_hash identity snapshots ~100 s apart
- `design-reference-note-body.md` — copy of the seeded note proving body lacks query terms

## Commands

- `flowdeck config get --json` (saved config points elsewhere — untouched; `-S <UDID>` passed explicitly throughout)
- `flowdeck simulator list --json`, `flowdeck apps --json`
- `flowdeck ui simulator session start -S A66F9A95-06B5-4983-816B-7907C7E917A1 --json`
- `flowdeck ui simulator type "<query>" -S <UDID>`; `tap "<label>" / --by-id search_button / --point x,y [--duration 1.2]`; `swipe --from --to`
- `xcrun simctl get_app_container <UDID> com.eugenechan.Noto data` + `sqlite3 "file:…semantic.sqlite?mode=ro"` (read-only, caller-authorized)
- `xcrun simctl pbcopy <UDID>` + long-press → Paste for the Chinese probe (caller-authorized)

## Notes

- Ranking caveat (criterion 1): "Design Reference" surfaced at position ~9 of the result list — one short scroll below several literal keyword matches ("index", "semantics" in body text) from the busy Readwise vault. It is clearly surfaced with the correct image breadcrumb; "prominently" is judged met in context of a vault with ~1,500 text chunks, but it is not top-3.
- Seed caveat: the note body does contain the word "settings" ("settings layout discussion"), contrary to the caller's claim — but none of the actual query terms (rebuild/semantic/index) or snippet terms (storage/vault location), so the match is unambiguously image-sourced (DB confirms the matched chunk is `kind='image'`).
- Criterion 3 bonus (line-level navigation) not observed for the long remote-image note: landing was top-of-note, which is within the stated pass bar.
- Index churn from live Readwise sync was real (148 → 207 image chunks over the session); all growth was new images only, reinforcing criterion 4.
- No app source, config, or FlowDeck saved config was modified. Database accessed strictly read-only (`mode=ro`).
