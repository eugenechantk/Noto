# iOS Visual Evidence Audit

Verdict: FAIL
Timestamp: 2026-09-19 00:41 HKT
Repository: /Users/eugenechan/dev/personal/Noto
Simulator: cc-012emy8m — B5B4FC33-FC58-4393-829C-62940C8378A3 (iPhone 17 Pro, iOS 26.3)
App: com.eugenechan.Noto2 (scheme Noto2) + com.eugenechan.Noto2.ShareExtension
Build: pre-installed by the implementer; no build/run performed by this audit.

## Change Audited

Share extension "Link captured" sheet (feature doc `.codex/feature/noto2-share-extension-link-capture.md`, SC7–SC9 only; SC1–SC6 were passed by `.codex/evidence/20260918-235728-ios-visual-audit/`). Tapping "Noto 2" in Safari's share sheet shows a dark "Link captured" sheet; "Add notes in Noto 2" opens `noto2://capture?shared=<UUID>` and Noto 2 files the capture and opens it in the Browse editor; ✕ closes the sheet and leaves the capture staged for the next activation drain.

Pages used (all independent of the implementer's Haskell/OCaml runs): Elixir, Erlang, Scala, Clojure.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| SC7 — "Link captured" sheet: title, page title, host `en.wikipedia.org`, "Saved to your inbox as a quick capture.", orange "Add notes in Noto 2", circular ✕ top-left | PASS | `04-link-captured-sheet-t+4s.jpg` (4 s after tap), `04b-link-captured-sheet-t+20s.jpg` (20 s), and the sheet was still present at ~70 s when `05-staged-before-add-notes.txt` was written; repeated for Erlang `12-…`, Scala `19-…`, Clojure `26-…`. Extension log `08-extension-log-add-notes.txt`: `share payload urls=1 texts=1 pageTitle=true` → `staged shared capture F4CA818C…`. |
| SC7 — does not auto-dismiss | PASS | Same sheet in `03` (0.7 s), `04` (4 s), `04b` (20 s) and at ~70 s (`check` frame before tapping Add notes). |
| SC8 — "Add notes in Noto 2" brings Noto 2 to the foreground | PASS | `06-after-add-notes-noto2.jpg`, `14-after-add-notes-erlang.jpg`, `21-…scala…jpg` all show Noto 2 with "◀ Safari" back-chevron. Extension log: `opening Noto 2 with noto2://capture?shared=<id>` → `open(_:options:completionHandler:) via UIApplication` → `UIApplication open completion success=true` (`08`, `16`, `23`). |
| SC8 — staged JSON removed, inbox note created with body `[title](url)` at share time | PASS | Elixir: `05-staged-before-add-notes.txt` (staged `F4CA818C…`) → `07-state-after-add-notes.txt` (pending-captures empty; `inbox/2026-09-19-33ffeb0c.md` body `[Elixir (programming language) - Wikipedia](https://en.wikipedia.org/wiki/Elixir_%28programming_language%29)`, `created: 2026-09-18T16:34:06Z` = share time). Same for Erlang (`13`→`15`, `953412e2.md`) and Scala (`20`→`22`, `55fea2fe.md`). App log: `Drained N shared capture(s); 0 left staged` / `Opening shared capture <id> at <file>` (`09`, `16`, `23`). |
| SC8 — editor shows THAT capture note (warm, Browse tab at root) | PASS | `14-after-add-notes-erlang.jpg`: nav title `[Erlang (programming languag…`, body renders blue link "Erlang (programming language) - Wikipedia". Preceded by `06c-after-back-once.jpg` proving Browse was at root. |
| SC8 — editor shows THAT capture note (warm, a note editor already open in Browse) | **FAIL** | Run 1 (Elixir, Haskell editor open from the implementer's test): `06-after-add-notes-noto2.jpg` and `06b-…t+15s.jpg` still show the **Haskell** note although the app logged `Opening shared capture F4CA818C… at 2026-09-19-33ffeb0c.md` (`09-app-log-add-notes.txt`). Back once landed on Browse root (`06c-after-back-once.jpg`) — the Elixir note was never on the stack. Run 2 (Scala, Erlang editor open): `21-after-add-notes-scala-editor-was-open.jpg` and `21b-…t+10s.jpg` still show **Erlang** although the log says `Opening shared capture 1E840800… at 2026-09-19-55fea2fe.md` (`23-logs-scala-add-notes.txt`). No `pending note did not resolve` error in the `BrowseScreen` category (`09b-app-log-browse.txt`). Reproduced 2/2. |
| SC8 — cold launch | NOT VERIFIED | Noto 2 was already running and is not a FlowDeck-tracked app on this sim, so `flowdeck stop` cannot target it; terminating via simctl is out of scope for this audit. |
| SC9 — ✕ closes the sheet, Safari is back with no share sheet | PASS | `26-link-captured-sheet-clojure.jpg` (sheet) → `28-after-close-safari.jpg` / `28b-after-close-safari-t+8s.jpg` (Clojure page, no sheet; status bar still "◀ Noto 2" = Noto 2 not foregrounded). `28-after-close-tree.json`: root is Safari with Back/Page Menu/Address/refresh/More only. |
| SC9 — Noto 2 did not come to the foreground | PASS | `30-logs-clojure-close.txt`: after the ✕ tap at 00:39:30 the only log lines are the extension's `staged shared capture B0E70CD2…`; no `Drained`/`Opening` app lines, no `opening Noto 2 with` extension line. |
| SC9 — staged JSON still present after ✕ | PASS | `27-staged-clojure-before-close.txt` and `29-staged-clojure-after-close.txt` both list `001789749566543-B0E70CD2-82FD-4079-8BF1-0691734909BF.json` with body `[Clojure - Wikipedia](https://en.wikipedia.org/wiki/Clojure)`. |
| SC9 — filed on next activation, visible in Digest | PASS | `flowdeck ui simulator open-url "noto2://capture"` (no Safari "Open" prompt appeared) → `34-logs-foreground-drain.txt`: `shared capture filed inbox/2026-09-19-d30a2468.md created=true`, `Drained 1 shared capture(s); 0 left staged`. `33-state-after-foreground.txt`: pending-captures empty, `d30a2468.md` body is the Clojure link with `created: 2026-09-18T16:39:26Z` (share time). `32-digest-tab-clojure.jpg`: Digest "6 to process", top card "Sep 19, 2026 at 12:39 AM — [Clojure - Wikipedia](https://en.wikipedia.org/wiki/Clojure)". |

## Artifacts

All under `/Users/eugenechan/dev/personal/Noto/.codex/evidence/20260919-003252-ios-visual-audit/`:

- `00-baseline-state.txt` — staging (1 OCaml leftover) and inbox (1 Haskell note) before the audit.
- `01-safari-elixir.jpg`, `02-share-sheet.jpg` — Safari page and share sheet with the "Noto 2" row.
- `03-link-captured-sheet-t+0.7s.jpg` — sheet container mid-presentation (content not yet rendered).
- `04-link-captured-sheet-t+4s.jpg`, `04b-link-captured-sheet-t+20s.jpg`, `04-link-captured-sheet-tree.json` — SC7 (tree only exposes the Safari root; the extension process is not reachable by the a11y bridge).
- `05-staged-before-add-notes.txt`, `07-state-after-add-notes.txt` — App Group + inbox before/after Add notes (Elixir).
- `06-after-add-notes-noto2.jpg`, `06b-after-add-notes-noto2-t+15s.jpg`, `06c-after-back-once.jpg`, `06-after-add-notes-tree.json` — SC8 failure run 1.
- `08-extension-log-add-notes.txt`, `09-app-log-add-notes.txt`, `09b-app-log-browse.txt` — logs for run 1.
- `10-safari-erlang.jpg`, `11-share-sheet-erlang.jpg`, `12-link-captured-sheet-erlang-t+4s.jpg`, `13-staged-erlang.txt`, `14-after-add-notes-erlang.jpg`, `15-state-after-add-notes-erlang.txt`, `16-logs-erlang-add-notes.txt` — SC8 passing run (Browse at root).
- `17-safari-scala.jpg`, `18-share-sheet-scala.jpg`, `19-link-captured-sheet-scala.jpg`, `20-staged-scala.txt`, `21-after-add-notes-scala-editor-was-open.jpg`, `21b-after-add-notes-scala-t+10s.jpg`, `22-state-after-add-notes-scala.txt`, `23-logs-scala-add-notes.txt` — SC8 failure run 2 (reproduction).
- `24-safari-clojure.jpg`, `25-share-sheet-clojure.jpg`, `26-link-captured-sheet-clojure.jpg`, `27-staged-clojure-before-close.txt`, `28-after-close-safari.jpg`, `28b-after-close-safari-t+8s.jpg`, `28-after-close-tree.json`, `29-staged-clojure-after-close.txt`, `30-logs-clojure-close.txt` — SC9 close path.
- `31-after-open-url-noto2.jpg`, `31-after-open-url-tree.json`, `32-digest-tab-clojure.jpg`, `33-state-after-foreground.txt`, `34-logs-foreground-drain.txt` — SC9 filing on next activation.
- `frames/` — raw FlowDeck session frames around the first Add notes tap.

## Commands

- `flowdeck config get --json` (saved config targets a different sim; the caller's UDID was passed explicitly on every command, config untouched)
- `flowdeck ui simulator session start -S "B5B4FC33-FC58-4393-829C-62940C8378A3" --json` (session 1C0ACBCF)
- `flowdeck ui simulator open-url "https://en.wikipedia.org/wiki/<Page>" -S "<UDID>"`
- `flowdeck ui simulator tap "More" -S …` → `flowdeck ui simulator tap "Share" -S …`
- `flowdeck ui simulator tap -p "245,655" -S …` (Noto 2 in the share sheet — by point, share sheet is not in the tree)
- `flowdeck ui simulator tap -p "200,288" -S …` (Add notes in Noto 2 — by point; extension UI not in the tree)
- `flowdeck ui simulator tap -p "35,102" -S …` (✕ — by point)
- `flowdeck ui simulator tap -p "38,84"` (editor back), `-p "158,822"` (Digest tab)
- `flowdeck ui simulator open-url "noto2://capture" -S …`
- `xcrun simctl spawn <UDID> log show --last Nm --info --predicate …` (extension + app logs, as authorised by the caller)
- `xcrun simctl get_app_container <UDID> com.eugenechan.Noto2 data` (inbox path, as authorised)

## Notes

- **SC8 failure detail.** `RootTabView.openFiledNote` sets `pendingNoteURL` and `selectedTab = .browse`; `BrowseScreen.consumePendingNote` then does `path = [destination]`. When the Browse `NavigationStack` already has a note pushed (`path.count == 1`), the visible editor does not change to the new note — it stays on the previously open note — even though the drain, the ledger lookup and the `Opening shared capture …` log all succeed and no `pending note did not resolve` error is logged. When Browse is at its root (`path == []`) the same code opens the correct note. Reproduced twice (Elixir over Haskell, Scala over Erlang). The capture itself is always filed correctly; only the "open that note" half of SC8 fails in this state. This is a realistic state: a user who previously opened any note in Browse and then shares from Safari.
- The implementer's manual check ("editor shows the note with the rendered link") is consistent with a Browse-at-root state and did not cover the editor-already-open case.
- Cold launch for SC8 not exercised (see table).
- Every tap on the extension sheet and the share sheet was by coordinate; neither surface is exposed through FlowDeck's accessibility tree on this sim (root shows only `Safari`), so the accessibility identifiers `linkCapturedSheet`/`linkCapturedTitle`/… could not be asserted semantically. Visual proof was used instead.
- `03-…t+0.7s.jpg` shows an empty dark card: the extension's sheet content appears ~1 s after the container animates in. Cosmetic; not a criterion.
- Simulator video recording is unavailable on this Mac (per caller); screenshots were used throughout.
- The leftover OCaml capture from the implementer was filed by the first Add notes drain (`6ab7ca4f.md`), as expected; it was not confused with audit captures.
