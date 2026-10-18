# Stale Mac list rows

## Status: FIXED

## Reproduction

1. In Inbox, select a snoozed capture, then another capture.
2. Both rows keep their orange selection surface.
3. Open Search and type a query.
4. The query changes, but some prior Recent rows remain visible.

Independent screenshots and AX evidence are in `.codex/evidence/noto-mac-20261018-visual-design-verify/round-5/`.

## Change

Pass current item and selection values into the row builders. Reset the list content identity when selection changes. Build palette rows from a current snapshot, and accept index results only for their matching query.

## Verification

Build 8 confirms typed search results, expanded results, and opening the first match. Independent build 9 verification confirms one selected Inbox row after Jamie-to-Calm reselection, with matching AX selection values. The same review confirms query-relevant search results.
