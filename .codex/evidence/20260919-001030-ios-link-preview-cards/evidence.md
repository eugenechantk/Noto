# iOS Visual Evidence Audit

Verdict: PASS
Timestamp: 2026-09-19 00:10–00:16 (local)
Repository: /Users/eugenechan/dev/personal/Noto/.claude/worktrees/link-preview-cards
Simulator: cc-linkprev — 85604907-83F2-4767-99D7-1B5C76182755 (iPhone 17 Pro, iOS 26.3)
App: com.eugenechan.Noto (scheme `Noto`, Noto.xcodeproj) — pre-installed build, not rebuilt by the auditor

## Change Audited

Link preview cards: a paragraph that is only a bare `https://` URL renders as a native
preview card (title, description, host + favicon, thumbnail) in the Noto editor, backed by
the new `NotoLinkPreview` package (LinkPresentation metadata + on-disk cache). Markdown on
disk stays a plain URL. Caret on the line reveals the raw URL; tap opens the link;
long-press puts the caret on the line.

Changed surface (from `git status` / `git diff --stat`): `NotoShared/Editor/TextKit2EditorView.swift`
(+374/-54), new `NotoShared/Editor/LinkPreviewCardView.swift`, new
`NotoShared/Editor/LinkPreviewSupport.swift`, new `Packages/NotoLinkPreview/`, pbxproj
package reference, tests in `NotoTests/`.

Seeded note (`Link Cards.md`) contains, in order: a bare Apple developer URL, a sentence with
an inline `https://apple.com` and a `[markdown link](https://www.apple.com)`, a bare
`https://github.com/apple/swift`, a bare `https://this-host-does-not-exist.invalid/page`,
a `---` divider, a todo and a bullet.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| SC2 — bare-URL line renders as a fixed-height card (~104pt) with the URL text hidden | PASS | `03-note-open-after-8s.jpg`, `03-note-open-tree.json`: three card elements with frames 360×105, 360×104, 360×104 pt at x=21; no raw URL text visible anywhere on the loaded screen. `04-scrolled-failed-card.jpg` shows the third card at 104pt. |
| SC2 — markdown on disk unchanged (plain URL) | PASS | `diff` of the simulator container file `.../Documents/Noto/Link Cards.md` against the seed file after the whole audit (including caret placement on the URL line and a tap-away): `IDENTICAL to seed`. |
| SC3 — long-press card (~1s) → card disappears, raw URL shown in blue; tapping another paragraph brings the card back | PASS | `05-long-press-reveal.mov` (22s, 189 frames) records the whole sequence. `06-after-long-press-revealed.jpg`: card gone, `https://this-host-does-not-exist.invalid/page` in blue link colour at body metrics, keyboard up with "page" in the QuickType bar (caret is on the line); `06-after-long-press-tree.json` no longer lists the `this-host-does-not-exist.invalid/page` element. `07-after-tap-other-paragraph-card-back.jpg`: caret in "A host that‖does not exist…", failed card rendered again below it. |
| SC5 — loaded card for developer.apple.com: title, description, host, thumbnail right | PASS | `03-note-open-after-8s.jpg` / `03b-cards-crop.jpg`: "Link Presentation \| Apple Developer Documentation", "Fetch, provide, and present rich link…", Apple favicon + `developer.apple.com`, thumbnail on the right. Tree label matches the title. |
| SC5 — loaded card for github.com: title, description, host, thumbnail right | PASS | `03-note-open-after-8s.jpg`: "swiftlang/swift: The Swift Programming Language", "The Swift Programming Language.…", GitHub favicon + `github.com`, OG image on the right. |
| SC5 — failed card for this-host-does-not-exist.invalid shows "Preview unavailable" | PASS | `04-scrolled-failed-card.jpg`: card title is the URL sans scheme, subtitle "Preview unavailable", host line `this-host-does-not-exist.invalid`, no thumbnail. On-disk cache entry for it is `{"failure":{"_0":"2026-09-18T16:04:14Z"}}` (41 bytes). |
| SC6 — short tap on a card leaves the app for Safari with that URL | PASS | `09-tap-card-opens-safari.mov` (15s, 247 frames). `10-after-tap-card-safari.jpg` + `10-after-tap-tree.json`: foreground app is `Safari` with a "◀ Noto" back link. `11-safari-loaded.jpg`: github.com swiftlang/swift repo page rendered. `12-safari-full-url.jpg`: address field shows `https://github.com/swiftlang/s…` (GitHub's server-side redirect of the seeded `apple/swift` URL). |
| Inline URL in a sentence and `[markdown link](…)` stay normal text (no card) | PASS | `03-note-open-after-8s.jpg`: "An inline link like https://apple.com inside a sentence stays plain text, and so does a markdown link." renders as a normal paragraph; the tree lists exactly three card elements (Apple, GitHub, invalid host) and none for apple.com / www.apple.com. |
| Bonus — cache served on reopen (SC4 side-effect) | PASS (observational) | `02-note-open-immediate.jpg` (1.5s after open) and `03-note-open-after-8s.jpg` are byte-identical (38361 bytes) — cards were fully populated with no loading state on a re-open. `Library/Caches/LinkPreviews/` holds 3 `<sha256>.json` entries: 32KB (Apple, with iconData), 40KB (GitHub, with imageData), 41B (failure). |

## Artifacts

All under `/Users/eugenechan/dev/personal/Noto/.claude/worktrees/link-preview-cards/.codex/evidence/20260919-001030-ios-link-preview-cards/`:

- `00-pre-audit-state.jpg`, `00-pre-audit-tree.json` — state as handed over (note already open)
- `01-note-list.jpg` — after tapping Back; list shows "Link Cards, Edited 17m ago"
- `02-note-open-immediate.jpg` — 1.5s after tapping the row
- `03-note-open-after-8s.jpg`, `03-note-open-tree.json`, `03b-cards-crop.jpg` — loaded state, two cards + inline/markdown links as text
- `04-scrolled-failed-card.jpg`, `04-scrolled-tree.json` — after `swipe up`; failed card, divider, todo, bullet
- `05-long-press-reveal.mov` — long-press reveal + tap-away restore (SC3)
- `06-after-long-press-revealed.jpg`, `06-after-long-press-tree.json` — raw URL revealed, card gone
- `07-after-tap-other-paragraph-card-back.jpg`, `07-card-back-tree.json` — card restored
- `08-after-undo-newline.jpg` — after undoing a harness-inserted newline (see Notes)
- `09-tap-card-opens-safari.mov` — short tap → Safari hand-off (SC6)
- `10-after-tap-card-safari.jpg`, `10-after-tap-tree.json` — Safari foreground, "◀ Noto"
- `11-safari-loaded.jpg` — GitHub page rendered
- `12-safari-full-url.jpg` — full URL in the address field
- `13-back-in-noto-final.jpg` — returned to Noto via the status-bar back link; final state

## Commands

- `flowdeck config get --json` → `config_not_found` (no saved config in this worktree; not set, since no build was needed)
- `flowdeck ui simulator session start -S "85604907-83F2-4767-99D7-1B5C76182755" --json` → session BAE3DAB1
- `flowdeck ui simulator tap "Back" -S …`
- `flowdeck ui simulator tap "Link Cards, Edited 17m ago" -S …`
- `flowdeck ui simulator swipe up --distance 0.45 -S …`
- `flowdeck ui simulator record -o …/05-long-press-reveal.mov -t 22 --force -S …` (background)
- `flowdeck ui simulator tap --point 201,487 --duration 1.0 -S …` (long-press failed card; coordinates because the card element exposes a label but the tree does not surface its `link_preview_card_<offset>` identifier)
- `flowdeck ui simulator tap --point 120,322 -S …` (tap "A host that does not exist" paragraph)
- `flowdeck ui simulator hide-keyboard -S …` (see Notes — inserted a Return)
- `flowdeck ui simulator key 42 -S …` (Backspace to undo it)
- `flowdeck ui simulator record -o …/09-tap-card-opens-safari.mov -t 16 --force -S …` (background)
- `flowdeck ui simulator tap --point 201,222 -S …` (short tap GitHub card)
- `flowdeck ui simulator tap "Address" -S …`, `tap --point 343,815` (cancel), `tap --point 30,40` ("◀ Noto")
- Host-filesystem reads only (no simctl): `diff` of container `Link Cards.md` vs seed; `wc -c` / `head -c` on `Library/Caches/LinkPreviews/*.json`

## Notes

- No rebuild was performed; the audit used the build already installed on `cc-linkprev`
  per the caller's instructions. The build under test is therefore the one the implementer
  installed, which I could not independently tie to the current diff beyond the observed
  behaviour matching the feature doc.
- Card taps used coordinates: the accessibility tree exposes each card with its label
  (title or URL) but FlowDeck's tree dump has no `identifier` field, so
  `link_preview_card_<offset>` could not be used with `--by-id`. Frames were read from the
  tree first, so the coordinates targeted the card centre.
- Harness artifact, not an app defect: `flowdeck ui simulator hide-keyboard` sent a Return
  into the editor and split "A host that does not exist…" into two paragraphs. I reversed it
  with a Backspace (`08-after-undo-newline.jpg`) and the final on-disk file diffs clean
  against the seed. The recording `09-…` starts from the repaired state.
- The seeded GitHub URL is `https://github.com/apple/swift`; the card title and Safari
  address show `swiftlang/swift` because GitHub redirects. The tap sent the seeded URL
  (Safari loaded the redirected target); this is expected and not a defect.
- Loading state ("Loading preview") was not observed: the cache was already warm from the
  implementer's earlier open, so cards populated instantly. Proving the loading state would
  require clearing `Library/Caches/LinkPreviews` and reopening; not done because it is
  outside the requested criteria.
- Inline `https://apple.com` in the sentence renders as plain body text (not blue) while
  `[markdown link]` is blue — this matches "stays plain text" and is pre-existing inline
  URL behaviour, not part of this change.
- Not covered by this audit: macOS (SC6 click / SC7 build), Noto 2 target, `<url>` angle-
  bracket and indented variants (SC1 — unit-tested per caller), and the 30-day / 1-day
  cache TTLs (SC4 — unit-tested per caller).
