# iOS Visual Evidence Audit

Verdict: PASS
Timestamp: 2026-09-20 21:17 (local)
Repository: /Users/eugenechan/dev/personal/Noto (branch worktree-link-preview-cards, dirty tree with the link-card change)
Simulator: cc-56c91326-aa9cc9f8 — UDID 1ED6DD60-C199-4928-9FB1-532411DB5DF6 (iPhone 17 Pro, iOS 26.5; stock, not slimmed — guard reported simslim not installed)
App: com.eugenechan.Noto2 (scheme Noto2, Debug), built fresh by this audit from the current working tree

## Change Audited

Noto 2 renders link captures as the editor's link-preview card. A line that is exactly
`[title](url)` or a bare `https://…` URL becomes a card in (a) the Capture tab editor,
(b) the note opened from the share sheet's "Keep editing", and (c) the Digest card, with
any text after the link shown below the card. Feature doc:
`.codex/feature/noto2-quick-capture-link-cards.md`.

Note on environment: the caller's simulator (`FAAE1E37…`) is blocked by the
`flowdeck-guard.sh` PreToolUse hook for this subagent, which provisioned its own sim
(`1ED6DD60…`). The app was therefore built, installed and seeded here from scratch
(`flowdeck run --scheme Noto2`, `.maestro/seed-vault.sh … --bundle-id com.eugenechan.Noto2`).
This makes the audit fully independent of the implementation agent's install.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| SC2a-1 Capture tab: bare URL + Return + "notes" renders the URL line as a card, loading first | PASS | `02-sc2a-url-typed-raw.jpg` (raw URL while caret on line) → `03-sc2a-card-loading-caret-line2.jpg` ("Loading preview…" card, caret on "Notes") |
| SC2a-2 Card loads with title / favicon / host / thumbnail, caret stays on line 2 | PASS | `04-sc2a-card-loaded-caret-line2.jpg` — "Go (programming language)", Wikipedia favicon, en.wikipedia.org, blue G thumbnail; caret after "Notes" |
| SC2a-3 Caret back on the card's line reveals the raw URL | PASS | `05-sc2a-longpress-reveals-raw-url.jpg` (1.2 s long-press on card → raw `HTTPS://en.wikipedia.org/wiki/Go_(programming_language)` with caret on it); `06-sc2a-uparrow-caret-on-url-line-raw.jpg` (Up-arrow keeps caret on line, still raw); `07-sc2a-caret-left-line-card-returns.jpg` (two Down-arrows → card returns) |
| SC2b-1 Safari share → Noto 2 → "Keep editing" opens the note with a card for the `[title](url)` capture | PASS | `11-sc2b-safari-wikipedia-swift.jpg` → `12-sc2b-share-sheet-noto2.jpg` → `13-sc2b-extension-sheet-keep-editing.png` ("Link captured", Keep editing) → `14-sc2b-keep-editing-card-loaded.jpg` (card: "Swift (programming language)", W favicon, en.wikipedia.org; a11y tree had a `Link` element labelled with the title, value = host) |
| SC2b-2 Caret on that line reveals the raw `[title](url)` markdown | PASS | `16-sc2b-editor-focused-caret-below-card.jpg` (editor focused, caret on empty line under card) → `17-sc2b-caret-on-line-raw-markdown-revealed.jpg` (Up-arrow → `[Swift (programming language) - Wikipedia](https://en.wikipedia.org/wiki/Swift_%28programming_language%29)` shown raw, caret at line start). Backing text confirmed in the a11y `TextArea` value. |
| SC3-1 Digest shows the SC2b capture as a link card (title, host, thumbnail) | PASS (thumbnail n/a) | `18-sc3-digest-swift-link-card-3-to-process.png`; `digest-tree-sc3.json` (`Link` "Swift (programming language)" / `en.wikipedia.org` at 36,299 330×104, "3 to process"). The Swift page's metadata carries no thumbnail — the editor card (`14-…`) shows the same, so this is the source, not the Digest surface. Thumbnail rendering on Digest is proven by the Go card in `21-…`. |
| SC3-2 Text after the link is shown below the card | PASS | `21-sc3-digest-go-link-card-plus-remainder-text.jpg` — Go card (title, favicon, host, G thumbnail) with "Notes" beneath; `digest-tree-go-card-with-remainder.json` |
| SC3-3 Swipe gestures still start from the card surface | PASS | Snooze: `19-sc3-snooze-swipe-from-card-surface.jpg` (left swipe begun at 200,350 = inside the link card → "Snoozed until Sep 27, 2026", count 3→2 in `20-…`, then 2→1 in `21-…`). Add to: `22-sc3-swipe-right-from-card-opens-add-to-sheet.jpg` (right swipe begun on the Go card → "Add to a note" sheet) → `23-sc3-filed-into-meeting-notes-inbox-clear.jpg` (picked Meeting Notes → "Inbox clear") |
| SC4 Plain-text capture still renders as plain text on Digest, no card | PASS | `09-sc4-plain-text-typed.jpg` → `10-sc4-plain-text-filed.jpg` (inbox/2026-09-20-a9b90bc3.md) → `20-sc4-digest-plain-text-card-2-to-process.jpg` ("Just a thought" as plain body text, no card; tree shows only a `StaticText`) |

## Artifacts

All under `/Users/eugenechan/dev/personal/Noto/.codex/evidence/20260920-205955-ios-visual-audit/`:

- `01-launch-capture-tab.jpg` — fresh install, Capture tab, empty editor with keyboard
- `02-sc2a-url-typed-raw.jpg`, `03-sc2a-card-loading-caret-line2.jpg`, `04-sc2a-card-loaded-caret-line2.jpg`
- `05-sc2a-longpress-reveals-raw-url.jpg`, `06-sc2a-uparrow-caret-on-url-line-raw.jpg`, `07-sc2a-caret-left-line-card-returns.jpg`
- `08-sc2a-capture-filed-to-inbox.jpg` — inbox/2026-09-20-89b50fef.md
- `09-sc4-plain-text-typed.jpg`, `10-sc4-plain-text-filed.jpg`
- `11-sc2b-safari-wikipedia-swift.jpg`, `12-sc2b-share-sheet-noto2.jpg`, `13-sc2b-extension-sheet-keep-editing.png`
- `14-sc2b-keep-editing-card-loaded.jpg`, `15-sc2b-card-tap-opens-safari.jpg` (incidental: tap on the card opens the URL)
- `16-sc2b-editor-focused-caret-below-card.jpg`, `17-sc2b-caret-on-line-raw-markdown-revealed.jpg`
- `18-sc3-digest-swift-link-card-3-to-process.png`, `19-sc3-snooze-swipe-from-card-surface.jpg`
- `20-sc4-digest-plain-text-card-2-to-process.jpg`
- `21-sc3-digest-go-link-card-plus-remainder-text.jpg`, `22-sc3-swipe-right-from-card-opens-add-to-sheet.jpg`, `23-sc3-filed-into-meeting-notes-inbox-clear.jpg`
- `digest-tree-sc3.json`, `digest-tree-go-card-with-remainder.json` — accessibility trees

## Commands

- `flowdeck config get --json` (saved config = Noto-iOS / shared iPhone 17 Pro; overridden by explicit `-S`, config untouched)
- `flowdeck run --scheme Noto2 -S "1ED6DD60-C199-4928-9FB1-532411DB5DF6" --json` (build + install + launch, exit 0)
- `.maestro/seed-vault.sh 1ED6DD60-C199-4928-9FB1-532411DB5DF6 --bundle-id com.eugenechan.Noto2`
- `flowdeck ui simulator session start -S "…" --json` (session C4B8C107)
- `flowdeck ui simulator open-url "noto2://capture" -S "…"` / `open-url "https://en.wikipedia.org/wiki/Swift_(programming_language)"`
- `flowdeck ui simulator type "…"`, `key 40` (Return), `key 82` (Up), `key 81` (Down)
- `flowdeck ui simulator tap --point "x,y" [--duration 1.2]`, `tap "<label>"`
- `flowdeck ui simulator swipe --from "…" --to "…" --duration 0.3`
- `flowdeck ui simulator screen --screenshot -S "…"` (one-off when the session symlink lagged)

## Notes

- Guard/sim mismatch: the caller's "dedicated" sim `FAAE1E37…` is blocked for this subagent; the hook provisions a per-agent sim. Any future auditor prompt should expect a fresh build on its own sim (about 4 minutes here).
- Guard printed "simslim not installed — sim stays stock", contrary to the house rule that sims boot slim. Not fixable from an audit; flagging.
- Typing via FlowDeck auto-capitalised the input ("HTTPS://…", "Notes"). The detector still cardified the uppercase-scheme URL; the filed capture body literally contains `HTTPS://en.wikipedia.org/…` (see `22-…`). Worth a look: does `LinkPreviewDetector` intentionally accept `HTTPS`? It did here, so no failure, but the stored text is what the sim typed.
- Synthetic long-press on the card is flaky: 0.7 s did nothing; 1.2 s revealed the raw URL in Capture but was delivered as a tap (opened Safari) in the Keep-editing note. Caret placement was therefore also proven via keyboard arrows (Up/Down), which is a real caret-on-line path. A real finger long-press was not tested.
- Visual quirk (not in scope, no criterion fails): with the caret on the empty line directly after a card in the Keep-editing note, the caret renders roughly card-height tall (`16-…`). Likely the trailing paragraph inheriting the reserved 104 pt line height. Worth a follow-up in the editor.
- Visual quirk: after HID typing the software keyboard dismissed, and the floating keyboard toolbar pill overlapped the tab bar (`04-…`, `08-…`). This is the hardware-keyboard-connected state on the simulator; not attributable to this change.
- Swift Wikipedia page had no thumbnail in either the editor or Digest card; the Go page did, so thumbnail rendering on Digest is proven via `21-…`.
- Video recording is broken on this Mac; motion (snooze fly-off, Add-to sheet) proven by before/mid/after screenshots.
- Not verified: macOS card, failed-metadata state on Digest, real-device touch.
