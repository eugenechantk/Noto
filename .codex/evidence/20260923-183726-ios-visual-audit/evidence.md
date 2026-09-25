# iOS Visual Evidence Audit

Verdict: PASS (all requested criteria met; one defect found in the same build, not attributed to this change, see Notes 1)
Timestamp: 2026-09-23 18:37–18:50 HKT
Repository: /Users/eugenechan/dev/personal/Noto (main, dirty working tree)
Simulator: cc-56c91326-ad618c5b, iPhone 17 Pro, iOS 26.3, UDID CAD9EFE5-2CE7-4EEE-A2EA-8230DE08B35F (per-agent, slim)
App: com.eugenechan.Noto2 (scheme Noto2, Debug) + Noto2ShareExtension (com.eugenechan.Noto2.ShareExtension)

## Change Audited

Feature doc `.codex/feature/noto2-share-media-queue.md`. When you share an X or Instagram post, the extension now sends a media job to the Worker (`cloudflare.eugenechantk.me/noto/share-media`), which puts it on the queue `noto-share-media`. The `noto-share-media run` CLI downloads the post's media into `.attachments/` and appends a block to the capture note. The Link captured sheet shows a new status line. `![](x.mp4)` renders as the video's first frame with a play badge. Noto 2's open note reloads when the file changes on disk. The editor no longer places a newly loaded image on top of the lines above it.

For this audit I stood in for Hermes: I ran `Packages/NotoSocialMedia/.build/release/noto-share-media run` (built 18:33, no newer sources) against **the simulator's vault only**. It used Hermes' credentials from `~/.hermes/workspaces/noto-share-media/.env`, and its state dir was a scratch dir. The Hermes job `eebe2bfeae67` stayed paused. The iCloud vault was never touched.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| SC2/SC8 sheet: sharing the X video post shows "Saved to your inbox. Its photos and videos will be added in a minute." | PASS | `01-x-video-share-sheet.png` (same line for the quote post `12-…` and Instagram `20-…`) |
| SC2 delivery: extension logs `media job … accepted=true` | PASS | `02-x-video-extension-log.txt` (A06643FD, 18:38:39), `14-x-quote-extension-log.txt` (20905274), `22-instagram-extension-log.txt` (4E8FBF8A) |
| SC2 delivery: App Group `pending-media-jobs/` is empty afterwards | PASS | `02-x-video-outbox.txt`, `14-x-quote-outbox.txt`, `22-instagram-outbox.txt` (all empty) |
| SC9 Keep editing: Keep editing files the note and opens it in the editor | PASS | `03-x-video-note-open-before-cli.png`; the file `inbox/2026-09-23-e3ad907c.md` existed before the CLI ran |
| SC9 CLI appends the block to the open note | PASS | `04-x-video-cli-run.txt`: "Saved 1 video …" + "Added media to inbox/2026-09-23-e3ad907c.md" |
| Live reload: the block appears in the open editor without leaving the note | PASS | `05-x-video-live-reload-5s.png` (5 s after the CLI exited), `06-x-video-live-reload-15s.png` (15 s, identical) |
| Overlay fix: the video thumbnail (first frame + play badge) sits below the text lines, not on top of them | PASS | `05`/`06`: `**@jacobrodri_**` at y≈318, text at y≈355, thumbnail starts at y≈430 with the play badge centred |
| Scroll once, nothing jumps | PASS | `07`/`07b`/`08` (live-reloaded note) and `10`/`11` (reopened note): the text and thumbnail move together and nothing overlaps. See Notes 1 for the scroll range |
| SC9 quote post + ✕: first CLI run reports "Saved 1 video" but not "Added media" | PASS | `13-x-quote-after-close.png` (Safari foreground), `15-x-quote-cli-run1-deferred.txt` (pending capture still staged, no inbox note, video already in `.attachments/`) |
| SC9 quote post: after Noto 2 comes to the foreground, the second run reports "Added media to inbox/…md" | PASS | `16-x-quote-cli-run2-appended.txt`: "Added media to inbox/2026-09-23-be44e062.md" |
| The quote note, opened from Browse → inbox, shows the text, "Quoting **@QuiverAI**" + its text, and the QuiverAI video thumbnail | PASS | `17-browse-inbox-list.png`, `18-x-quote-note-open.png`, `19-x-quote-note-scrolled.png` (the whole landscape frame + play badge) |
| Instagram (Keep editing): CLI appends the caption and video; the note shows both | PASS | `21-…-before-cli.png`, `23-instagram-cli-run.txt`, `24`/`25-instagram-live-reload-*.png` (caption live-reloaded), `26`/`27` (video thumbnail + play badge) |
| Exact markdown of each resulting note | Recorded | `30-final-note-contents.txt` (reproduced below) |
| Idempotency, seen incidentally | PASS | The X video job stayed in the CLI's `pending-appends/` (10-minute restore window) through three later runs. `e3ad907c.md` is still 366 bytes, its mtime is still 18:40, and there is no duplicate block |

## Resulting notes (verbatim)

`inbox/2026-09-23-e3ad907c.md` (X video, Keep editing)
```
---
id: 928CD8F9-8389-49E1-8324-3A2C90E036E2
created: 2026-09-23T10:38:36Z
updated: 2026-09-23T10:38:36Z
type: note
status: inbox
---

[Jacob Rodri on X: "I can see a potential $100k/month app here" / X](https://x.com/jacobrodri_/status/2102386784814735508)

**@jacobrodri_**
I can see a potential $100k/month app here

![](.attachments/x-2102386784814735508-1.mp4)
```

`inbox/2026-09-23-be44e062.md` (X quote post, ✕ then foreground)
```
---
id: 84BF98BF-63FA-411A-95A2-D86F9C0B7A0D
created: 2026-09-23T10:44:11Z
updated: 2026-09-23T10:44:11Z
type: note
status: inbox
---

[Thais Castello Branco on X: "congrats quiver team! this is awesome" / X](https://x.com/thaiscbranco_/status/2100400751357083664)

**@thaiscbranco_**
congrats quiver team! this is awesome

Quoting **@QuiverAI**
Introducing Arrow 2

Our latest and most advanced models for generating precise, editable vector graphics.

Higher quality. Faster outputs. Available now in App and API.

![](.attachments/x-2100295136261349802-1.mp4)
```

`inbox/2026-09-23-e0009e4a.md` (Instagram, Keep editing)
```
---
id: ED12AF22-5792-463A-81A0-A442A2F0D795
created: 2026-09-23T10:46:45Z
updated: 2026-09-23T10:46:45Z
type: note
status: inbox
---

[Instagram](https://www.instagram.com/p/Daw8hiys2w1/)

**@instaagent.ai**
拍廣告片唔一定要貴！
立即 Whatsapp：http://wa.me/85261612623

拍一條 Studio 級數嘅廣告片，其實唔駛幾萬蚊。 我哋幫你慳返大量製作費：
✅ 唔駛租場、租器材
✅ 唔駛請 Crew、請 Model
✅ 唔駛等幾星期後期製作

InstaAgent 結合「AI 生成」與「專業團隊監修」，用最抵價錢，做最 High-End 效果。

精明老闆之選 💡 
立即 WhatsApp 我哋睇成功案例！👇

![](.attachments/instagram-Daw8hiys2w1-1.mp4)
```

`.attachments/`: `x-2102386784814735508-1.mp4` (7,411,259 B), `x-2100295136261349802-1.mp4` (4,455,756 B), `instagram-Daw8hiys2w1-1.mp4` (3,804,815 B). The file `audit-control-portrait.png` is my control file (Notes 1).

## Artifacts

All in `/Users/eugenechan/dev/personal/Noto/.codex/evidence/20260923-183726-ios-visual-audit/`:
- X video: `01`–`11` (sheet, log, outbox, open note, CLI output, live reload at 5 s and 15 s, scroll, reopen)
- X quote: `12`–`19` (sheet, after ✕, log, outbox, deferred run, appended run, Browse inbox, note)
- Instagram: `20`–`27`
- Controls: `28-control-browse-emoji-missing-glyph.png`, `29-control-portrait-png-scroll-max.png`
- `30-final-note-contents.txt` (markdown, sizes, md5s, CLI state dir listing)

## Commands

- `flowdeck config get --json` (saved config targets the shared iPhone 17; the guard hook overrode it with the per-agent sim)
- `flowdeck run -s Noto2 -S "CAD9EFE5-2CE7-4EEE-A2EA-8230DE08B35F" --json` (BUILD succeeded, app pid 77298)
- `.maestro/seed-vault.sh CAD9EFE5-… --bundle-id com.eugenechan.Noto2`
- `flowdeck ui simulator session start -S "CAD9EFE5-…" --json`, `open-url` (noto2://capture and the three post URLs), `tap -p`, `scroll`, `swipe`, `screen -o`, `screen --tree --json`
- `xcrun simctl spawn … log show --predicate 'subsystem == "com.eugenechan.Noto2.ShareExtension"'` and `xcrun simctl get_app_container … data|groups`. These are read-only and were run because the caller explicitly asked for them. FlowDeck has no equivalent for extension-process logs or App Group paths
- `noto-share-media run --vault <sim vault> --state-dir <scratch>`, four runs through a wrapper that refuses to run on any vault outside this simulator. The token was never printed, and I grepped the evidence to confirm it is not present

## Notes

1. **Defect: a tall image at the end of a note cannot be scrolled fully into view.** Both portrait posters (X 9:16 `08`/`11`, Instagram `27`) run off the bottom of the screen, about 200 pt of the frame and the trailing line cannot be reached, and scrolling stops after 4–18 pt. The landscape QuiverAI poster (`19`) is fully visible.
   - **Control in the same build:** a plain portrait PNG at the end of a note clips the same way (`29-control-portrait-png-scroll-max.png`). So the bug is not video-specific and not caused by the overlay fix.
   - **Origin not established:** I did not check whether it predates this change, because that needs a baseline build and I may not touch source.
   - **Unconfirmed hypothesis:** `ImageLayoutFragment` makes the frame taller to match the image's aspect ratio. The paragraph style still fixes the line height at `imagePreviewReservedHeight = 300` (TextKit2EditorView.swift:800, 962). The scrollable content height may be following that 300 pt line rather than the taller frame.
   - **Why it matters:** X and Instagram videos are mostly portrait and the media block is always last in the note, so most shared videos will show this.
2. **Emoji render as a "?" box on this simulator.** This affects the Instagram caption (✅ 💡 👇), and the same glyphs also fail in the SwiftUI Browse list (`28`). It is most likely the slim simulator's font services, not Noto. The markdown on disk has the correct code points (U+2705, U+1F4A1, U+1F447).
3. **The status line is proven by screenshot only.** The accessibility tree can't see inside the extension's remote view (`01-…-tree.json` shows only "Safari"), so I could not check the `linkCapturedStatus` identifier.
4. **Not checked in the simulator:** the offline path of SC2 (a failed send stays in the outbox and Noto 2 re-sends it on activation). The `ShareMediaDeliveryTests` package tests cover it. I did not do an extra idempotency run, to avoid pulling the shared queue without a fresh share of my own.
5. **Taps used coordinates.** They were checked against screenshots before each tap, except "Open", which was tapped by label. I captured no video; recording is broken on this Mac.
6. **Leftovers:** the simulator vault holds my control note `Audit Control.md` and `.attachments/audit-control-portrait.png`. The CLI state dir `/private/tmp/claude-501/…/scratchpad/state/pending-appends/` still holds the three job records, which expire after 10 minutes.
