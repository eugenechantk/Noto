# Feature: Tap to play videos (Noto 2)

## User Story

When a note contains a video — typically one Hermes added from a shared X / Instagram post, written as `![](.attachments/<file>.mp4)` — I want to tap its thumbnail and watch it, in the editor and on the Digest card, instead of only seeing a still frame.

## User Flow

1. **Editor**: a video line shows its first frame with a play badge. Tap it → the video plays **inline, in place of the thumbnail**, with the native iOS inline controls (play/pause, ±10 s, scrubber, mute, AirPlay, speed, full screen). The full-screen button opens the native full-screen player; closing it puts the video back on its line. Scrolling the video off screen, starting another video, or leaving the note stops it. *(First version, build 202609232143: tap opened full screen directly.)*
2. Long-press the thumbnail → the caret moves to that line, so the markdown can be edited or deleted (same as link cards).
3. **Digest**: a capture's media lines no longer show as raw `![](…)` text. The card shows the text, then a row of up to three thumbnails (videos with a play badge, "+N" when there are more). Tap a video thumbnail → the same full-screen player. Swipes on the card keep working.
4. A video still downloading from iCloud does not open a broken player: the tap starts the download and nothing else happens.

## Success Criteria

1. **SC1** — Only local video files (`.mp4`, `.mov`, `.m4v`, any case) are playable targets; images and remote URLs are not.
2. **SC2** — Tapping an editor video thumbnail presents a full-screen player that is playing that file; Done dismisses it and the note is unchanged.
3. **SC3** — Long-pressing an editor video thumbnail puts the caret at the end of that line; tapping an ordinary image still places the caret as before (images stay non-interactive).
4. **SC4** — Digest: media lines are removed from the card text and shown as thumbnails (max 3 + "+N"); tapping a video thumbnail plays it; the card's swipe gestures still work.
5. **SC5** — A video that is not downloaded yet triggers a download instead of a player.
6. **SC6** — Existing editor, Digest and share tests keep passing.
7. **SC7** — Inline: tapping an editor video plays it inside the note at the thumbnail's frame with native inline controls; it moves with its line as the note scrolls.
8. **SC8** — The inline player's full-screen button opens the native full-screen player on the same playback (same position, keeps playing); closing full screen returns it to its line.
9. **SC9** — Only one video plays at a time; starting another stops the first (which shows its thumbnail again); scrolling it off screen or leaving the note stops it.
10. **SC10** — Every editor video fills the editor's content width. A portrait video keeps the capped height (the line TextKit reserves) with the picture centred on black, and the inline player fills that same box. Images keep their own sizing.

## Test Strategy

- SC1: unit tests on `VideoPosterRenderer.playableVideoURL(for:)`.
- SC4 (parsing): unit tests on `DigestMediaSplit` (media lines out, order kept, video flagged, text tidied, remote images left as text).
- SC7–SC9 (state rules): unit tests on `InlineVideoPlayer` with a host view controller.
- SC2, SC3, SC4 (interaction), SC5, SC7–SC9: simulator audit — player UI visible with the time advancing between two screenshots; caret position after long-press; swipe from a thumbnail.

## Tests

### App Unit — `Noto2Tests/VideoTapToPlayTests.swift`
- `onlyLocalVideoFilesArePlayable` — SC1
- `mediaLinesLeaveTheCardTextInOrder` — SC4
- `quotedAndListedMediaLinesAreMediaToo` — SC4
- `remoteImagesAndInlineLinksStayText` — SC4
- `mediaOnlyTextLeavesNoProse` — SC4
- `cardTextRendersInlineMarkdownAndKeepsLineBreaks` — SC4 (added after the first audit)

### App Unit — `NotoTests/TextKit2MarkdownLayoutTests.swift`
- `imageOverlaySizeCapsPortraitImages` — portrait images shrink to the reserved height, keeping their shape
- `videoOverlaySizeFillsWidth` — SC10 (portrait video: full width × capped height; landscape unchanged)
- `viewportLinesIncludeTheProbedMediaLine` — SC10 (a media line at either viewport edge is included in the overlay refresh)
- `cappedFragmentHeightMatchesOverlay` — SC10 (the line reserves exactly the overlay's height + padding; short images unaffected)

`TextKit2MarkdownLayoutTests`: all pass except the 4 known pre-existing failures (wiki-link styling/reveal, hyperlink reveal on delete, divider reveal).

### App Unit — `Noto2Tests/InlineVideoPlayerTests.swift`
- `playEmbedsNativePlayerOverTheThumbnail` — SC7 (child `AVPlayerViewController`, view at the thumbnail frame, native controls on)
- `followMovesThePlayerAndStopRemovesIt` — SC7, SC9
- `startingAnotherVideoReplacesTheFirst` — SC9
- `fullScreenPlayerIsNeitherMovedNorStopped` — SC8

Full suite: `Noto2Tests` 106/106 reported, 0 failures (FlowDeck's report omits the async `DigestModelTests/filingRequestsSearchIndexUpdates`, which passes alone). Noto (iOS) and Noto-macOS (compile-only, signing off) build.

## Implementation Details

- `VideoPosterRenderer.playableVideoURL(for:)` — local `.mp4/.mov/.m4v` only (SC1).
- `NotoShared/Editor/VideoPlayback.swift` (iOS): `prepare` (starts an iCloud download and refuses when the file is a placeholder; sets the `.playback` audio session so sound plays on silent), `makeController` (`AVPlayerViewController`), `present(_:from:)` for UIKit, and `VideoPlayerScreen` for SwiftUI `.fullScreenCover`.
- `NotoShared/Editor/MediaOverlayImageView.swift` (iOS): the editor's image overlay subclass. `configureVideo(_:location:)` makes it a button (tap → `onPlay`, long-press → `onEdit`) only for videos; images keep `isUserInteractionEnabled = false`. `TextKit2EditorViewController.refreshImageOverlayViews` wires `onPlay` to `VideoPlayback.present` and `onEdit` to `placeCaret(atEndOfLine:)` — the link card's pattern.
- `Noto2/Digest/DigestMedia.swift`: `DigestMediaSplit` (uses the editor's `MarkdownImageLinkParser` + `MarkdownBlockMarker`, so card and editor agree), `DigestMediaStrip` (fixed row of ≤3 thumbnails with "+N" — not a horizontal scroller, which would steal the card's swipes), `DigestThumbnailLoader` (cached `preparingThumbnail` / video poster). `DigestScreen.cardText` renders prose + strip; `.fullScreenCover(item: $playingVideo)` shows `VideoPlayerScreen`.
- **Inline** (`NotoShared/Editor/InlineVideoPlayer.swift`, iOS): embeds one native `AVPlayerViewController` as a child of the editor controller, its view added to the text view at the thumbnail's frame (above it). `play` replaces any current player; `follow(frame:)` is called on every overlay refresh (`followInlineVideo` finds the thumbnail with the same URL; off screen → `stop`). The full-screen delegate callbacks set `isFullScreen`, and `follow`/`stop` do nothing while it is set. `onPlay` now calls `inlineVideo.play` instead of presenting full screen.
- **Line height = box height** (SC10): `ImageLayoutFragment` sizes an image line from its aspect ratio (`aspectAdjustedFragmentHeight`), which had no cap, while the iOS overlay is capped at `MarkdownVisualSpec.imagePreviewMaxImageHeight` (284 pt). On iOS the line height now uses the same cap. macOS draws inside the fragment and stays uncapped.
- **Full width** (SC10): `ImageFragmentGeometry.overlaySize(…, fillsWidth:)` keeps the full content width for videos when the height is capped; `imageOverlayRect` passes `fillsWidth` for playable videos. `MediaOverlayImageView.configureVideo` gives videos a black backdrop (aspect-fit poster centred on it). The inline player follows the thumbnail frame, so it fills the same box.
- The editor stops the inline player in **`viewDidDisappear`, not `viewWillDisappear`**: entering the player's own full screen makes the editor "disappear", and `viewWillDisappear` fires before AVKit's `willBeginFullScreenPresentation` callback, so stopping there removed the controller mid-transition ("AVPlayerViewController was deallocated while its contents were being presented full screen") and full screen fell back to the poster. By `viewDidDisappear` the flag is set.
- macOS is out of scope: it draws images inside the text view (no overlays), so there is nothing to tap yet.

## Evidence

- First audit PARTIAL: `.codex/evidence/20260923-192600-ios-visual-audit/evidence.md` (SC2, SC3 pass; Digest layout bug — see Bugs).
- Re-audit **PASS**: `.codex/evidence/20260923-194126-ios-visual-audit/evidence.md` — 5-media card (full prose, three 104×120 tiles, "+2"), per-tile a11y ids, bold author, Digest play/close for landscape and portrait, image tile inert, left swipe from a tile snoozes, editor tap-to-play with the note unchanged.
- After the re-audit: media row pinned outside the scrolling text + soft bottom fade (the auditor's layout note: long posts pushed tiles below the card edge). Verified on the simulator with a link + 3 paragraphs + 5 media capture: tiles fully inside the card at y 493–613, portrait tile plays. `Noto2Tests` 103/103.

Success criteria (full-screen version): SC1 ✔ SC2 ✔ SC3 ✔ SC4 ✔ SC5 — not verifiable in the simulator (files are always local) ✔ SC6 ✔

### Inline (2026-09-23)
- Self-check on the simulator: tap → plays inline with native controls; full-screen button → native full screen, playing (frame advances), no AVKit dealloc warning; ✕ → back on its line, resumes at 0:35; scrolling keeps it on its line; tapping the second (portrait) video stops the first (poster returns) and plays the second at its capped size; back → rate 0, no audio queued afterwards. One pause in full screen was traced to the simulator's CoreAudio device rebuilding (`RebuildIOContext`, `StartIO` failed), not app code.
- Full width (after Eugene's request "The video should fill the width of the editor space"): portrait Instagram video now spans the same width as the landscape X video above it, black side bars, plays inline in the same box; tapping a side bar plays it. Screenshots: `.codex/evidence/20260923-video-full-width/`.
- Independent audit 1 **PARTIAL**: `.codex/evidence/20260923-144704-ios-visual-audit/evidence.md`. SC7, SC8, SC9, SC3 PASS; SC10 width PASS, but a ~379 pt empty band below a portrait video followed by text (D1). No AVKit dealloc warning in 13,456 log lines.
- After the D1 fix: the line below the portrait video sits the same distance below it as the line below the landscape video; a note ending on a portrait video still scrolls to show the whole box (`.codex/evidence/20260923-video-full-width/3-no-gap-below-portrait.jpg`). `TextKit2MarkdownLayoutTests` all pass except the 4 pre-existing failures; Noto-macOS compiles.
- Independent re-audit (layout) **PARTIAL**: `.codex/evidence/20260923-152557-ios-visual-audit/evidence.md`. SC10a–e PASS (all media x 21–380; gaps below 10/5 pt, above 29 pt; last-line portrait fully scrollable; plays in its box; identical after reopen). New defect D2: a video whose top was within ~160 pt of the screen bottom was not drawn.
- After the D2 fix: "Thais on X" opened unscrolled draws the portrait video at the bottom edge (`.codex/evidence/20260923-video-full-width/4-video-drawn-at-screen-bottom.jpg`). `Noto2Tests` 106/106.

## Residual Risks

- **SC5 unverified**: tapping a video that is still an iCloud placeholder should start the download and not open a player; the simulator can't produce a placeholder. Needs a device check.
- **Long text on a Digest card scrolls behind a fade** above the pinned media; a short, slow synthetic drag did not scroll it in the audit, a longer one did — check with a real finger.
- **macOS**: no tap-to-play (images are drawn in the text view there, not as overlays).
- Needs a new TestFlight build to reach the phone (202609232143 has full-screen tap-to-play only).
- **✕ in full screen pauses** (audit note O1): native AVKit behaviour; the video returns to its line paused. Not changed.
- **Long-press caret on a media line** is as tall as the line (300 pt), pre-existing and cosmetic (audit note O2).
- **Picture in picture from inline** is enabled but not exercised; the simulator can't show PiP reliably.
- **Editing while a video plays**: typing reflows lines; the player follows via the overlay refresh, but a long edit session with a playing video is untested.

## Bugs

- **D2: video missing near the bottom of the screen** (re-audit): `visibleTextRange` probes `closestPosition(to:)` 120 pt past each viewport edge; inside a tall media line that returns the line's start, and the half-open range dropped the line, so its overlay was never placed. Fixed with `EditorViewportLines.lineRange`, which includes the lines at both probes plus one beyond each. The same path serves todo markers, dividers and link cards.
- **D1: empty band below a portrait video** (audit 1): the line reserved the uncapped aspect height (656 pt at 360 pt wide) under a 284 pt box. Fixed by capping the fragment height on iOS (see Implementation Details). The same mismatch would have left gaps under tall images on iPad.
- **Inline → full screen tore the player down** (found while building inline): see Implementation Details — `viewWillDisappear` stop moved to `viewDidDisappear`.

- **First audit PARTIAL** (`.codex/evidence/20260923-192600-ios-visual-audit/`): Digest thumbnails grew to the image's aspect ratio past the 120 pt row and hid the card's last text line (`scaledToFill` inside a `maxHeight: .infinity` frame); the row's accessibility identifier replaced the per-thumbnail ones; the card showed `**@author**` literally. Fixed: fixed-size tile with the image as a clipped overlay, `.accessibilityElement(children: .contain)` on the row, inline-markdown `AttributedString` for card prose.
