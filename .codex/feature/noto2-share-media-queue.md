# Feature: Share-sheet media capture via Cloudflare Queue + Hermes

## User Story

When I share an X or Instagram post to Noto 2, I want its images and videos — including a carousel, and the media inside a post it quotes — saved into the vault and added to that quick-capture note, without having to keep Noto 2 open or do anything else.

## User Flow

1. Share an X or Instagram post → Noto 2. The Link captured sheet appears as today; the link capture is staged as today.
2. For X / Instagram URLs, the extension also sends a **media job** to a Cloudflare Worker, which puts it on the Cloudflare Queue `noto-share-media`. If the send fails (offline), the job waits in the App Group outbox and Noto 2 re-sends it on its next activation.
3. **Hermes** (the always-on agent on the MacBook Pro) runs a script job every minute that pulls the queue, resolves the post, downloads every image/video into the vault's `.attachments/`, and acks the message.
4. As soon as the capture note exists in the iCloud vault (Noto 2 files it on activation — Keep editing does this immediately), Hermes appends the caption and media to it. iCloud syncs the result to every device.
5. In the editor the images render; a video renders as its first frame with a play badge (tap-to-play is a follow-up).

## Design decisions

- **Hermes never creates the note.** The phone is the only filer (`CaptureFilingService`). A second writer racing the phone at the same path would produce iCloud conflict copies. Hermes downloads immediately (Instagram CDN URLs expire) and parks the append until the note appears; it gives up after 7 days.
- **The job names the note path**, computed on the phone with the same function `CaptureFilingService` uses (moved to `NotoShareCapture.CaptureNotePath`). If the note has already left `inbox/` (Digest filed it) Hermes finds it by the post URL.
- **Idempotent**: re-running the append never duplicates media (checked by attachment filename); re-delivered queue messages reuse already-downloaded files.
- **Resolvers** (no login): X via `cdn.syndication.twimg.com/tweet-result` (quoted post included); Instagram via the public embed page's `contextJSON` (`GraphImage` / `GraphVideo` / `GraphSidecar`).

## Success Criteria

1. **SC1 — job shape and routing.** Only X status URLs and Instagram post/reel URLs produce a job; the job carries capture id, URL, note path (identical to `CaptureFilingService`'s), share time, title.
2. **SC2 — delivery from the phone.** The extension sends the job to the Worker; a failed send leaves it in the App Group outbox and the app re-sends it on activation; a successful send clears it.
3. **SC3 — Worker + queue.** The Worker accepts only a bearer-authenticated, well-formed job for an allowed host and enqueues it; anything else is rejected with 4xx and nothing is enqueued.
4. **SC4 — resolve.** X: text, author, all photos and the best MP4 of each video, plus the quoted post with its media. Instagram: caption, author, single image, single video, and every child of a carousel.
5. **SC5 — download + append.** Media lands in `.attachments/` with stable names; the note gets a block (`**@author**` + text, one `![](.attachments/…)` line per photo or video, then "Quoting **@author**" + its text and media); running again changes nothing.
6. **SC6 — deferred append.** A job whose note does not exist yet is downloaded and acked, then appended on a later run once the note appears; a note that already left `inbox/` is found by URL.
7. **SC7 — Hermes job.** A no-agent Hermes job runs every minute, is silent when idle, and reports failures.
8. **SC8 — rendering.** The capture note shows the images and a first-frame thumbnail for each video in the editor.
9. **SC9 — end to end.** Share an X post with video from the simulator → Worker → queue → Hermes CLI → note shows the media.

## Test Strategy

- SC1, SC2 (outbox + request building): `NotoShareCapture` package tests.
- SC4, SC5, SC6: `NotoSocialMedia` package tests with the recorded X/Instagram responses as fixtures, a fake HTTP client, temp-dir vaults.
- SC3: live `curl` checks against the deployed Worker (auth, validation, enqueue confirmed by pulling).
- SC7: live `hermes cron` run.
- SC8, SC9: simulator audit.

## Tests

### Package — `Packages/NotoShareCapture` (28 tests)
- `ShareMediaJobTests` — X/Instagram URL routing, other URLs rejected, note path shape + calendar, job fields, ISO JSON round trip, inbox-path validator (SC1)
- `ShareMediaDeliveryTests` — outbox-first delivery, failed send kept and flushed later, oldest-first flush, Info.plist endpoint parsing, authenticated request (SC2)

### Package — `Packages/NotoSocialMedia` (21 tests, fixtures = live responses recorded 2026-09-23)
- `ResolverTests` — X token matches JavaScript, status-id shapes, video post, quote post with quoted video, photo post, tombstone; Instagram shortcode shapes, real video embed, carousel, login wall; platform routing (SC4)
- `NoteAndProcessorTests` — stable file names + skip existing, exact markdown block, idempotent append, locate by path then by URL, park-until-note-appears, 7-day give-up, 10-minute restore window (SC5, SC6)
- `CloudflareQueueClientTests` — body normalisation, pull/ack payloads + auth, API errors (SC7)

### Worker — `web/noto-share-media-worker` (5 vitest tests)
- routing parity with the phone, job validation, handler guards (auth/method/JSON/validation → nothing enqueued), valid job enqueued with 202 (SC3)

### App — `Noto2Tests` 97/97 (no new app tests; the existing `CaptureFilingServiceTests` pin the path function now delegated to `CaptureNotePath`)

### Live
- Worker: health 200, no auth 401, bad job 400, valid job 202 and pulled back off the queue as JSON text (SC3)
- CLI `accept` against a scratch vault with Eugene's three posts: X video (7.4 MB), X quote post's video (4.5 MB), Instagram video (3.8 MB); rerun idempotent (SC4, SC5)
- Simulator E2E ×2: Safari → Share → Noto 2 → sheet shows "photos and videos will be added in a minute" → extension log `media job … accepted=true` → Keep editing files the note → `noto-share-media run` (Hermes' command, Hermes' credentials) against the simulator vault → note gains the block; open editor reloads live; video renders as first frame + play badge (SC2, SC8, SC9)

## Implementation Details

- **Phone** (`NotoShareCapture`): `CaptureNotePath` (the `inbox/<date>-<sha8>.md` rules, now also used by `CaptureFilingService`), `ShareMediaSource`, `ShareMediaJob`, `ShareMediaOutbox` (App Group `pending-media-jobs/`), `ShareMediaEndpoint` (Info.plist `NotoShareMediaEndpoint` / `NotoShareMediaToken`, the token from gitignored `Config/LocalSecrets.xcconfig` via `ReadwiseSecrets.xcconfig`), `ShareMediaDispatcher` (outbox-first `deliver`, `flush`).
- **Extension**: after staging the capture, `startMediaJob` delivers the job; `finish` waits ≤3 s for it. The Link captured sheet says photos and videos will follow.
- **App**: `RootTabView.drainSharedCaptures` flushes the outbox first. `NoteScreen` now reloads on `VaultFileWatcher` changes and on return to foreground (via `session.handleExternalChange`, which skips while local edits are unsaved) — previously Noto 2 never reloaded an open note from disk.
- **Editor**: `MarkdownImageLoader` renders `![](x.mp4|mov|m4v)` through `VideoPosterRenderer` (frame at 0.1 s + play badge). `invalidateImageLayouts` now lays the viewport out before placing overlays and schedules a full overlay refresh — an image loading under an open editor used to be placed from stale line frames and cover the lines above it.
- **Cloudflare**: Worker `noto-share-media-intake` on `cloudflare.eugenechantk.me/noto/*` (bearer secret `NOTO_SHARE_MEDIA_TOKEN`), queue `noto-share-media` (id `56e6d30818144590b341e5fbd1032ce4`) with an HTTP pull consumer (batch 10, 5 retries, visibility 600 s) and DLQ `noto-share-media-dlq`.
- **Mac** (`NotoSocialMedia` + `noto-share-media` CLI): resolvers, `MediaDownloader` (`.attachments/<platform>-<id>-<n>.<ext>`), `ShareMediaMarkdown` (author + text, media lines, "Quoting @author"; plain paragraphs because the editor has no blockquote styling), `CaptureNoteAppender` (coordinated write, idempotent), `ShareMediaProcessor` (park until the note exists, 7-day give-up, 10-minute restore window against autosave races), `CloudflareQueueClient`.
- **Hermes**: job `eebe2bfeae67` "Noto share media", every 1 min, no-agent, deliver local; script `~/.hermes/scripts/noto_share_media.sh` (stale-lock guard, credentials from `~/.hermes/workspaces/noto-share-media/.env` (0600), log `state/cron.log`, stdout only on failure) runs `Packages/NotoSocialMedia/.build/release/noto-share-media run` against `~/Library/Mobile Documents/com~apple~CloudDocs/Noto`. The Queues API token is the existing account token from the OpenClaw Linear setup.

## Evidence

- Independent audit **PASS**: `.codex/evidence/20260923-183726-ios-visual-audit/evidence.md` — sheet copy, `accepted=true` + empty outbox (×3), block appearing live in the open editor with the video thumbnail below the text, quote post via ✕ (deferred "Saved" then "Added" after foregrounding), Instagram caption + video, exact note markdown, idempotent reruns.
- After the audit: portrait-video fix verified on the simulator (thumbnail fits the reserved height, fully visible at the end of the note); `NotoTests/TextKit2MarkdownLayoutTests` 61/65 (the 4 known pre-existing failures), `Noto2Tests` 97/97, Noto-macOS compiles.
- Hermes live: job `eebe2bfeae67` resumed; first run 19:05 `ok`, silent, queue empty, nothing written to the real vault.

Success criteria: SC1 ✔ SC2 ✔ SC3 ✔ SC4 ✔ SC5 ✔ SC6 ✔ SC7 ✔ SC8 ✔ SC9 ✔

## Residual Risks

- **The phone needs a new build.** The TestFlight build on devices predates this; the extension only sends jobs from the next build.
- **Unofficial endpoints.** X's syndication endpoint and Instagram's embed page can change or throttle; a failure leaves the plain link capture (permanent errors are acked and logged, transient ones retried 5× then dead-lettered to `noto-share-media-dlq`).
- **Hermes availability.** Media only arrives while the MacBook Pro is awake, online and has the iCloud vault materialised; jobs wait in the queue (24 h retention) meanwhile.
- **Autosave race.** If you keep typing in the capture note across the moment Hermes appends, the editor skips the reload and its next autosave can drop the block; Hermes re-appends within its 10-minute window. After that window, removing the media is treated as your choice.
- **Not verified live:** an Instagram carousel (parser tested on a synthetic `GraphSidecar`), an X photo post (synthetic fixture), the offline outbox → re-send path (package-tested), tap-to-play (not built).
- **Emoji render as boxes on the slim simulator** (fonts stripped by simslim) — the files are correct.
- The share token ships inside the app's Info.plist; it only permits enqueueing validated X/Instagram jobs.

## Bugs

- **Stale overlay after an image loads under an open note** (found in the second E2E): `invalidateImageLayouts` placed image overlays immediately after invalidating layout, from stale line frames, so a video that finished loading under an open editor covered the lines above it. Fixed by laying out the viewport before placing and scheduling a full overlay refresh.
- **Portrait images overflow their line** (found by the audit, pre-existing): the iOS overlay was full-width × aspect while TextKit reserves a fixed 300 pt line, so portrait media drew past the end of the note (unscrollable) or over following text. Fixed with `ImageFragmentGeometry.overlaySize` (capped to the reserved height, width follows the aspect ratio) + test `imageOverlaySizeCapsPortraitImages`.
