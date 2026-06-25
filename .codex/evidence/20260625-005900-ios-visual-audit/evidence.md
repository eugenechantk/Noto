# iOS Visual Evidence Audit

Verdict: PARTIAL

Timestamp: 2026-06-25 00:17 (local)
Repository: /Users/eugenechan/dev/personal/Noto
Simulator: Noto-Test-docedit (CEF57638-CDF7-4D1B-84EE-D595FACB1F64, iOS 26.2)
App: com.eugenechan.Noto

## Change Audited

Accepting an AI "Suggested Edits" card now writes the note via file IO, stamps the
`modified:` frontmatter timestamp at the write, and publishes an in-process sync
snapshot so a note open in the editor updates live. Previously `modified` was not
bumped for this accept path.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| SC1: Edit accepted → note file on disk contains the new line | PARTIAL | File now contains "Eggs", but written malformed: line 10 is `- Dairy\n- Eggs` with a LITERAL backslash-n, not a real newline. So "Eggs" did not become its own list line. See on-disk `cat -v -e` and screenshots 06/08. |
| SC2 (the fix): `modified:` frontmatter bumped to today at write | PASS | Before: `modified: 2026-03-15T10:00:00Z`. After: `modified: 2026-06-25T04:16:32Z` (today). `id` (…000002) and `created` (2026-03-15T10:00:00Z) unchanged. |
| SC3 (live sync): open editor shows updated content after closing chat, no reopen | PASS | After Accept and swiping the chat sheet down, the still-open Shopping List editor showed the new content with no manual reopen. `08-editor-after-sync.png`. |

## Artifacts

- 01-launch.png — vault file list
- 02-note-open.png — Shopping List editor (baseline: Fruits/Vegetables/Dairy)
- 03-chat-open.png — chat sheet, Shopping List auto-attached
- 04-typed.png — propose_edits request typed
- 05-response.png — Suggested Edits card appeared (1st attempt)
- 06-suggested-edits-card.png — clean card showing diff `- Dairy` → `- Dairy\n- Eggs`, Accept/Dismiss
- 07-applied.png — card collapsed to "✓ Applied"
- 08-editor-after-sync.png — editor live-updated showing `- Dairy\n- Eggs` (literal \n)

## Commands (FlowDeck)

- flowdeck config get --json
- flowdeck apps
- flowdeck ui simulator session start -S CEF57638-… --json
- flowdeck ui simulator screen -S CEF57638-… -o <path> --json
- flowdeck ui simulator tap -p <x,y> -S CEF57638-… --json
- flowdeck ui simulator type "…" -S CEF57638-… --json
- flowdeck ui simulator hide-keyboard -S CEF57638-… --json
- flowdeck ui simulator tap "Accept" -S CEF57638-… --json
- flowdeck ui simulator swipe --from 200,90 --to 200,820 --duration 0.5 -S CEF57638-… --json

## Notes

- The fix under audit (modified-stamp bump + live in-process editor sync) is verified
  working: SC2 and SC3 both PASS, proven on disk and on screen.
- Audit surfaced a SEPARATE content-correctness bug not specific to this fix: the AI's
  propose_edits replacement string contained a literal `\n` escape that was written to
  disk verbatim ("- Dairy\n- Eggs") instead of being interpreted as a newline. The
  card's diff preview also rendered the literal `\n`. Result: "Eggs" is on disk but not
  as a proper separate list line. This is a string-handling defect in the edit
  apply/parse path (or the model emitting an escaped newline that the tool fails to
  normalize), independent of the modified-stamp/live-sync change.
- Accept was tapped by the "Accept" label. The requested accessibility id
  `chat.editCard.accept` did not resolve via element query (only the "Accept" label was
  exposed); the labeled control is the same Accept button on the card.
- Card appeared on the first attempt; no retries needed.
