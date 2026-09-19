# iOS Visual Evidence Audit

Verdict: PASS
Timestamp: 2026-09-19 00:03 (Asia/Hong_Kong, UTC+8) — share fired at 2026-09-18T16:00:14.487Z
Repository: /Users/eugenechan/dev/personal/Noto
Simulator: cc-012emy8m — iPhone 17 Pro, iOS 26.3 — UDID B5B4FC33-FC58-4393-829C-62940C8378A3
App: com.eugenechan.Noto2 (scheme `Noto2`); extension com.eugenechan.Noto2.ShareExtension; App Group group.com.eugenechan.Noto2

## Change Audited

Noto 2 Share Extension link capture (`.codex/feature/noto2-share-extension-link-capture.md`, SC5 + SC6). Sharing a web page from Safari to "Noto 2" should stage `[title](url)` as a JSON file in the App Group `pending-captures/` folder, show a short "Saved to Noto 2" pill, dismiss on its own, and be drained into the vault `inbox/` the next time Noto 2 becomes active, appearing in Digest.

Audit was run independently on a *different* page than the implementer used (Rust rather than Swift), so the new capture is unambiguous. The pre-existing `inbox/2026-09-18-6f53aba1.md` (Swift link, 15:52:50Z) belongs to the implementation pass and was used only as the baseline (`00-inbox-baseline.txt`).

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| 1. Safari share sheet app row shows "Noto 2" | PASS | `04-share-sheet-noto2-row.png` — "Noto 2" with the orange N icon in the app row between Reminders and More, at ~(245,655) pt. Also `05c-session-t-0.9s-share-sheet.jpg` (session frame immediately before the tap). |
| 2. Tapping it shows "Saved to Noto 2" and the sheet dismisses on its own, well under 2 s, with no further input | PASS | `05d-session-t+0.1s-pill.jpg` — FlowDeck session frame at epoch 1789747214596 ms (~110 ms after the staged `createdAt` 1789747214487 ms): extension sheet with the dark pill "✓ Saved to Noto 2". `05e-session-t+1.45s.jpg` (1789747215939 ms, +1.45 s): Safari page with no sheet. `05a`/`05b` are the slower one-shot frames bracketing the same window; `07-share-sheet-dismissed.png` is the settled state at +9 s. No taps were issued between the "Noto 2" tap and these frames. |
| 3. JSON file exists under the App Group container `pending-captures/` whose `body` is `[<page title>](<url>)` with `(`/`)` percent-encoded | PASS | `06-staged-capture.json` copied from `.../Containers/Shared/AppGroup/4A6CBF4D-6433-4725-8216-C81254AFF374/pending-captures/001789747214487-3433EAFB-….json` (container metadata id `group.com.eugenechan.Noto2`). Body: `[Rust (programming language) - Wikipedia](https://en.wikipedia.org/wiki/Rust_%28programming_language%29)` — title parens kept, URL parens encoded as `%28`/`%29`. `createdAt` 1789747214487. |
| 4. After foregrounding Noto 2: staged file gone; new `inbox/*.md` whose body is that link; `created:` equals share time; Digest shows the capture card | PASS | `10-drain-proof.txt` — `pending-captures/` empty after foreground; inbox gained `2026-09-19-c941a054.md`. `10-inbox-2026-09-19-c941a054.md` — frontmatter `created: 2026-09-18T16:00:14Z` (= staged createdAt 16:00:14.487Z, not the 16:02Z drain time), `type: note`, `status: inbox`, body is the same markdown link. `09-digest-tab.png` + `09-digest-tree.json` — Digest shows "2 to process" and the top card labelled `[Rust (programming language) - Wikipedia](https://en.wikipedia.org/wiki/Rust_%28programming_language%29)` dated "Sep 19, 2026 at 12:00 AM" (= 16:00Z in UTC+8). |

SC5 (drain runs on return to `.active`) is covered by criterion 4: Noto 2 was already running in the background (it was on Digest at `01-launch.png`), was foregrounded via `noto2://capture`, and the drain completed before the Digest tab was even opened (`10-drain-proof.txt` was captured 16:02:38Z, before `09-digest-tab.png`).

## Artifacts

All under `/Users/eugenechan/dev/personal/Noto/.codex/evidence/20260918-235728-ios-visual-audit/`:

- `00-inbox-baseline.txt` — inbox listing before the share (one implementer note only)
- `01-launch.png` — Noto 2 running on Digest before the audit (implementer's Swift capture, "1 to process")
- `02-safari-page.png` — Safari on Rust_(programming_language)
- `03-safari-more-menu.png` — Safari More menu with "Share"
- `04-share-sheet-noto2-row.png` — share sheet, "Noto 2" in app row (criterion 1)
- `05-share-tap-time.txt` — wall clock immediately before the tap command
- `05a-extension-sheet-presenting-t+0.3s.png` — one-shot frame: extension sheet presenting, pill not yet drawn
- `05b-sheet-gone-t+2.2s.png` — one-shot frame: sheet gone
- `05c-session-t-0.9s-share-sheet.jpg` — session ring frame before tap
- `05d-session-t+0.1s-pill.jpg` — session ring frame: "Saved to Noto 2" pill (criterion 2)
- `05e-session-t+1.45s.jpg` — session ring frame: sheet dismissed (criterion 2)
- `06-staged-capture.json` — staged capture from the App Group container (criterion 3)
- `07-share-sheet-dismissed.png` — settled Safari state at +9 s
- `08-open-prompt.png` — Noto 2 foregrounded on Capture (no Safari "Open" prompt appeared this time)
- `09-digest-tab.png`, `09-digest-tree.json` — Digest showing the Rust capture card (criterion 4)
- `10-drain-proof.txt`, `10-inbox-2026-09-19-c941a054.md` — on-disk drain proof (criterion 4)

## Commands

```
flowdeck config get --json                                   # saved config is Noto-iOS / iPhone 17; overridden per-command with -S
flowdeck ui simulator session start -S "B5B4FC33-…" --json   # session 554EF0BA, 500 ms ring, screens/ dir
flowdeck ui simulator screen -S "B5B4FC33-…" --output …      # each still
flowdeck ui simulator open-url "https://en.wikipedia.org/wiki/Rust_(programming_language)" -S "B5B4FC33-…"
flowdeck ui simulator tap "More" -S "B5B4FC33-…"
flowdeck ui simulator tap "Share" -S "B5B4FC33-…"
flowdeck ui simulator tap -p "245,655" -S "B5B4FC33-…"       # "Noto 2" in share sheet (by point — sheet not in a11y tree)
flowdeck ui simulator open-url "noto2://capture" -S "B5B4FC33-…"
flowdeck ui simulator tap -p "160,805" -S "B5B4FC33-…"       # Digest tab (by point — tab bar items not in a11y tree)
flowdeck ui simulator session stop -S "B5B4FC33-…"
```

No build was run: the caller stated Noto 2 was already built/installed/seeded/running on this simulator, and `01-launch.png` confirmed it. No source, test, or project files were modified.

## Notes

- **Pill capture method.** One-shot `flowdeck ui simulator screen` has ~1–2 s latency, so its burst missed the ~0.7 s pill. The FlowDeck session ring (`.flowdeck/automation/sessions/554EF0BA/screens/`, epoch-ms filenames) caught it; those frames were copied into the evidence folder before the 60 s retention expired. Timing in the table is derived from the ring filenames vs. the staged `createdAt`.
- **Two taps were by coordinate** (share-sheet "Noto 2" at 245,655 and the Digest tab at 160,805) because neither the share sheet nor the tab-bar items are exposed in the accessibility tree. Both positions were confirmed from a screenshot before tapping.
- **No Safari "Open in Noto 2?" prompt** appeared on `noto2://capture` this time — the app foregrounded directly (the prompt was presumably already accepted earlier in this simulator's life). Did not affect the drain.
- **Observation, not a failure:** the Digest card renders the capture as raw markdown text (`[title](url)`) rather than as a styled link. The criterion asks for the card "with that link text", which is met, but if a rendered link is expected in Digest that is a separate follow-up.
- **Observation:** the inbox filename date is the *local* date at share time (`2026-09-19-…` for 00:00:14 HKT) while `created:` is UTC (`2026-09-18T16:00:14Z`). This matches the existing Capture-tab convention (the implementer's `2026-09-18-6f53aba1.md` at 15:52:50Z = 23:52 HKT) so it is consistent, just worth knowing when eyeballing filenames against frontmatter.
- **Not covered here:** device (non-simulator) behaviour, share-from-other-apps (only Safari was exercised), text-only shares (SC2 — unit-tested), failed-write retention (SC4 — unit-tested), and Search indexing of the drained note (SC5 second half — not in the requested criteria).
