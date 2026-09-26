# Note Editor Copy Path

## Product tier

Small editor workflow enhancement.

## User story

As a Noto user, I can copy the current note's vault-relative path from the editor More menu so I can reference the note elsewhere without exposing an unstable device-container path.

## Success criteria

- [x] The shared note editor More menu contains a `Copy Path` action in both Noto and Noto 2.
- [x] Copy Path writes the current note's vault-relative path, including its `.md` extension, to the iOS pasteboard.
- [x] A root note copies as `Note.md`; a nested note copies as `Folder/Note.md`.
- [x] If the note is unexpectedly outside the configured vault, Copy Path falls back to its standardized absolute path instead of producing a misleading relative path.
- [x] The action has the stable accessibility identifier `copy_note_path_menu_item`.

## Test plan

- Unit-test root, nested, and outside-vault path formatting.
- Simulator-test that Copy Path appears in the editor More menu and can be invoked.
- Build both Noto and Noto 2 because the menu is shared by both app targets.

## Verification status

PASS. Both app targets build. The focused path/pasteboard suite passed before the final architecture cleanup, and the full Noto 2 suite passed 117/117. A later redundant focused rerun was unable to launch XCTest on the root session's isolated simulator, but the final Noto 2 build and independent runtime audit passed; the audit pasted the copied value as `Projects/Roadmap.md` and verified `copy_note_path_menu_item`.

Evidence: `.codex/evidence/20260925-235640-ios-visual-audit/evidence.md`.
