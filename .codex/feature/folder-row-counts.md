# Feature: Folder Row Counts

## User Story

As a Noto user, I want folder rows to show what is inside each folder so the note list is more informative than a folder modified time.

## User Flow

1. Open a note list that contains folders.
2. Read each folder row subtitle.
3. See immediate child counts for folders and note items.

## Success Criteria

- [x] Folder row subtitles show folder and item counts.
- [x] Folder row subtitles no longer show elapsed modified time.
- [x] Counts are loaded from the filesystem with the folder summary.
- [x] Existing folder sorting and note row timestamps remain unchanged.

## Test Strategy

- Package test covers filesystem folder summaries with immediate folder and markdown item counts.
- Simulator build validates the app compiles with the updated row model.

## Verification

- `swift test --package-path Packages/NotoVault` passed on 2026-04-24.
- `flowdeck build -S 2A34A57A-3948-47F5-9AAE-3BF54B7BC28C` passed on 2026-04-24.
- Simulator visual check showed folder rows with immediate counts, while note rows still showed elapsed time. Final subtitle order is files first, then folders.
