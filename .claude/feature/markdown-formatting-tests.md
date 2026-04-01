# Feature: Markdown Formatting Regression Tests

## User Story

As a developer, I want unit tests covering all markdown formatting rules so that changes to MarkdownTextStorage don't silently break existing formatting behavior.

## Success Criteria

- [x] Heading font sizes: H1=28, H2=22, H3=18
- [x] Heading font weights: H1=bold, H2=bold, H3=semibold
- [x] Heading spacing before: H1=24, H2=20, H3=16 (progressive)
- [x] Heading spacing after: H1=12, H2=8, H3=6 (progressive)
- [x] Title heading (first H1) has no spacing before
- [x] Heading prefix hidden when not active line (font=0.1, color=clear)
- [x] Heading prefix shown dimmed when active line (tertiaryLabel color)
- [x] Body paragraph spacing: 6px
- [x] Bullet indent: 12px per level (L1=12, L2=24, L3=36)
- [x] Bullet wrapped lines align with text after bullet (headIndent = levelIndent + bulletWidth)
- [x] Bullet paragraph spacing: 4px
- [x] Bullet character replaced: `-` and `*` become `•`
- [x] Ordered list indent: 12px per level
- [x] Ordered list wrapped lines align with text after prefix
- [x] Ordered list paragraph spacing: 4px
- [x] Frontmatter hidden (font=0.1, color=clear)
- [x] Bold formatting applies bold weight
- [x] Italic formatting applies italic trait
- [x] Inline code uses monospaced font

## File I/O (MarkdownNoteStore)

- [x] Note CRUD: create, read, save, delete
- [x] Frontmatter: generation, ID extraction, timestamp update, title extraction
- [x] Daily notes: creation, template applied, idempotent, retroactive template
- [x] Templates: content, no double-apply, preserves existing content
- [x] File rename: title-based rename, daily notes keep ISO date
- [x] Folders: create, delete, listed before notes

## Steps to Test in Simulator

N/A — these are unit tests. Run via `test_sim` with `-only-testing:NotoTests`.

## Bugs

### Bug 1: Crash on multi-line bullet formatting (FIXED)
**Description:** `applyBulletList` replaces `-` with `•` via `replaceCharacters` during `enumerateSubstrings`, mutating the backing store during enumeration and causing a crash.
**Fix:** Collect lines into an array first, then iterate the array to apply formatting.
