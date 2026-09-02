# Delegation Brief: `#` tag search in the search sheet (Step 4)

## Goal
When the user types `#` in the search bar, enter "tag mode": show a strip of
matching tag suggestions above the search dock, and when the query names a known
tag, list the notes that have that tag (instead of full-text results). Works on
iOS and macOS. Dash-delimited tag names (e.g. `#podcast-script`).

## Context (you have none of this session's context)
- Search UI is `NoteSearchSheet` in `Noto/Views/NoteListView.swift` (struct at
  ~line 2122). Key existing state: `query` (~2134), `scope` (~2135),
  `results: [NoteSearchResult]` (~2136), `recentNotes: [NoteSearchResult]` (~2137),
  `trimmedQuery` (~2152). iOS layout: `iosSearchView` (~2205), results list
  `iosResultsScroll` (~2224) rendering `NotoSearchRowV2` rows, bottom controls
  `iosBottomControls` (~2289) containing `iosSegmentedControl` + `iosSearchDock`
  (the text field, ~2297/2336). macOS uses `macOSSearchPanel` / `macOSSearchControls`.
  Search is debounced via `scheduleSearch()` (~2798).
- `NoteSearchResult` (struct ~2051): `{ id, note: MarkdownNote, store:
  MarkdownNoteStore, relativePath, title, breadcrumb, snippet, kind }`.
- How to build a `NoteSearchResult` from a vault-relative path (copy this pattern
  from `loadRecentNotes` ~2920): use
  `NoteRepository(directoryURL: rootURL, vaultRootURL: rootURL)
   .note(atVaultRelativePath: relPath)` → `MarkdownNote(record:)`; build a per-note
  `MarkdownNoteStore(directoryURL: fileURL.deletingLastPathComponent(),
   vaultRootURL: rootURL, autoload: false, directoryLoader: rootStore.directoryLoader)`.
  `rootURL = rootStore.vaultRootURL`.
- `TagController` is in the SwiftUI environment (`@Environment(TagController.self)`).
  Methods: `suggestions(matching: String) -> [TagName]`,
  `notes(withTag: TagName) -> [String]` (returns vault-relative paths — the SAME
  identifier shape as `NoteSearchResult.relativePath`), `count(for:) -> Int`,
  `allTagNames() -> [TagName]`.
- `TagName` (package `NotoTags`): `init?(_:)`, `static normalize(_:) -> String`,
  `rawValue`. `TagChip` view already exists (in `PropertiesSheet.swift`, `struct
  TagChip`) — reuse it for suggestion pills.

## Constraints
- Import `NotoTags` in `NoteListView.swift` (and keep existing imports).
- Do NOT change existing full-text search behavior when NOT in tag mode.
- Do NOT modify `Packages/NotoTags/`, the Properties editors, or Settings.
- Preserve existing accessibility identifiers; add new ones as specified.
- `nonisolated` for any pure static helper you call off the main actor.

## Spec — interaction model (query string IS the state; no extra token state)
Add these computed helpers to `NoteSearchSheet`:
- `isTagMode: Bool` = `trimmedQuery.hasPrefix("#")`.
- `tagFragment: String` = `TagName.normalize(String(trimmedQuery.dropFirst()))`
  (normalizes everything after the leading `#`).
- `tagSuggestions: [TagName]` = `isTagMode ? tagController.suggestions(matching:
  tagFragment) : []`.
- `resolvedTag: TagName?` = `TagName(tagFragment)` if it exactly matches a known
  tag name (`tagController.allTagNames().contains`), else `nil`.

Behavior:
1. **Suggestion strip** — when `isTagMode`, render a single horizontally
   scrolling row of `TagChip`s (one per `tagSuggestions`, cap ~10) directly ABOVE
   the search dock (inside `iosBottomControls`, above `iosSearchDock`; on macOS the
   equivalent controls area). Each chip shows `#<name>` and a small note count
   (`tagController.count(for:)`). Tapping a chip sets `query = "#" + name.rawValue`.
   Give the strip `accessibilityIdentifier("tag_search_suggestions")` and each chip
   `accessibilityIdentifier("tag_search_suggestion_\(index)")`. Hide the normal
   scope segmented control while in tag mode.
2. **Results** — when `isTagMode`:
   - if `resolvedTag != nil`: results list shows the notes for that tag —
     `tagController.notes(withTag: resolvedTag!)` resolved to `[NoteSearchResult]`
     via the `loadRecentNotes` pattern above, sorted by `note.modifiedDate`
     descending. Render with the existing `NotoSearchRowV2` rows. Section title
     "Tagged #<name>".
   - else (fragment doesn't fully match yet): show ONLY the suggestion strip with
     an empty results area (a subtle hint like "Pick a tag" is fine). Do not run
     the full-text engine in tag mode.
   - Do the note-resolution off the main thread (Task.detached like
     `loadRecentNotes`), publish results to a new `@State private var tagResults:
     [NoteSearchResult] = []`. Recompute when `query` changes (extend the existing
     `.onChange(of: query)` / `scheduleSearch` path: if `isTagMode`, run the tag
     resolver instead of `scheduleSearch`).
3. When `query` does NOT start with `#`, everything behaves exactly as today.
4. Selecting a result calls the existing `onSelect(result)` + `closeSearch()`.

## Verification
- `flowdeck build` (iOS) + macOS compile — parent runs these.
- Add a lightweight Swift Testing test (in `NotoTests`, `import NotoTags`) for any
  pure helper you extract (e.g. a function mapping `(trimmedQuery) ->
  (isTagMode, tagFragment)`), if you factor one out. UI itself is verified by the
  parent in the simulator.

## Definition of done
- [ ] Typing `#` shows a tag suggestion strip above the search dock (iOS + macOS).
- [ ] Typing/selecting a known tag lists that tag's notes (recency-sorted) using
      existing row views; non-tag queries are unchanged.
- [ ] Tag resolution runs off the main thread; new `tagResults` state.
- [ ] Compiles on both platforms; no edits to NotoTags/Properties/Settings.

## Report back
Files changed, the helpers/state you added to `NoteSearchSheet`, how you handled
the macOS controls area, and whether you extracted a testable helper.
