# iOS Visual Evidence Audit

Verdict: PASS
Timestamp: 2026-06-25 01:31 local
Repository: /Users/eugenechan/dev/personal/Noto
Simulator: Noto-Test-docedit (CEF57638-CDF7-4D1B-84EE-D595FACB1F64, iOS 26.2)
App: com.eugenechan.Noto

## Change Audited
Content-normalization fix for AI document editing. Previously when the model added a
line via the propose_edits / VaultEditTool path, a literal `\n` (backslash-n) ended up
in the note (e.g. `- Dairy\n- Eggs` on one physical line). The tool now normalizes
literal escape sequences to real newlines so an added bullet lands as its own line.

Live flow: open Shopping List.md -> open chat (note auto-attached) -> ask to add an
"Eggs" bullet -> review Suggested Edits diff card -> Accept -> verify on disk.

## Success Criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| SC1: Added bullet "Eggs" is its own clean line on disk; NO literal `\n` | PASS | `eggs-line-od-c.txt` shows `- D a i r y \n - E g g s \n` where `\n` = real 0x0A byte; `grep '\\n'` finds NO literal backslash-n; `Shopping List.md.after` line 11 = `- Eggs`. Diff card `04-suggested-edits-card.png` shows a clean green `+ - Eggs` row on its own line; a11y tree (`04-card-tree.json`) lists `'- Dairy'` and `'- Eggs'` as separate labels. |
| SC2: `modified:` bumped to today; id/created unchanged | PASS | After: `modified: 2026-06-25T04:30:44Z` (today UTC); `id: a1b2c3d4-e5f6-7890-abcd-000000000002` unchanged; `created: 2026-03-15T10:00:00Z` unchanged. Baseline was `modified: 2026-03-15T10:00:00Z`. |

## Artifacts
- 01-launch.png / 01-launch-tree.json — Vault file list
- 02-note-open.png — Shopping List.md open (Fruits/Vegetables/Dairy baseline)
- 03-chat-open-attached.png — Chat sheet, Shopping List auto-attached
- 04-suggested-edits-card.png / 04-card-tree.json — Suggested Edits diff card, green `+ - Eggs`
- 05-applied.png — Card shows "✓ Applied"
- eggs-line-od-c.txt — od -c raw bytes around the Eggs line
- Shopping List.md.after — full file after the edit

## Raw bytes (od -c, lines 10-11)
```
0000000    -       D   a   i   r   y  \n   -       E   g   g   s  \n
```
(`\n` shown by od = single 0x0A newline byte, not a `\` `n` pair.)
`grep -n '\n'` over the file: PASS — no literal backslash-n sequence present.

## Commands (key FlowDeck)
- flowdeck config get --json
- flowdeck ui simulator session start -S CEF57638-CDF7-4D1B-84EE-D595FACB1F64 --json
- flowdeck ui simulator tap -S <udid> --point "200,648"   (open Shopping List)
- flowdeck ui simulator tap -S <udid> "Chat"
- flowdeck ui simulator type -S <udid> "Add an item 'Eggs' to my shopping list as a new bullet."
- flowdeck ui simulator tap -S <udid> --point "356,500"   (send)
- flowdeck ui simulator tap -S <udid> "Accept"
- flowdeck ui simulator session stop -S <udid> --json

## Notes
- The app was already built/installed/running on CEF57638 per the caller; no rebuild was
  performed (config's saved sim is a different device, so the UDID was passed explicitly).
- Model called propose_edits on the first attempt; no retries needed.
- Tapped Shopping List and the send arrow by coordinates (the list button label is the
  combined "Shopping List, Edited 3m ago"; send arrow has no resolvable label). Chat and
  Accept were tapped by their accessibility labels.
- Disk container confirmed by `find ... -path "*Documents/Noto/*"`; only one matched and it
  is the one that changed.
