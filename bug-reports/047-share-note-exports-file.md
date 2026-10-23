# Bug 047: Sharing a note exports a file instead of Markdown text

Status: FIXED — verified on iPhone, 2026-10-23. Final native Mac sharing awaits password unlock.

## Reproduction

Open a note in Noto 2, open Note actions, and choose Share.
The share item is `session.note.fileURL`, so destinations receive a file.
The Mac toolbar and library context menu have the same source-level defect.

## Expected

All Share actions send the complete Markdown body as plain text, without YAML metadata or template fields.
Every saved-note editor has a top-right Share button.
Current unsaved text takes precedence over the saved file.

## Criteria and verification

See `.codex/feature/share-note-markdown.md` for the shared specification and evidence.

## Investigation log

### Attempt 1

Exported the full Markdown with a UTF-8 DataRepresentation.
Unit tests passed, but native iOS sharing treated it as an attachment.
The independent audit failed because Copy and Messages were absent.
Evidence: `.codex/evidence/20261023-152541-share-markdown-audit/evidence.md`.

### Attempt 2

Native UIActivityViewController and NSSharingServicePicker now receive String items directly.
The NotoVault package owns full-text loading and metadata removal. Inbox edits share their current body directly.
Final native audit is pending.

### Attempt 3

The body-only toolbar export matched all 2,555 expected bytes through native Copy and Paste.
The independent audit found that More-menu sharing lost its presenting view when the menu closed.
iOS presentation now belongs to a stable editor-root host, shared by toolbar and menu buttons.

Regression investigation: the existing title-rename test failed during two parallel Mac runs.
The final sharing tests passed in both runs. A method-only CLI filter found no tests, so it is not counted as a pass.

### Attempt 4

Noto2 Library, Daily Notes, Inbox detail, and Inbox context sharing passed the independent audit.
Noto1 More-menu Copy matched the same 2,555-byte body exactly.
The auditor found that Noto1 toolbar buttons inside one HStack had overlapping tap targets.
Search, Share, and More now use separate native toolbar items. The final toolbar audit is pending.

The full Mac regression suite passes after replacing the existing rename test fixed sleep with a bounded outcome wait.

### Final verification

The separate native toolbar controls passed the focused audit.
Direct Share copied all 2,555 expected bytes, with no frontmatter or template metadata.
More-menu sharing still opens the native sheet. The disposable paste-verification draft was cleared.
Evidence: `.codex/evidence/20261023-165651-share-toolbar-final-gate/evidence.md`.

All 191 NotoVault tests and 24 unique app regression cases pass.
Both iOS app builds and the macOS build succeed.
Final Mac native sharing needs a password unlock because protected services remain sealed after password-free unlock.
iPad runtime sharing was not separately exercised.
