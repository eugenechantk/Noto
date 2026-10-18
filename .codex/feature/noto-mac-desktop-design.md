# Noto desktop design

## User story

Use the Mac desktop design on page D of the supplied Artifact. Navigate the vault, write, capture, and clear the Inbox with the keyboard.

## Reference

- https://claude.ai/artifact/LMhUu5nNQiDZSkLN6pscq8#page-0f2399a88504
- Export: `.codex/design/noto-mac-20261018/artifact-export.html`
- Render the original `boards/*/export.html`; these preserve bundled component imports.
- Before, Mobbin references, and the alternative tree layout are reference material, not product screens.

## Success criteria

- [x] Three panes with compact folder rows and dated note previews. Verify by running Mac app and design comparison.
- [x] At 880 points show two panes; at 480 points show one, with list/sidebar/inspector overlays. Verify at each width.
- [x] Capture files Markdown to Inbox with Undo. Verify real temporary-vault writes and running app.
- [x] Inbox supports Add to, New note, Later, Discard, edit, and keyboard navigation. Verify package tests and running app.
- [x] Command-K/Command-O opens one search palette, starting with recent notes. Results open at a match. Verify search tests and running app.
- [x] Inspector shows Info and Outline; File, View, Go menus expose shortcuts. Verify running app.
- [x] Existing editing, autosave, note links, and iCloud lifecycle remain in the established shared session. Verify relevant tests and both platform builds.

## Decision log

- The URL explicitly selects the Mac desktop page. Implement Noto macOS, not Noto 2's phone redesign.
- Preserve pre-existing working-tree changes. Keep new Mac presentation in `Noto/Views/macOS` and pure projections in NotoVault.
- Use the native editor and controls. Reference sample text and counts become live vault data.
- Product tier: full build, tests, runtime checks, independent design audit.

## Verification evidence

- NotoVault: 136 tests in 21 suites pass, including library projections and fractional timestamps.
- NotoDigest: 50 tests in 3 suites pass.
- NotoSearch: 59 relevant core tests in 10 suites pass. The debounce test also passes alone.
- Noto macOS: 32 unique relevant tests pass in a single worker. This includes fifteen new checks, nine existing NoteEditorSession checks, and eight sync-controller checks.
- Full search run stalled in unrelated suites; the concurrent debounce timing assertion failed there. No full-suite pass is claimed.
- Runtime unit tests require `TEST_RUNNER_NOTO_PREVIEW_VAULT`, not an ordinary inherited environment variable. The documented Xcode prefix forwards the fixture path to the test host. Ordinary Mac preview launches use inherited `NOTO_PREVIEW_VAULT`.
- Independent visual audits cover the main workspace, Inbox, and palettes. Final comparison: `.codex/evidence/noto-mac-20261018-visual-design-verify/final-consolidated/evidence.md`. The report retains exact per-component candidate provenance. Native keyboard ownership and stale list rows are tracked in bug-reports/039-mac-palette-keyboard.md and bug-reports/040-mac-stale-list-rows.md. Find focus return is tracked in bug-reports/041-mac-find-return-focus.md.
- Live build 8 verifies query updates, expanded search, opening the first match, and discard Undo. Earlier runs verify capture Undo, append, create, snooze, skip, editing, and saved file contents.
- A pre-existing lifecycle assertion compared input Markdown with saved Markdown. Saving stamps its timestamp. The test now checks persisted bytes and the expected body, removing its wall-clock boundary assumption.
- Remaining reference map: `.codex/evidence/noto-mac-20261018-visual-design-verify/round-2-reference/evidence.md`.


## Residual risks

The final title and metadata geometry recheck passes. Exact native font identity and RGB matching remain unproven. Runtime checks use an isolated vault; they do not establish production iCloud behavior.

## Change manifest

Exact paths: `.codex/feature/noto-mac-desktop-change-manifest.json`.

Created:

- `Packages/NotoVault/Sources/NotoVault/VaultLibrary.swift` and `Tests/NotoVaultTests/VaultLibraryTests.swift`: bounded library projections, Markdown snippets, backlinks, outline, and calendar helpers.
- `Packages/NotoVault/Sources/NotoVault/NoteFileCommands.swift`, `VaultDailyActivity.swift`, and matching test files: sorting, folder filtering, duplicate identity, title changes, and persisted daily totals.
- `Noto/Views/macOS/MacDesktop{Model,Workspace,LibraryViews,Editor,Capture,Palette,QueryField,Commands}.swift`: the desktop shell, views, native controls, and window-scoped command routing.
- `NotoShared/Support/NotoPreviewConfiguration.swift`: an isolated DEBUG preview vault and window size.
- `NotoShared/Views/MacMarkdownMetadataStrip.swift` and `MacMarkdownFocusStyle.swift`: desktop metadata and typography.
- `NotoTests/MacDesktop{Model,Rendering,Keyboard}Tests.swift`: model, rendering, and keyboard regression checks.
- `bug-reports/039-mac-palette-keyboard.md`, `040-mac-stale-list-rows.md`, `041-mac-find-return-focus.md`, and `042-mac-inbox-selection-after-undo.md`: reproduction and verification records.
- This feature document, the local design export/component manifest, and desktop evidence directories.

Edited:

- `.gitignore`: exclude local build products.
- `Noto.xcodeproj/project.pbxproj`: link the existing local NotoDigest package to Noto.
- `Noto/NotoApp.swift`, `Noto/Views/NoteListView.swift`: desktop entry point and commands.
- `Noto/Views/SettingsView.swift`: skip saved-key reads only in the isolated DEBUG preview.
- `Noto/Sync/ReadwiseSyncController.swift`, `NotoShared/Storage/VaultLocationManager.swift`: keep the DEBUG preview isolated from production vault and sync startup.
- `NotoShared/Views/EditorContentView.swift`, `NotoShared/Editor/TextKit2EditorView.swift`: Mac layout, metadata, focus, and Markdown rendering adapters. Preserve concurrent media edits.
- `Packages/NotoVault/Sources/NotoVault/NoteProperty.swift` and its tests: accept fractional ISO timestamps.
- `NotoTests/NoteEditorSessionTests.swift`: compare saved bytes rather than an input timestamp that saving replaces.
- `README.md`: describe the desktop shell and isolated preview route. Preserve existing documentation changes.

Deleted: none by this task.

Other working-tree edits belong to concurrent or earlier work. They are outside this manifest. No commit, push, release, or Applications installation was performed.

## Native data and proof limits

- Source titles, counts, dates, paths, search ranks, snippets, and note text come from the vault. They need not match the sample data.
- Capture and Inbox totals persist per vault on this Mac. They reset by the local day, and Undo reverses the appropriate total.
- Native SF Symbols, segmented controls, menus, window controls, and material rendering use the component manifest's native translations.
- Static artboards prove visible reference states. They cannot prove hidden states, gesture behavior, exact native font identity, or all animation frames.
- Filesystem and keyboard checks use a disposable DEBUG vault. They do not establish live iCloud or production-vault behavior.

## Final runtime checks

- Candidate 18: Settings opens with Command-comma and closes with Done. No settings values changed.
- Candidate 18: native note context menu opens. Move To places a disposable note in Ideas. The source path disappears; UUID and body remain intact.
- The preview skips saved-key reads in Settings and real Keychain-backed Readwise access. Dependency-injected mock stores remain testable. All eight sync-controller tests pass.
- Runtime screenshots and filesystem assertions: `.codex/evidence/noto-mac-20261018/final-runtime/`.
- Final preview: `.codex/evidence/noto-mac-20261018/final-desktop.jpg` (candidate39, 1440×900). Final hashes and unchanged fixture notes are recorded beside it.
- Candidate 31: Escape closes an unfocused Find bar after search closes. Direct Escape and Done also resume actual typing. All three disposable probes were undone; original Move, Desktop, and Pricing bytes remain identical.
- Candidate 33: final title and toolbar checks cover 480, 880, and 1440 points.
- Candidate 34: the open Inspector header passes targeted 880/1440 checks: Search, Share, and Hide Inspector are visible; the header button closes the panel.
- Candidate 35: all 31 Mac checks pass, including title tracking, hidden-prefix preservation, and empty-title caret metrics. Final adjacent checks cover title, metadata, Daily, and Inbox anchors.

## Menu behavior

Native File, View, Go, Format, and Noto menus carry the reference commands and shortcuts. The note context menu exposes Copy Link, Move To, Duplicate, Rename, Reveal, Share, and Trash. Moving waits for the existing editor session so it can flush unsaved text. Duplicate waits for full text when the source is selected, preventing the bounded list prefix from becoming a truncated copy. Native tests cover duplicate identity, preserved body/properties, folder boundaries, daily rollover, and Undo totals.

The narrow document toolbar uses Search and More. More exposes Inspector, Focus Mode, and Share. The open Inspector header provides Search, Share, and Hide Inspector. Opening Inspector from Inbox enters the existing editor session; Done returns to the Inbox card. Capture does not expose Inspector.

Wide Inbox plain paragraphs use a selectable read-only native text view with ordinary word wrapping. Rich Markdown keeps its existing renderer. The regression checks the rendered line strings and unchanged source text. [Apple documents the native line-break strategy](https://developer.apple.com/documentation/appkit/nstextfield/linebreakstrategy).

Candidate 38: wide Inbox wrapping matches the reference before, during, and after text selection. Text size and card/link placement remain stable. The final 32 Mac checks pass; original fixture notes remain byte-identical.

Candidate 39: the final wide Inbox link gap matches the reference in normal and selected states. All 32 Mac checks pass on the final source.

Final independent verdict: PARTIAL for stated proof limits, with no confirmed visual failures in 149 component rows. Each row covers all nine criteria and retains its actual candidate provenance.
