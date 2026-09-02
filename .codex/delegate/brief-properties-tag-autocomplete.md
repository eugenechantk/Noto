# Delegation Brief: Properties tag autocomplete + normalization + template-on-add (Step 3)

## Goal
Make adding/editing a note's tags in the Properties editor (1) autocomplete
against known tags, (2) normalize every tag to the dash-delimited form, and
(3) when a tag that has a content template is newly added to a note, append that
template to the end of the note body — once (idempotent). Applies to the note's
frontmatter `tags:` field. iOS gets a live suggestion dropdown; macOS gets
normalization + template-on-add (dropdown optional).

## Context (you have none of this session's context)
- `TagController` (app target, `Noto/Storage/TagController.swift`, `@MainActor
  @Observable`) is already injected into the SwiftUI environment via
  `.environment(tagController)` in `Noto/NotoApp.swift`. Read it in views with
  `@Environment(TagController.self) private var tagController`.
  Relevant methods:
  - `suggestions(matching: String) -> [TagName]` (prefix then substring, capped 10)
  - `definition(for: TagName) -> TagDefinition?`
  - `applyTemplate(for: TagName, to content: String) -> String` (no-op if no
    definition or empty template; idempotent via a hidden marker)
  - `@discardableResult save(_ TagDefinition) -> TagDefinition` (persists registry)
  - `nonisolated static func tagNames(inFrontmatterOf:) -> [TagName]`
- `TagName` (package `NotoTags`): `init?(_ String)` normalizes (lowercase,
  spaces/underscores→`-`, strip leading `#`, `[a-z0-9-]` only, collapse dashes);
  `rawValue` is the normalized string; `static func normalize(_:) -> String`.
- `TagDefinition` has `name: TagName`, `template: String`.
- Tag members are stored in frontmatter as an inline list; parse/serialize with
  `NotePropertyClassifier.parseTags(_ String) -> [String]` and
  `serializeTags(_ [String]) -> String` (from package `NotoVault`).
- Editors write content through `session.applyExternalContentEdit(_ String)`
  (`NoteEditorSession`), which persists synchronously. Frontmatter edits use
  `EditableFrontmatterDocument.updatingField(key:value:in:) -> String`
  (`Noto/Editor/EditableFrontmatter.swift`).
- The two property editors:
  - iOS/iPad: `Noto/Views/iOS/PropertiesSheet.swift` — horizontal chip editor for
    tags (`tagsValue`, `inlineTagField`, `beginTagEdit`, `commitInlineEdit`,
    `editingTagMembers`, `draft`). Tags commit through `commitInlineEdit()` which
    builds `members` and calls `updateField(key, serializeTags(members))`.
  - macOS: `Noto/Views/macOS/MacPropertiesForm.swift` — a comma-separated
    `TextField` (`tagsBinding`), committed in `commit(_ key:)` which splits on
    "," and calls `updateField(key, serializeTags(members))`.

## Constraints
- Import `NotoTags` (and keep `NotoVault`) in any file that references `TagName`.
- Pure helpers you add that are called off the main actor must be `nonisolated`.
  (Not expected here — all this runs on the main actor in views — but keep any
  helper on `TagController` `@MainActor` unless it touches no state.)
- Do NOT modify `Packages/NotoTags/`. Do NOT change the search UI (that's Step 4).
- Preserve all existing Properties behavior (other field kinds, dates, add/delete).
- `os_log`/`Logger`, no `print`. Match existing SwiftUI style in each file.

## Spec

### A. Shared commit logic — one place both editors call
Add a `@MainActor` method to `TagController`:
```
/// Writes the given tag members to the note's `tags` frontmatter (normalized,
/// deduped, order-preserving), then appends the content template for any tag
/// that is newly added (not in `previous`) and has a non-empty template.
/// Returns the normalized members actually written.
@discardableResult
func commitTags(_ rawMembers: [String], previous: [TagName], frontmatterKey: String, session: NoteEditorSession) -> [TagName]
```
Algorithm:
1. Map each raw member through `TagName(_:)`, drop nils, dedupe preserving order → `newTags`.
2. Write frontmatter:
   `session.applyExternalContentEdit(EditableFrontmatterDocument.updatingField(key: frontmatterKey, value: NotePropertyClassifier.serializeTags(newTags.map(\.rawValue)), in: session.content))`.
3. For each tag in `newTags` where `!previous.contains(tag)`:
   - lazily ensure it exists in the registry (call `save` only if you also want to
     persist a fresh empty definition; simplest: if `definition(for: tag) == nil`,
     do nothing here — Step 2's membership scan/registry already lazily registers;
     do NOT create empty defs on every keystroke).
   - if `applyTemplate(for: tag, to: session.content)` differs from current
     content, `session.applyExternalContentEdit(...)` with the result. This appends
     the template once (the applier is idempotent).
4. Return `newTags`.

Note: `NoteEditorSession` is in the app target; `TagController` may reference it.
If that creates an import/knowledge coupling you dislike, instead return a small
result struct and let the caller apply edits — but the single-call version is
preferred for parity.

### B. iOS — `PropertiesSheet.swift`
1. Add `@Environment(TagController.self) private var tagController`.
2. Route the tag commit through the shared logic: in `commitInlineEdit()` for the
   tags branch, compute `previous = NotePropertyClassifier.parseTags(oldValue).compactMap(TagName.init)`
   and, after building `members`, call
   `tagController.commitTags(members, previous: previous, frontmatterKey: key, session: session)`
   instead of the direct `updateField(key, serializeTags(members))`. Keep the rest
   of the inline-edit state machine intact.
3. Live suggestions while editing a tag member: when `editingTagIndex != nil` and
   `draft` is non-empty, show `tagController.suggestions(matching: draft)` as a
   small floating list just below the inline tag field (reuse `TagChip` for the
   rows / the existing suggestion-list visual language; cap ~6 visible). Tapping a
   suggestion sets `draft = suggestion.rawValue` and calls `commitInlineEdit()`.
   Give the list `accessibilityIdentifier("tag_suggestion_list")` and each row
   `accessibilityIdentifier("tag_suggestion_\(index)")`. If no matches, show nothing.
4. On commit, the value is normalized by the shared logic — the chip re-renders in
   dash form automatically.

### C. macOS — `MacPropertiesForm.swift`
1. Add `@Environment(TagController.self) private var tagController`.
2. In `commit(_ key:)` tags branch, compute `previous` from the field's prior
   value and call `tagController.commitTags(members, previous:, frontmatterKey: key,
   session: session)` instead of the direct `updateField`. This gives macOS
   normalization + template-on-add parity. A live dropdown is optional for v1 —
   skip it if it complicates the native `Form` field; normalization + template are
   the required parity.

## Verification
- `flowdeck build` (iOS) and macOS compile (the parent runs these).
- Add a Swift Testing test in `NotoTests` for `commitTags` logic if feasible with a
  constructible `NoteEditorSession`; if the session isn't unit-constructible, add a
  pure test for the normalize+dedupe+template-append sequence at the string level
  instead (e.g. verify serialized frontmatter value and that the body gains the
  template exactly once when the same tag is committed twice). Import `NotoTags`.
- The parent will do simulator visual verification (add a tag → see suggestions →
  template appended once).

## Definition of done
- [ ] `TagController.commitTags(...)` implemented per algorithm.
- [ ] iOS Properties: `#`/text suggestions dropdown + normalized commit +
      template-on-add, wired through `commitTags`.
- [ ] macOS Properties: normalized commit + template-on-add via `commitTags`.
- [ ] A test covering normalize+dedupe+idempotent-template-append; imports NotoTags.
- [ ] Everything compiles; existing Properties behavior preserved; no edits under
      `Packages/NotoTags/`.

## Report back
Files changed (created/edited), the `commitTags` signature you settled on, whether
the macOS dropdown was included or deferred, and your test approach + result.
