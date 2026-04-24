# Feature: Active Note Search in Editor

## User Story

As a Noto user editing or reading a note, I want to search within the active note, move between occurrences, and see matches highlighted so I can quickly find and edit specific text without leaving the editor.

## Scope

This is find-in-current-note, not vault-wide search. It should operate entirely on the active editor text in memory and should not use the `NotoSearch` SQLite/FTS index.

## User Flow

1. User opens a note in the editor.
2. User invokes note search from the editor More actions menu or with `Command-F`.
3. A compact find bar appears directly below the More actions button, aligned to the right edge of the window.
4. User types a keyword or phrase.
5. Matching occurrences are highlighted in the editor.
6. The current occurrence is visually distinguished from the other highlighted matches.
7. User taps/clicks down or up arrows, or uses keyboard arrow keys while the search field is focused, to move to the next or previous occurrence.
8. The editor scrolls the selected occurrence into view and selects or focuses that range.
9. User edits the note while search is active.
10. Matches update against the latest text without persisting any search metadata into the note.
11. User clears or closes search and all highlights disappear.

## Success Criteria

- [ ] Search field is available from the active note editor on iOS, iPadOS, and macOS.
- [ ] Typing a query highlights all case-insensitive matches in the active note.
- [ ] Current match uses a bright yellow highlight, while other matches use a slightly opaque yellow highlight.
- [ ] Up/down controls and keyboard arrow keys navigate through matches and wrap at the ends.
- [ ] Find bar search field is pill-shaped, uses native glass treatment where available, and follows Apple search-field guidance: magnifying glass affordance, content-specific placeholder, inline clear button when text exists, and immediate results while typing.
- [ ] Up/down buttons live inside the pill-shaped search field, while close is a separate adjacent button.
- [ ] Navigation scrolls the current match into view.
- [ ] Editing text while search is open recomputes matches and keeps state valid.
- [ ] Clearing or closing search removes all highlights and leaves note content unchanged.
- [ ] Search highlights coexist with markdown styling, hidden todo syntax, collapsed image/frontmatter rendering, and hyperlink title rendering.
- [ ] Implementation does not touch vault-wide search indexing or persist search state to markdown files.

## Platform & Stack

- Platform: iOS, iPadOS, macOS
- UI: SwiftUI editor composition plus UIKit/AppKit editor controllers
- Editor: `TextKit2EditorView`
- Text engines: `UITextView` on iOS/iPadOS, `NSTextView` on macOS
- Active entry path: `NoteEditorScreen` -> `EditorContentView` -> `TextKit2EditorView`

## Recommended Product Shape

Use a compact editor-local find bar anchored under the More actions button on the right edge of the window.

Entry points:

- Add `Search in Note` to the editor More actions menu.
- Place `Search in Note` immediately before `Delete Note`.
- Keep `Delete Note` visually separated as the destructive action.
- Add the menu item in both platform chrome implementations:
  - `Noto/Views/iOS/IOSEditorNavigationChrome.swift`
  - `Noto/Views/macOS/MacEditorNavigationChrome.swift`

Controls:

- Pill-shaped search field with search icon, content-specific placeholder text such as `Find in Note`, and inline clear-text button when a query exists
- Previous match button inside the search pill
- Next match button inside the search pill
- Separate close button outside the search pill
- Search pill and close button should match the native editor More button height/hit target. Current implementation uses 44-point controls.

Behavior:

- Empty query shows no highlights and disables arrows.
- No matches disables arrows.
- First non-empty query selects the first match at or after the current caret when possible; otherwise the first match.
- Up/down button navigation wraps.
- Keyboard arrow navigation wraps: down/right moves to the next occurrence, up/left moves to the previous occurrence while the search field is focused.
- Search should not trigger autosave by itself. Only actual note text edits should publish content changes.

Keyboard shortcuts:

- `Command-F` opens the editor find bar.
- Arrow keys navigate between occurrences while the search field is focused.
- macOS may also support `Command-G` next and `Shift-Command-G` previous if this fits naturally after the first implementation.
- iPad hardware keyboard should support `Command-F`; `Command-G` and `Shift-Command-G` can follow if they fit the existing `UIKeyCommand` setup.
- iPhone can rely on visible controls.

## Architecture

### Shared Search Model

Create a small shared model near the editor code, for example `EditorFindState` or `EditorFindModel`.

Proposed responsibilities:

- Store `query`.
- Store `[NSRange]` matches in UTF-16 coordinates.
- Store `selectedMatchIndex`.
- Derive display count and navigation availability.
- Recompute matches from a plain `String`.
- Preserve or repair selection after text edits.

Use `NSString`/`NSRange`, not Swift `String.Index`, because both `UITextView` and `NSTextView` selection and scroll APIs use UTF-16 ranges.

Initial matching rules:

- Required case-insensitive matching.
- Literal substring matching.
- Non-overlapping matches.
- No regex.
- No stemming.
- No tokenization.

That is the right first version for editor find. Vault-wide search can keep richer FTS behavior separately.

### SwiftUI Host

Update `EditorContentView` to own the visible search UI state and pass search bindings into `TextKit2EditorView`.

Likely additions:

- `@State private var isFindVisible = false`
- `@State private var findQuery = ""`
- `@State private var findNavigationRequest: EditorFindNavigationRequest?`
- `@State private var findStatus: EditorFindStatus`

The SwiftUI find bar should be shared between platforms unless a platform-specific affordance is clearly better.

Because the More actions menu lives in the platform editor chrome, `NoteEditorScreen` should expose an `onSearchRequested` action into `EditorNavigationChrome`, similar to the existing delete action. That action should toggle or show the shared find bar owned by the editor content layer.

The find UI should be presented as a right-aligned overlay/popover rather than a full-width banner. Its frame should be anchored to the trailing edge of the editor window and sit immediately below the More actions button/top chrome. This keeps the search controls spatially connected to the menu item that opened them and avoids pushing editor content down.

### TextKit Bridge

Extend both `TextKit2EditorView` representable variants with search inputs:

- `findQuery`
- `selectedFindMatchIndex` or a navigation request token
- callback for match status changes

Both iOS and macOS `TextKit2EditorViewController` implementations should:

- Recompute match ranges when query or editor text changes.
- Apply highlight attributes after markdown rendering/restyling.
- Navigate to the selected range using platform text APIs.
- Clear only search highlight attributes when query is empty or view updates.

### Highlighting Strategy

Treat find highlights as final render attributes on `textView.textStorage`.

Use a narrow editor-search highlight palette:

- All non-current matches: slightly opaque yellow background.
- Current match: bright yellow background.

Important: apply search highlights after markdown styling and hyperlink restyling. The existing editor already styles markdown through `MarkdownParagraphStyler`, `MarkdownTextDelegate`, and platform-specific hyperlink restyling. Search should be layered last so it does not get erased by markdown updates.

Initial implementation can use `.backgroundColor` on text ranges. If hidden syntax/image/frontmatter behavior makes background attributes visually weak or inconsistent, add lightweight overlay rect drawing later.

### Navigation Strategy

iOS/iPadOS:

- Set `textView.selectedRange = range`.
- Call `textView.scrollRangeToVisible(range)`.
- Keep keyboard behavior deliberate: opening search should focus the search field; navigating can keep focus in the field unless selecting text in the editor proves necessary for scroll reliability.

macOS:

- Use `textView.setSelectedRange(range)`.
- Use `textView.scrollRangeToVisible(range)` or `scrollToVisible` through the layout manager if needed.
- When search is opened with `Command-F`, focus the search field.

## Implementation Phases

### Phase 1: Shared Matching Logic

Scope:

- Add a pure search range helper.
- Add unit tests for matching behavior.

Expected files:

- New or existing editor support file under `Noto/Editor/`
- New tests under `NotoTests/` if app tests are the right target

Verification gate:

- Tests cover empty query, case-insensitive matches, repeated matches, Unicode/emoji-adjacent text, no matches, and non-overlapping matches.

### Phase 2: Editor Find Bar UI

Scope:

- Add the visible find bar to `EditorContentView`.
- Add `Search in Note` to the editor More actions menu before `Delete Note` on iOS/iPadOS and macOS.
- Add `Command-F` as the primary keyboard shortcut for opening the find bar.
- Add arrow-key handling in the focused search field for previous/next occurrence navigation.
- Add controls and accessibility identifiers.
- Wire query and navigation intents, without TextKit highlighting yet if needed.

Expected files:

- `Noto/Views/Shared/EditorContentView.swift`
- Possibly a new shared SwiftUI view file such as `Noto/Views/Shared/EditorFindBar.swift`
- `Noto/Views/NoteEditorScreen.swift`
- `Noto/Views/iOS/IOSEditorNavigationChrome.swift`
- `Noto/Views/macOS/MacEditorNavigationChrome.swift`

Verification gate:

- UI builds on iOS and macOS.
- More actions menu shows `Search in Note` immediately before `Delete Note`.
- `Command-F` opens and focuses the search field.
- Arrow keys move between occurrences while focus is in the search field.
- Empty/no-match states disable navigation controls.
- Find bar appears directly below the More actions button, aligned to the right edge of the window.
- Find bar layout does not obscure critical editor chrome; any overlay behavior is visually deliberate and dismissible.

### Phase 3: TextKit Highlighting

Scope:

- Pass find state into both iOS and macOS `TextKit2EditorView` implementations.
- Apply and clear search highlight attributes.
- Reapply highlights after text changes and markdown restyling.

Expected files:

- `Noto/Editor/TextKit2EditorView.swift`

Verification gate:

- Highlights appear for all matches.
- Highlights disappear on clear/close.
- Markdown styling still works for headings, lists, todos, links, code spans, frontmatter, and images.

### Phase 4: Navigation and Keyboard Shortcuts

Scope:

- Implement next/previous navigation.
- Add wraparound behavior.
- Add optional `Command-G` and `Shift-Command-G` where platform-appropriate.

Expected files:

- `Noto/Views/Shared/EditorContentView.swift`
- `Noto/Editor/TextKit2EditorView.swift`
- Platform chrome files only if the search entry point belongs in existing toolbar/menu chrome

Verification gate:

- Up/down buttons move between matches.
- Arrow keys move between matches while the search field is focused.
- `Command-F` remains available after navigation work.
- Optional next/previous keyboard shortcuts work on macOS and iPad hardware keyboard where supported.
- Current match scrolls into view.

### Phase 5: Simulator and Visual Validation

Scope:

- Build and run the app through FlowDeck.
- Seed an isolated simulator vault.
- Validate active note search on iPhone and iPad simulator.
- Validate macOS app manually or through the existing macOS verification path.

Verification gate:

- Capture evidence for:
  - search field visible
  - multiple highlighted matches
  - current match distinction
  - navigation to an offscreen match
  - editing while search remains active

## Testing Plan

Automated tests:

- Pure matching helper tests.
- State repair tests after text edits, if the selected match preservation logic is non-trivial.
- Focused attributed-text tests if search highlighting is factored into a helper.

Manual and UI validation:

- Search a normal paragraph.
- Search headings.
- Search list and todo text, including wrapped lines.
- Search text inside links, verifying title-only link rendering remains usable.
- Search terms adjacent to hidden markdown syntax.
- Search while the keyboard is visible on iPhone.
- Search on iPad regular-width editor layout.
- Search on macOS.

## Edge Cases

- Empty note.
- Empty query.
- Query with only whitespace.
- Query longer than note content.
- Multiple adjacent matches.
- Matches before and after an edit.
- Deleting the current match while search is active.
- Pasting large text while search is active.
- Query matching hidden markdown syntax. Recommendation: first version searches backing markdown text, not only rendered visible text. Revisit visible-only search if hidden syntax results feel wrong.
- Case folding for accented characters. Recommendation: start with `.caseInsensitive`; add `.diacriticInsensitive` only if desired after testing.

## Non-Goals

- Vault-wide search.
- FTS indexing.
- Search result snippets.
- Replace-in-note.
- Regex search.
- Whole-word search.
- Persistent search history.
- Search across multiple open editor windows.
- Scroll-to-heading from vault search results.

## Open Decisions

1. Current match behavior: should navigating select the text range in the editor, or only scroll and visually emphasize it while keeping focus in the search field?
2. Matching source: should first version search backing markdown, rendered visible text, or backing markdown with hidden syntax filtered out?

## Recommendation

Implement backing-text search first, with a shared SwiftUI find bar and platform-specific TextKit highlight/navigation adapters. This is the shortest path to a useful feature and preserves the current editor architecture. Defer visible-text-only matching and replace-in-note until real usage shows they are needed.

## Implementation Notes

- Added shared active-note matching with case-insensitive, literal, non-overlapping UTF-16 `NSRange` matches.
- Added `Search in Note` to the iOS/iPadOS and macOS editor More actions menu before `Delete Note`.
- Added `Command-F` through editor/app command notification wiring.
- Added the right-aligned find bar with a 44-point, native-glass pill query field, embedded previous/next arrows, separate close button, and arrow-key handling while focused.
- Added TextKit controller support for match status, navigation, selection, scrolling, and iOS visual highlight overlays.
- iOS visual validation confirmed menu placement, find bar placement, and yellow highlights on the matching terms in `Shopping List`.

## Verification Log

- `flowdeck build` against the saved iOS simulator config: passed.
- `flowdeck test --only EditorFindTests`: passed, 7/7 tests.
- `flowdeck test --only TextKit2EditorLifecycleTests`: 16/17 passed; `pageMentionSuggestionRowsKeepHorizontalInsetInsidePopover()` failed. This is in the pre-existing page-mention suggestion path and was not changed for active-note search.
- Isolated simulator used for manual validation: `06674247-EF2E-480E-B034-86070AC8C852`.
- Vault seeded with `.maestro/seed-vault.sh 06674247-EF2E-480E-B034-86070AC8C852`.
- Screenshots captured under `.codex/evidence/active-note-search/`.
