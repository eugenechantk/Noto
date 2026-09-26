# iOS Visual Evidence Audit

Verdict: PARTIAL
Timestamp: 2026-09-26 09:58–10:29 HKT (01:58–02:29 UTC)
Repository: /Users/eugenechan/dev/personal/Noto
Simulator: cc-56c91326, iPhone 17 Pro, iOS 26.3, UDID BA34BC0A-B394-456D-96CC-8F4E10E46F0E (402x874 pt, screenshots 1 px = 1 pt)
App: com.eugenechan.Noto2 (scheme Noto2) + Noto2ShareExtension.appex, as already installed. Not rebuilt. The installed binary (00:18:15 local) is newer than every changed source file (latest is ShareViewController.swift, 00:16:41).

## Change Audited

1. The share-sheet confirmation ("Link captured") was redesigned.
2. Link preview cards (editor, Digest, share sheet) were redesigned to show a banner image, title, up to 3 lines of description and the site, and to use Open Graph metadata when LinkPresentation returns too little.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| SC1: header has only a circular X at top right; tapping it closes the sheet | PASS | `04-sheet-loaded-preview.png`: no header title, only a 44x44 pt glass circle at x 342–386, y 84–128 (16 pt right margin). Tapping (364,106) dismissed both Noto's sheet and the system share sheet and returned to Safari: `05-after-x-close-safari.png`. The capture was still staged (`data/pending-capture-apple-newsroom.json`) and later filed (`data/2026-09-26-78733423.md`). |
| SC2: content centred horizontally and vertically between the header and the buttons | PASS (see note) | `04m-sheet-layout-measurements.png`. **Horizontal:** icon x 163–238, title 132–269, message 68–333, card 24–377. Each centre is x = 201.0, which is the screen centre. **Vertical:** content block y 162–638 (centre 400.0). The region between the X row (ends 128) and the button stack's 12 pt top padding (671) has its centre at 399.5, so the content is centred to within 0.5 pt. Measured against the visible edges instead (X bottom 128 to Keep editing top 683), there is 34 pt above the content and 45 pt below, so the content sits 5.5 pt above the visible midpoint. The failure state measures the same way: content 365–513, centre 439, region centre 438.5 (`13b-failure-state.png`). |
| SC3: icon is a circle with a tick, orange accents | PASS | `04-sheet-loaded-preview.png`: a 76x76 pt circle (row widths are symmetric), orange ring (~#78381F on dark), translucent orange fill, and tick colour #FF6B2E (the accent is #FF6A2E). |
| SC4: title reads "Link captured"; message says saved to inbox | PASS | Every success capture shows "Link captured" and "Saved to your inbox as a quick capture." (`03b`, `04`, `06b`, `08b`, `11b`, `20a`). The X/Instagram "media" variant of the message was not triggered (see Notes). |
| SC5: preview card shows title, description, site and image; while loading, the page title (or host) with "Loading preview…" | PASS | Loading states captured for uncached URLs: `03b-sheet-loading-preview.png` ("Newsroom - Apple / Loading preview…", link-symbol banner, host), `06a`, `08a`, `11a`, `21a-gnu-loading-two-line-title.png` (Safari title wrapping to 2 lines). Loaded states: `04` (Newsroom, 3-line description, favicon + apple.com, banner), `06b`, `08b`, `10a`, `20a`. No-image page: `11b-example-loaded-placeholder-banner.png` shows a placeholder banner (link symbol + example.com). Sequence strips: `03-share-sequence-strip.png`, `06-…`, `11-…`. Card is 300 pt tall (y 338–637). |
| SC6: "Keep editing" (primary, orange) and "Close" (secondary) pinned to the bottom; Keep editing opens the capture note; Close dismisses | PARTIAL | Layout: Keep editing y 683–749 (#FF692D orange), Close y 761–827 (dark glass), 20 pt side margins, pinned to the bottom (`04m`). **Close:** dismissed everything and returned to Safari (`10a` → `10b`). **Keep editing:** opened the capture note in the editor, showing the link card, in 3 of 4 runs: warm (`09-keep-editing-warm-opens-capture-note.png`), cold after reboot with 1 staged capture (`20b`, recording `20-cold-launch-keep-editing-python-org.mov`), and cold with 2 staged (`21b`). **In 1 of 4 runs (the first cold launch) Noto 2 opened on the Digest tab instead**, with that capture as the top card (`07-keep-editing-cold-launch-opens-digest.png`). The app logged "Shared capture 22478479-… not filed this session; showing Digest", although the same launch had just filed it (`data/log-excerpts-before-reboot.log`, Run 2). See Defect 1. |
| SC7: swiping down closes Noto's sheet; the capture is still filed | PASS | A synthetic swipe from (200,160) to (200,780) closed Noto's sheet. The extension logged "sheet swiped away". The system share sheet then reappeared, which is expected iOS behaviour (`12a-after-swipe-down-system-share-sheet.png`, `12-swipe-down-sequence-strip.png`). The capture stayed staged. On the next activation of Noto 2 it was filed as `inbox/2026-09-26-ed72b168.md` (`data/`). It appears in Browse → inbox (`14-browse-inbox-all-captures-filed.png`) and as the top Digest card (`18a-digest-example-placeholder-card.png`). |
| SC8: failure state (warning icon, "Couldn't capture link", message, only Close) | PASS (triggered) | Triggered in the simulator by selecting the word "examples" on example.com, then Share… → Noto 2 (`13a`). The extension logged `share payload urls=0 texts=1`. The sheet shows a red (#FF5A5F) exclamation circle, "Couldn't capture link", "Nothing shared looked like a web link.", no link card and only Close (`13b-failure-state.png`). Close dismissed it (`13c`). Nothing was staged. |
| SC9: capture behaviour unchanged; the link lands in `inbox/` | PASS | All 8 shares (X, Keep editing x4, Close, swipe, and X before a cold launch) were filed, one note each, with no duplicates. Each note has `type: note`, `status: inbox` and a body of `[Page title](url)` (`data/inbox-final-listing.txt` and the note copies in `data/`). Staging went through the App Group `pending-captures/` and was drained on activation. |
| SC10: editor cards show a full-width banner, title, ≤3-line description, site icon + name; no-image pages get a placeholder; one fixed height; no overlap; the same card on Digest | PASS (iOS) | Existing note "Link cards" (`15a`, `15b`): The Verge, X post and Instagram cards with image banners, and a placeholder banner for example.com. The Verge card is y 224–523 (**300 pt**), 360 pt wide at x 21–380. The banner is 168 pt. The description clamps to 3 lines with an ellipsis. My own note with text directly adjacent to bare URLs (`16a`, `16b`, `data/Audit Link Cards.md`): each card is 300 pt, with a 12 pt gap to the text line above and a 20 pt gap to the text below, and no overlap, including a wrapped 3-line paragraph. **No reflow while loading:** `17a` (loading: host title + "Loading preview…" + placeholder) and `17b` (loaded) have identical row bands [159–176, 195–209, 224–523, 543–557, 572–871]. The accessibility tree shows the card as `Link` "W3C", frame 360x301 at (21,151) (`22-editor-w3c-card-tree.json`). **Digest:** the same card design, 300 pt tall (y 300–599): `07` (image card) and `18a` (placeholder card). |
| SC11: public Instagram post shows a real title, description and image | PASS | `15b`: "InstaAgent (YC P26) on Instagram", a Chinese description, the post image, and the instagram.com icon. To rule out a stale cache written by the implementer, I opened the same post as an uncached URL form (`https://instagram.com/p/Daw8hiys2w1/`, which has a different cache key). It went from "instagram.com / Loading preview…" to the full card within about 1.5 s (`19a` → `19b`, `19-instagram-fresh-fetch-strip.png`). The new cache entry has `schemaVersion 2` and `fetchedAt 2026-09-26T02:19:29Z` (`data/instagram-cache-entries.txt`). No social link was *shared*; the URL was only opened in the editor. |

## Defects

**Defect 1 — "Keep editing" sometimes opens Digest instead of the capture note on a cold launch (intermittent, 1 of 3 cold runs).**
Reproduction:
1. Boot the simulator fresh so Noto 2 is not running.
2. In Safari, share any page to Noto 2 and close it with the X, so one capture is staged.
3. Open another page, share it to Noto 2, and wait about 15 s with the sheet open.
4. Tap Keep editing.

Observed: Noto 2 opens on the Digest tab with the capture on top (`07`). The log shows two concurrent drains, each filing both captures (`created=true` twice per file), then `Shared capture <id> not filed this session; showing Digest`.
Expected: the editor opens on the capture note.

The same steps after a reboot opened the note correctly twice (`20b`, `21b`), and those runs also logged 2–3 concurrent drains per launch. So this looks like a race between the concurrent `drainSharedCaptures()` calls and the router's `requestedSharedCaptureID`, not a problem with the sheet. `Noto2/RootTabView.swift` is not in this diff, so this is probably an existing issue rather than a regression, but SC6 as written is not reliably met.

## Artifacts

All paths are relative to `/Users/eugenechan/dev/personal/Noto/.codex/evidence/20260926-015825-ios-visual-audit/`.
- Share sheet: `01`–`06b`, `08a`–`13c`, `20a`, `21a`; measurement overlay `04m-sheet-layout-measurements.png`; strips `03`, `06`, `11`, `12`.
- Keep editing: `07` (cold → Digest), `09` (warm → note), `20b` + `20-cold-launch-keep-editing-python-org.mov` (cold → note; the recorder only writes frames when the screen changes, so the timeline is compressed), `21b`.
- Inbox/filing: `14`, `data/inbox-final-listing.txt`, `data/*.md`, `data/pending-capture-apple-newsroom.json`.
- Link cards: `15a`, `15b`, `16a`, `16b`, `17*`, `18a`, `19*`, `22-editor-w3c-card-tree.json`; test notes `data/Audit *.md`.
- Logs: `data/log-excerpts-before-reboot.log` (verbatim; info logs do not survive a sim reboot), `data/noto2-and-extension.log` (after the last reboot).

## Commands

- `flowdeck config get --json` (the saved config points at Noto-iOS on another sim, so every command passed `-S` explicitly)
- `flowdeck simulator boot BA34BC0A-B394-456D-96CC-8F4E10E46F0E` (it was shut down); `flowdeck simulator shutdown/boot` twice more to force cold launches
- `flowdeck ui simulator session start/stop -S "BA34BC0A-…"`
- `flowdeck ui simulator screen -S "BA34BC0A-…" --output …` / `--tree --json`
- `flowdeck ui simulator tap -S "BA34BC0A-…" -p "x,y"` (coordinate taps; the extension's remote view has no accessibility tree, only "Safari")
- `flowdeck ui simulator swipe -S "BA34BC0A-…" --from … --to …`; `flowdeck ui simulator record -S "BA34BC0A-…" -t 30 -o …`
- As the caller directed: `xcrun simctl openurl BA34BC0A-… <url>`, `xcrun simctl spawn BA34BC0A-… log show …`, `xcrun simctl get_app_container …`

## Notes

- **Not verified:** (a) the X/Instagram "photos and videos will be added in a minute" message variant, because sharing social links is off limits; (b) the SC5 "Preview unavailable" fetch-failure path, which needs the network cut; (c) the macOS editor card (SC10 names macOS; this audit is iOS simulator only); (d) the media job itself.
- SC2: the content is centred inside the scroll region to 0.5 pt, but relative to the visible X and Keep editing edges it sits 5.5 pt high (34 pt gap above, 45 pt below), because the buttons' 12 pt top padding is outside the centred region. Worth a glance if the visual balance matters.
- Swipe-down was a synthetic drag. It did dismiss the sheet, and the log confirms `viewDidDisappear` ran ("sheet swiped away").
- Observation outside scope: capture notes' titles in Browse and the editor nav bar show raw markdown (`[W3C](https://www.w3.org/)`), because the note title comes from the first line. This is not part of this change.
- Observation: each cold launch runs 2–3 concurrent shared-capture drains that write the same file. The results were correct (no duplicates or lost captures), but it is the likely root of Defect 1.
- While auditing, one `flowdeck ui simulator --help` call with `-S` only inside a shell comment made the guard hook create and boot `cc-56c91326-ae194edc` (93988C97-0323-4595-AC6B-FA145795CACE). I shut it down right away and never used it. The session cleanup should delete it.
- Test notes `Audit Link Cards.md`, `Audit Loading Cards.md` and `Audit Instagram Card.md` were left at the simulator vault root. The 8 test captures are in the simulator's `inbox/`. This was simulator data only; the real vault was not touched.
