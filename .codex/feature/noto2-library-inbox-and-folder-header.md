# Feature: noto2-library-inbox-and-folder-header

## User Story

Eugene, 2026-10-18:
- "why don't i see the [inbox] folder in my library? ... a directory that we should expose
  in the library ... the library which exposes everything that is in the [vault], that
  includes inbox"
- "for the metric (like number of folders and notes), we can put it right below the heading
  title which is the directory name. for the sort by we can have a button on the right ...
  so i don't have an extra line of description there"

## Decisions

- `LibraryCatalog.isVisible` no longer hides `inbox/`. Only hidden (dot) folders and media
  `Attachments` folders stay out; they hold no notes.
- Library's Recent section and Search's "recently edited" list keep to filed notes
  (`LibrarySnapshot.filedNotes`, `LibraryNote.isCapture`). Reason: 19 raw captures would
  fill Library's seven Recent slots and repeat the Inbox tab. Pinned captures do show in
  Pinned and in the Add-to sheet's pinned list, because pinning is a deliberate choice.
- Folder pages: `navigationSubtitle` carries "N folders · N notes" under the folder name;
  sorting is a toolbar `Menu` (`arrow.up.arrow.down`) beside New note. The in-list summary
  row is gone.

## Success Criteria

1. Library's Folders section lists `inbox` with its note count.
2. Opening `inbox` lists its captures, and a capture opens in the editor.
3. Library Recent and Search's recently edited list contain no captures.
4. Folder page header: name, with counts below it; no summary row in the list.
5. The sort button offers Recent, Name and Oldest, shows the current choice, and re-sorts.

## Tests

- `LibraryCatalogTests.homeListsEverythingInTheVaultIncludingInbox` — SC1, SC2 (data), SC3
- `NotePinningTests.persistsAndListsByTitleIncludingPinnedCaptures` — pinned captures listed
- `SearchRedesignTests.recentlyEditedUsesSevenNewestPagesIncludingPinsAndRefreshesAfterEdits`
  (existing, unchanged) — SC3 for Search
- `swift test` (NotoVault): 173/173. `Noto2Tests`: 203/204; the one failure is the
  pre-existing `FilingKeyboardLayoutTests.addSearchStays…` (fails on 417a351 too).

## Simulator evidence

`.codex/evidence/20261018-library-inbox-header/`: `01-library-folders.png` (SC1, SC3),
`02-inbox-folder-header.png` (SC4), `03-sort-menu.png` and `04-sorted-oldest.png` (SC5),
`05-open-capture.png` (SC2).

## Independent audit

`ios_visual_evidence_auditor`: **PASS** on all five criteria
(`.codex/evidence/20261018-221734-ios-visual-audit/evidence.md`). Notes: the title-bar
sort and New note buttons are not in the accessibility tree that FlowDeck reads (same for
the existing New note button), and the sort choice resets to Recent when a folder is
reopened. Not covered: folders with subfolders.
