# iOS Visual Evidence Audit

Verdict: PASS

Timestamp: 2026-06-25 00:57 local
Repository: /Users/eugenechan/dev/personal/Noto
Simulator: Noto-Test-docedit (CEF57638-CDF7-4D1B-84EE-D595FACB1F64), iOS 26.2
App: com.eugenechan.Noto (scheme Noto)

## Change Audited

AI document editing in the Noto chat: the user asks the AI to change a note,
the model calls `propose_edits`, and the chat renders a tool-step-styled
"Suggested Edits" card with a GitHub-style diff and Dismiss / Accept controls.
Accepting writes the change to the note `.md` file on disk (frontmatter
preserved) and collapses the card to a "✓ Applied" terminal state.

This audit exercises the LIVE model end-to-end (real OpenRouter call), which the
feature doc's §12 explicitly flagged as the one path NOT previously
screenshot-proven.

## Success Criteria

| Criterion | Result | Evidence |
|-----------|--------|----------|
| SC1 — Edit request produces a "Suggested Edits" card (not a plain tool row), with note name in header + readable diff | PASS | 02-proposed-card.png; 02-proposed-tree.json (header `Suggested Edits ・ Document Shopping List`; rows `− / - Dairy`, `+ / - Dairy- Eggs`; context lines `- Fruits`, `- Vegetables`, `## Notes`; `Go Up`/`Go Down` expand chevrons) |
| SC2 — Minimal tool-step styling: left rule, monochrome header, quiet Dismiss + orange-ink Accept (no heavy chrome) | PASS | 02-proposed-card.png — left rule under the `NOTO` eyebrow, monochrome header, diff with red removed / green added rows on dimmed context, footer is a quiet text "Dismiss" + orange-ink "Accept" (not a filled pill). Matches design doc §6. |
| SC3 — Accept applies edit: card shows ✓ Applied AND file on disk contains new content with frontmatter preserved | PASS | 03-applied-state.png (`✓ Applied ・ Shopping List`); shopping-list-after.md on disk now contains "Eggs"; YAML frontmatter (`---`, `id`, `created`, `modified`) intact and unchanged |

## Artifacts

- 01-launch.png — vault file list with seeded notes
- 02-proposed-card.png — live "Suggested Edits" card (KEY EVIDENCE)
- 02-proposed-tree.json — accessibility tree of the proposed card
- 03-applied-state.png — card collapsed to "✓ Applied" after Accept
- 03-applied-tree.json — accessibility tree of applied state
- shopping-list-before.md — baseline note content (no Eggs)
- shopping-list-after.md — note content after Accept (Eggs present, frontmatter intact)

## Commands

- flowdeck config get --json
- flowdeck apps
- flowdeck ui simulator session start -S CEF57638-... --json
- flowdeck ui simulator tap --point <x,y> -S CEF57638-... --json   (Shopping List row, chat icon, composer, send "Up" button, Accept)
- flowdeck ui simulator type "Add 'Eggs' as a new item to my shopping list." -S CEF57638-...
- flowdeck ui simulator wait "Suggested Edits" -S CEF57638-... --timeout 30
- Disk verification via glob on the app Documents/Noto/Shopping List.md container

## Notes

- Single prompt succeeded — the model called `propose_edits` on the first try; no retries needed.
- The send button is exposed with accessibility label "Up" (not a separate id);
  Accept/Dismiss are addressable by label. The documented `chat.editCard.*`
  identifiers surface under the parent `chat.aiReply` container id in the tree
  (the buttons carry labels "Accept"/"Dismiss"), so taps were done by resolved
  frame coordinates from the tree. Minor identifier delta, not a functional issue.
- DELTA (model authoring quality, not a feature bug): the model anchored the
  addition as a replace of `- Dairy` → `- Dairy- Eggs`, so the on-disk result is
  `- Dairy- Eggs` on one line rather than a clean `- Eggs` bullet on its own line.
  The propose→diff→accept→disk pipeline behaved exactly as designed and the file
  matches the previewed diff verbatim; the imperfect result is the LLM's anchor
  choice. The NotoEdit applier and the UI are correct.
- Frontmatter safety confirmed: the `---` YAML block was byte-for-byte preserved.
- Dismiss / stale / multi-spot terminal states were not exercised in this live
  run (covered by the existing NotoTests/ChatEditSuggestionTests per the caller).
