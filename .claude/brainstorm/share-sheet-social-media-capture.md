# Share sheet → capture the media inside X / Instagram posts

2026-09-23. Question from Eugene: can sharing an Instagram or X post to Noto 2 also save its images, video, carousel, including media inside a quoted post?

## Answer: yes, without logging in, through two unofficial endpoints

Probed live on 2026-09-23 with the three posts Eugene sent (raw responses in the session scratchpad `media-probe/`).

| Post | Endpoint | What came back |
|---|---|---|
| X `jacobrodri_/2102386784814735508` | `cdn.syndication.twimg.com/tweet-result?id=<id>&token=<t>` | text + 1 video; highest-bitrate MP4 (720x1280, 7.4 MB) downloads with HTTP 200 |
| X `thaiscbranco_/2100400751357083664` (quotes another post) | same | text + `quoted_tweet` with its own video (1280x720); quoted media comes in the same response |
| Instagram `p/Daw8hiys2w1` | `instagram.com/p/<code>/embed/captioned/` → `contextJSON.gql_data.shortcode_media` | author, full caption, `GraphVideo` with `video_url` (3.8 MB MP4, HTTP 200) + poster image |

- X token: `((id / 1e15) * π).toString(36)` with zeros and the dot stripped. No auth, no cookies.
- Instagram carousels arrive as `GraphSidecar` with `edge_sidecar_to_children[].node` entries, each an image or a video. The shape is standard, but I did not test a live carousel.
- The share sheet itself only hands Noto a URL (plus text for X). The media has to be fetched from the network. Nothing comes from the share payload.

## Constraints that shape the design

- **Unofficial and fragile.** Both endpoints are undocumented and have changed before. Instagram also rate-limits by IP and serves login walls to some networks. Failure must degrade to today's behaviour: a link card.
- **Instagram media URLs are signed and expire** (`oe=` parameter). Resolve and download close to the moment of saving; never store the CDN URL.
- **Share extensions have tight memory and time limits.** Downloading a 10 MB video there is fragile.
- **The editor cannot show video yet.** Images render through `![](path)` image links; there is no video block. `NotoVault.AttachmentStore` already writes files into the vault's `.attachments/`.
- **Storage.** Videos are 4–10 MB each and live in iCloud Drive with the vault.
- **Terms of service.** Both platforms prohibit downloading content outside their apps. For a personal archive this is low risk, but it is a real policy exposure if Noto 2 ever ships publicly.

## Recommended design

1. **Extension unchanged.** It keeps staging the URL and showing Link captured.
2. **New package `NotoSocialMedia`** (Foundation only): `SocialPostResolver.resolve(url)` returns `SocialPost { author, text, media[image|video + poster], quoted: SocialPost? }` for `x.com`/`twitter.com` status URLs and Instagram `/p/` and `/reel/` URLs. Unit-tested against the recorded responses above as fixtures.
3. **Resolve and download in the app, during the drain** that already files share captures. That keeps downloads out of the extension and fetches fresh Instagram URLs. Files go through `AttachmentStore` into `.attachments/`.
4. **Capture body** becomes the link card line, then the caption as a quote, then one `![](.attachments/…)` line per media item, then the quoted post's text and media under it. Everything stays plain markdown in the vault.
5. **Editor and Digest render video**: a poster frame with a play button that plays inline, and consecutive media lines laid out as a grid or swipeable carousel. This is the largest piece of new UI work.
6. **Failure fallback:** any resolve or download error files the plain link capture, exactly as today.

Optional later: a Mac-side `yt-dlp` worker (already installed, used by the `ig-download` skill) as a sturdier fallback when an endpoint breaks. It only helps while the Mac is on.

## Rough size

- Package + resolver + drain integration + tests: small to medium.
- Video block + media grid in the TextKit 2 editor and Digest: medium to large; this is where the time goes.
- Could ship in two steps: media saved + images rendering first, video playback second.
