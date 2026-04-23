# Feature: Readwise Import Preserves Manual Notes

## User Story

As a Noto user importing Reader/Readwise captures, I want importer refreshes to update only importer-owned fields and marked blocks so that my own note additions survive subsequent syncs.

## Success Criteria

- [x] Manual markdown between generated metadata and generated marker blocks is preserved.
- [x] Generated source metadata has its own refreshable `readwise:` marker block.
- [x] Reader/Readwise content and highlight marker blocks still refresh.
- [x] Existing frontmatter tags are retained when generated import tags are refreshed.
- [x] NotoReadwiseSync package tests pass.
- [x] Existing Capture source notes are migrated from `noto:` markers to `readwise:` markers.

## Verification

Run `swift test` in `Packages/NotoReadwiseSync`.
