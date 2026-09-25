# iOS Visual Evidence Audit

Verdict: PARTIAL
Timestamp: 2026-09-23 19:26–19:36 HKT
Repository: /Users/eugenechan/dev/personal/Noto
Simulator: cc-56c91326-ac386e88 (iPhone 17 Pro, iOS 26.3), UDID BBFC620B-6BB0-4435-8C86-582EE0E8EB14
App: com.eugenechan.Noto2 (scheme Noto2, Debug, Noto.xcodeproj)

## Change Audited

Noto 2 tap-to-play videos (`.codex/feature/noto2-video-tap-to-play.md`):
- Editor: a `![](.attachments/<file>.mp4)` line shows as a poster with a play badge. Tapping it presents a full-screen `AVPlayerViewController`. Long-pressing it moves the caret to the end of that line. Images do not respond to taps.
- Digest: media lines are lifted out of the card text into a row of up to 3 thumbnails, with "+N" when there are more. Tapping a video thumbnail plays it, and card swipes still work.

Test content, written into the simulator vault by the auditor:
- `Video Playback Test.md`: prose, a landscape video, prose, a PNG image, prose.
- `inbox/…0001.md`: link, prose and 1 landscape video. Created 10:10, so it is the front card.
- `inbox/…0002.md`: prose plus 5 media (3 videos, 2 PNGs).
- `inbox/…0003.md`: plain text.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| SC2: Tapping an editor video opens a full-screen player that plays the file | PASS | `01-editor-note-with-video-and-image.png` shows the poster and badge (a11y `editor_video_157`, "Play video"). Frames after tapping, in time order: `02-editor-player-t0.jpg` (19:27:30), `03-editor-player-t1.jpg` (19:27:48), `04-editor-player-controls-a.jpg` (19:28:01, controls up, 0:33 / -0:11, pause glyph showing so it is playing), `06-editor-player-endcard.jpg` (19:28:12, end card). The picture changes between every frame. |
| SC2: Done/close returns to the same note, unchanged | PASS | `07-editor-after-close.png` is the same note at the same scroll position. `shasum` before (`note-shasum-before.txt`) and after (`note-shasum-after-close.txt`) are both `8b9fc6d64ad1e61ffd22565a5cbea1a3e217a39a`. The file mtime is still 19:25:34. |
| SC3: Long-press on an editor video puts the caret at the end of that line | PASS | `08-editor-longpress-caret.png`: no player opened, the editor took focus (keyboard toolbar showing) and the caret sits on the video line. To prove the exact position I typed "Z": `09-note-on-disk-after-typing-Z.md` line 10 became `![](.attachments/x-2100295136261349802-1.mp4)Z`, and `09-editor-caret-probe-typed-Z.png` shows it. A Backspace brought the file back to hash `8b9fc6d…`. |
| SC3: Tapping an ordinary image opens no player and places the caret as before | PASS | `10-editor-tap-image-no-player.png` shows the caret on the image line and no player. `10-editor-tap-image-tree.json` has no a11y element for the image; only the video is a button. |
| SC4: Media lines are removed from the card text and shown as thumbnails | PASS (function) / FAIL (layout) | `11-digest-card-tree.json`: the card text is `'**@thaiscbranco_**\ncongrats quiver team!'`, with no `![](`. But the thumbnail is 330x185 at y=433 while the text runs y=415–453, so the thumbnail covers the second line, "congrats quiver team!" (`11-digest-card-video.png`, zoomed in `19-crop-single-video-overlaps-prose.png`). |
| SC4: At most 3 thumbnails, "+N" on the third | PASS (function) / FAIL (layout) | `17-digest-after-snooze-plus2.png` shows 5 media as 3 thumbnails with "+2" on the third. The portrait video thumbnails are 97x172 at y=323, not the 120 pt strip height (the image is 120x120 at y=350). They reach 27 pt above and 25 pt below the strip and cover the second prose line, "videos and two images." (`18-crop-plus2-strip-overlaps-prose.png`, `17-digest-after-snooze-tree.json`). |
| SC4: Tapping a Digest video thumbnail plays it; dismissing returns to the card | PASS | `12-digest-player-t0.jpg` (19:34:34), `13-digest-player-t1.jpg` (19:34:44) and `14-digest-player-t2.jpg` show different frames. After closing, the same card is back and it still says "3 to process". Tapping the image thumbnail opened no player (`20-digest-tap-image-no-player.png`). |
| SC4: Left swipe that starts on a thumbnail snoozes the card | PASS | `15-digest-before-swipe.png` says "3 to process". The swipe went from (300,525), on the thumbnail, to (20,530). `16-digest-swipe-outcome.jpg` shows the yellow "Snooze" overlay mid-flight. `17-digest-after-snooze-plus2.png` says "2 to process" with the next card showing. On disk, `16-snoozed-capture-on-disk.md` now has `snoozed_until: 2026-09-30T11:35:15Z`. |
| SC5: A video that is not downloaded starts a download instead of opening a player | NOT VERIFIED | The simulator vault is a local container, so every file counts as downloaded. There is no dataless iCloud placeholder to tap. |

## Artifacts

All paths are relative to `/Users/eugenechan/dev/personal/Noto/.codex/evidence/20260923-192600-ios-visual-audit/`:
- Editor: `01-editor-note-with-video-and-image.png`, `01-editor-tree.json`, `02-…t0.jpg`, `03-…t1.jpg`, `04-…controls-a.jpg`, `05-…controls-b.jpg`, `06-…endcard.jpg`, `07-editor-after-close.png`/`.json`, `08-editor-longpress-caret.png`, `08-editor-longpress-tree.json`, `09-editor-caret-probe-typed-Z.png`, `09-note-on-disk-after-typing-Z.md`, `10-editor-tap-image-no-player.png`, `10-editor-tap-image-tree.json`, `note-shasum-before.txt`, `note-shasum-after-close.txt`.
- Digest: `11-digest-card-video.png`, `11-digest-card-tree.json`, `12-…t0.jpg`, `13-…t1.jpg`, `14-…t2.jpg`, `15-digest-before-swipe.png`, `16-digest-swipe-outcome.jpg`, `16-snoozed-capture-on-disk.md`, `17-digest-after-snooze-plus2.png`, `17-digest-after-snooze-tree.json`, `18-crop-plus2-strip-overlaps-prose.png`, `19-crop-single-video-overlaps-prose.png`, `20-digest-tap-image-no-player.png`.

## Commands

- `flowdeck config get --json`. The saved config is Noto-iOS on the shared sim, so the guard's session sim was used instead.
- `flowdeck run -s Noto2 -S "BBFC620B-6BB0-4435-8C86-582EE0E8EB14" --json`
- `.maestro/seed-vault.sh BBFC620B-6BB0-4435-8C86-582EE0E8EB14 --bundle-id com.eugenechan.Noto2`
- `flowdeck ui simulator open-url "noto2://capture" -S "…"`, then tapped "Open"
- `flowdeck ui simulator session start -S "…" --json`, restarted twice
- `flowdeck ui simulator tap "editor_video_157" --by-id -S "…"` (tap to play)
- `flowdeck ui simulator tap "editor_video_157" --by-id -d 0.8 -S "…"` (long-press)
- `flowdeck ui simulator type "Z"` and `flowdeck ui simulator key 42` (caret probe, then Backspace)
- `flowdeck ui simulator tap -p "160,740"` (tap the image), `flowdeck ui simulator tap "Play video"` (Digest)
- `flowdeck ui simulator swipe --from "300,525" --to "20,530" --duration 0.35 -S "…"`
- `flowdeck ui simulator screen -o <file>.png -S "…" --json`

## Notes

- **Digest layout defect (the reason for PARTIAL):** `DigestMediaThumbnail` uses `Image.resizable().scaledToFill()` inside a ZStack with `.frame(maxWidth: .infinity, maxHeight: .infinity)`. The thumbnail takes the image's aspect-fill size, and the strip's `.frame(height: 120)` does not clip it. The result is 185 pt tall for a single landscape video and 172 pt for portrait videos in a 3-up row. The thumbnails run about 25–33 pt above the strip and cover the last prose line of the card. Widths are also uneven (97 / 120 / 97). A likely fix is to give each tile a fixed size, e.g. `Color.clear.frame(height: 120).overlay { image.scaledToFill() }.clipped()`, so the image cannot drive the layout. I made no code change.
- **A11y identifiers:** the thumbnail tiles report `id = digestMediaStrip`, not `digestVideoThumbnail_<i>` / `digestImageThumbnail_<i>`. The container's `.accessibilityIdentifier("digestMediaStrip")` on the HStack overrides the children's identifiers because there is no `.accessibilityElement(children: .contain)`. The labels "Play video" and "Image" are correct. This matters to UI tests that target the per-thumbnail ids.
- **Not part of this change:** the card prose shows raw `**@thaiscbranco_**` asterisks, because the Digest `Text` does not render markdown. The old `Text(entry.body)` behaved the same way.
- **Tooling:** while `AVPlayerViewController` is on screen, `flowdeck ui simulator screen` fails with "Failed to parse accessibility tree", and the session ring skips frames whenever the player controls are showing. The player frames are copies of the session's `latest.jpg`. As a result `04` and `05` are the same frame, captured during a 3.5 s ring stall. I could not get two time-label readings. Playback is shown instead by the frames changing over 19:27:30 → 19:28:12, plus the 0:33 time and pause glyph in `04`.
- **Swipe:** a synthetic idb swipe triggered the snooze. That proves the drag gesture works when it starts on a thumbnail; the thumbnail's tap recogniser did not take the drag.
- **SC5** is not verified in the simulator; it needs a device or Mac with a dataless iCloud file.
- The sim has no software keyboard showing (hardware keyboard setting). Focus is shown by the input-accessory toolbar and caret.
