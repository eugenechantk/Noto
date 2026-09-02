# Delegation Brief: Settings tag list + tag detail editor (Step 5)

## Goal
Add a "Tags" section to Settings that lists every known tag (name + note count)
and lets the user edit a tag's **content template** and **delete** a tag
definition. This is where a tag gets the template that (from Step 3) auto-appends
to a note's body when the tag is added. iOS + macOS. Tag RENAME is intentionally
OUT OF SCOPE for this step.

## Context (you have none of this session's context)
- `SettingsView` (`Noto/Views/SettingsView.swift`) is a SwiftUI `List` of
  `Section`s. It's presented at 4 sites: 3 in-app sheets in
  `Noto/Views/NoteListView.swift` (which ARE inside the app environment that has
  `TagController` injected) and the macOS `Settings { }` scene in
  `Noto/NotoApp.swift` (~line 237) which is a SEPARATE scene WITHOUT
  `TagController` in its environment.
- `TagController` (`@MainActor @Observable`, `Noto/Storage/TagController.swift`) is
  injected via `.environment(tagController)` in `MainAppView` only. Methods:
  `registry.allDefinitions() -> [TagDefinition]` (sorted), `count(for: TagName) ->
  Int`, `definition(for:) -> TagDefinition?`, `@discardableResult save(_
  TagDefinition) -> TagDefinition` (persists registry to disk), `remove(_ TagName)`
  (persists). `TagDefinition`: `{ name: TagName, template: String, createdAt,
  modifiedAt }`. `TagName.rawValue` is the dash-delimited string.
- Sheet header convention (house HIG): paired circular ✕/✓ buttons via
  `SheetCircleButton` (`Noto/Views/Shared/SheetCircleButton.swift`) — orange
  confirm. But for an auto-committing editor a single ✕ (close = confirm) is the
  established pattern (see `PropertiesSheet` header). Follow whichever matches the
  editor's commit model you choose; prefer explicit Save for the template editor.
- `TagChip` view exists in `Noto/Views/iOS/PropertiesSheet.swift`.

## Constraints — environment safety (IMPORTANT)
- In `SettingsView`, read the controller as an OPTIONAL to avoid crashing the
  macOS `Settings` scene that lacks it:
  `@Environment(TagController.self) private var tagController: TagController?`
  Render the Tags section ONLY `if let tagController`.
- ALSO make it work from the macOS `Settings` scene: in `Noto/NotoApp.swift` at the
  `Settings { SettingsView(...) }` scene (~line 237), when `locationManager.vaultURL`
  is non-nil, construct a `TagController(vaultURL: url)` and inject it with
  `.environment(...)`, calling `.load()` and `.rebuildMembership()` (e.g. via a
  small wrapper view with `@State` + `.task`) so macOS ⌘, Settings can manage tags.
  Do not construct one when there's no vault.
- Import `NotoTags` where `TagName`/`TagDefinition` are referenced.
- Do NOT modify `Packages/NotoTags/`, the search UI, or the Properties editors.
- Do NOT implement tag rename in this step. The name is shown read-only in the
  detail editor (display only).
- `os_log`/`Logger`, no `print`. Match existing `SettingsView` styling
  (`AppTheme` colors, `Section`, `Label`, accessibility identifiers).

## Spec

### A. Tags section in `SettingsView`
Add a `Section("Tags")` (only when `tagController != nil`):
- One row per `tagController.registry.allDefinitions()`:
  `#<name>` (leading `tag` glyph) + a trailing note-count caption
  (`tagController.count(for: def.name)`), a chevron. Tapping opens the Tag Detail
  editor (sheet on iOS, could be a sheet or navigation on macOS — a sheet is fine
  for both). Row a11y id `tag_row_<name.rawValue>`.
- If there are no definitions, show a subtle placeholder row ("No tags yet — add
  tags to a note to see them here.").
- Section a11y id `settings_tags_section`.

### B. Tag Detail editor (new view, e.g. `Noto/Views/TagDetailSheet.swift`)
- Input: a `TagDefinition` (or its `TagName`) + the `TagController`.
- Header: title `#<name>`; a Save (✓) and Cancel (✕) using `SheetCircleButton`
  (orange confirm), OR a Done button — explicit save since the template is
  free-form multiline.
- Body:
  - Read-only name display (`#<name>`) with a caption "Tag name" (editing/rename is
    a future step).
  - A multiline template editor: a `TextEditor` bound to a `@State template: String`
    seeded from `definition.template`, labeled "Content template", with helper text
    "Added to the end of a note when this tag is added." a11y id
    `tag_template_editor`.
  - A destructive "Delete Tag" button at the bottom (confirmation dialog): calls
    `tagController.remove(def.name)` and dismisses. a11y id `delete_tag_button`.
- Save: `tagController.save(TagDefinition(name: def.name, template: template,
  createdAt: def.createdAt, modifiedAt: Date()))` then dismiss. (Preserve
  createdAt.)
- a11y id `tag_detail_sheet`.

### C. Wire it
- iOS/macOS: present the Tag Detail as a `.sheet` from the tapped Tags row, using
  `@State private var editingTag: TagDefinition?` (`TagDefinition` is
  `Identifiable` by `name`).

## Verification
- `flowdeck build` (iOS) + macOS compile — parent runs these; the macOS build check
  is important because of the Settings-scene environment injection.
- Add a Swift Testing test only if you extract pure logic; the UI + persistence are
  verified by the parent in the simulator (edit a template → reopen → persisted).

## Definition of done
- [ ] Settings shows a Tags section listing definitions with note counts (only when
      a `TagController` is present).
- [ ] Tag Detail editor edits + saves the template (persists via `save`) and can
      delete a tag (via `remove`), with confirmation.
- [ ] macOS `Settings` scene injects a `TagController` (when a vault exists) so tag
      editing works there; no crash when no controller/vault.
- [ ] Compiles iOS + macOS; no edits to NotoTags/search/Properties; no rename.

## Report back
Files changed (created/edited), how you wrapped the macOS Settings-scene controller
injection, and the Tag Detail commit model you chose (explicit Save vs auto-commit).
