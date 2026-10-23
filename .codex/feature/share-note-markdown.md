# Share note Markdown

Status: Implemented. iPhone verified; final native Mac sharing awaits password unlock.

## User story

Share any note as its complete plain text, preserving Markdown syntax and removing YAML metadata, including template fields.
Provide a direct Share action at the top right of every saved-note editor.

## Success criteria

- Toolbar and existing Share menu actions export UTF-8 plain text, never a file URL.
- Exports include the full Markdown body, with no preview limit, metadata, or rendered formatting.
- Open editors share their latest edits before autosave.
- Library context actions share the chosen note, including when another note is open.
- Unloaded or unavailable documents never export an empty placeholder.
- Noto, Noto 2, Daily Notes, iPhone, iPad, and macOS use the same export contract.
- Inbox detail shares current body edits without metadata or changes to the saved file.

## Test strategy

Swift Testing covers exact raw content, Unicode, long notes, lazy file reads,
missing-file errors, and unsaved editor changes. FlowDeck builds both apps and macOS.
An independent visual audit verifies editor buttons, native share presentation,
and exact clipboard text from the system Copy action.

## Root cause

Existing ShareLink actions export file URLs. Noto 2 has only a menu action.
Noto 1 mobile and Daily Notes have no Share action.

## Verification

- All 191 NotoVault tests pass.
- All 24 unique app regression cases pass, including live edits and selected-note context sharing.
- Final iOS builds for both apps and the macOS build succeed through FlowDeck.
- Noto 2 Library toolbar/More, Daily Notes, Inbox detail, and Inbox context sharing passed the independent audit.
- Native Copy matched the complete 2,555-byte note body and 101-byte Inbox body exactly. Metadata and template fields were absent.
- Noto toolbar and More sharing passed the final focused audit. Native Copy matched the exact 2,555-byte body.
- Mac runtime sharing is pending a password unlock because native services remain sealed after password-free unlock.

Evidence:

- [Final Noto toolbar and More audit](../evidence/20261023-165651-share-toolbar-final-gate/evidence.md)
- [Final exact clipboard comparison](../evidence/20261023-165651-share-toolbar-final-gate/exact-copy-verification.json)
- [Noto 2 Library, Daily Notes, and Inbox audit](../evidence/20261023-162211-share-host-final-audit/evidence.md)
- [Noto 2 exact clipboard comparisons](../evidence/20261023-162211-share-host-final-audit/exact-copy-verification.json)

## Tests

`Packages/NotoVault/Tests/NotoVaultTests/NoteMarkdownShareTests.swift` covers:

- `preservesEntireBodyWithoutMetadata`: removes all YAML fields and preserves the complete Markdown body, Unicode, and long documents.
- `readsChosenFileLazily`: exports the selected file's newest full text.
- `missingFileFails`: rejects unavailable files instead of exporting empty text.
- `emptyDocument`: preserves intentionally empty documents.
- `preservesEditedInboxBody`: preserves body-only edits, including leading Markdown rules.
- `preservesMarkdownWithoutMetadata`: preserves ordinary Markdown and internal horizontal rules.
- `metadataOnlyNote`: shares an empty body when only metadata exists.

`NotoTests/NoteMarkdownShareTests.swift` covers:

- `sharesLatestEditorText`: exports current keystrokes before autosave.
- `unloadedEditorCannotShare`: disables placeholder sharing.
- `contextShareUsesChosenNote`: Mac context actions preserve unsaved selected-note text and read other notes independently.

## Files changed

Created:

- `NotoShared/Views/NoteMarkdownShare.swift`
- `Packages/NotoVault/Sources/NotoVault/NoteMarkdownShare.swift`
- `NotoTests/NoteMarkdownShareTests.swift`
- `Packages/NotoVault/Tests/NotoVaultTests/NoteMarkdownShareTests.swift`
- `.codex/feature/share-note-markdown.md`
- `bug-reports/047-share-note-exports-file.md`

Edited:

- `NotoTests/NoteEditorSessionTests.swift`
- `Noto/Views/NoteEditorScreen.swift`
- `Noto/Views/iOS/IOSEditorNavigationChrome.swift`
- `Noto/Views/macOS/MacEditorNavigationChrome.swift`
- `Noto/Views/macOS/MacDesktopEditor.swift`
- `Noto/Views/macOS/MacDesktopModel.swift`
- `Noto/Views/macOS/MacDesktopWorkspace.swift`
- `Noto/Views/macOS/MacDesktopLibraryViews.swift`
- `NotoShared/Views/NoteEditorActionsMenu.swift`
- `Noto2/Browse/NoteScreen.swift`
- `Noto2/Today/TodayScreen.swift`
- `Noto2/Digest/DigestScreen.swift`

Deleted: none. Existing unrelated changes remain in place.

## References

The implementation follows Apple's native toolbar and sharing APIs:
[Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars),
[UIActivityViewController](https://developer.apple.com/documentation/uikit/uiactivityviewcontroller),
[NSSharingServicePicker](https://developer.apple.com/documentation/appkit/nssharingservicepicker).

## Residual risks

Mac native-share verification is currently limited by sealed protected data after password-free unlock.
The final Mac build and all relevant app tests pass. Native Mac sharing was observed before the lock changed.
iPad runtime sharing was not separately exercised. It uses the same native iOS presentation path.
