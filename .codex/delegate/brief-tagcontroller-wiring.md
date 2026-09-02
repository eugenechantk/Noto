# Delegation Brief: TagController + Xcode wiring (Step 2 of the Tag System)

## Goal
Make the new `NotoTags` package usable by the app: (1) link it into the Xcode
project, (2) add an app-target `TagController` that owns the loaded tag registry
and a tag→notes membership index (seeded by scanning the vault's frontmatter),
and (3) inject it into the SwiftUI environment so later UI steps can read it.
The app must build and existing tests must still pass.

## Context (you have none of this session's context)
Noto is a universal iOS+macOS SwiftUI note app. `Packages/NotoTags` was just
created (Step 1) and is fully unit-tested — DO NOT modify it. It exposes:
`TagName` (dash-delimited, `init?(_:)`, `normalize`), `TagDefinition`
(`name/template/createdAt/modifiedAt`), `TagRegistry` (`definition(for:)`,
`allDefinitions()`, `upsert`, `remove`, `ensure(_:now:)`), `TagRegistryStore`
(`load(from:) throws`, `save(_:to:) throws`), `TagMembershipIndex`
(`init(records: [NoteTagRecord])`, `notes(withTag:)`, `allTags()`, `count(for:)`,
with `NoteTagRecord{noteID:String, tags:[TagName]}`), and `TagTemplateApplier`
(`apply(template:forTag:to:)`, `isApplied(...)`).

Tag *membership* lives in each note's frontmatter as `tags: [a, b]`. The app
already parses that: `NotePropertyClassifier.parseTags(_:) -> [String]` (in the
`NotoVault` package) and `EditableFrontmatterDocument` (in
`Noto/Editor/EditableFrontmatter.swift`) which reads a field's value from a
markdown string. The tag registry (definitions) is NEW and persists to
`<vaultURL>/.noto/tags.json`.

## Constraints
- **Only the app target `Noto` needs the package.** Mirror EXACTLY how the
  existing local package `NotoVault` is wired in `Noto.xcodeproj/project.pbxproj`
  — replicate each of NotoVault's entries for `NotoTags` (relativePath
  `Packages/NotoTags`): the `XCLocalSwiftPackageReference`, the
  `XCSwiftPackageProductDependency` productRef, the `packageProductDependencies`
  entry on the `Noto` target, the `PBXBuildFile` (product "NotoTags in
  Frameworks"), and its entry in that target's Frameworks build phase. Use fresh
  unique 24-char hex IDs that don't collide with existing ones. Do not remove or
  reorder unrelated entries.
- Do NOT modify anything under `Packages/NotoTags/`. Do not touch the search
  (`NotoSearch`) package or its FTS schema.
- `os_log`/`Logger` for logging (no `print`). `@MainActor @Observable` for the
  controller (match `VaultController` in `Noto/Storage/VaultController.swift`).
- Swift Testing (`import Testing`, `@Test`, `#expect`) for the new test, with a
  test-index comment block at the top + a one-line description per `@Test`.

## Spec

### 1. `TagController` — `Noto/Storage/TagController.swift`
`@MainActor @Observable final class TagController`. Owns:
- `let vaultURL: URL`
- the loaded `TagRegistry` (private, `private(set)` accessors)
- a `TagMembershipIndex` (starts empty)
- a `TagRegistryStore`

Registry file path: `vaultURL.appendingPathComponent(".noto/tags.json")`.

Public API (the facade later UI reads):
- `func load()` — load the registry from disk on a background task (do not block
  the main thread); publish results on the main actor. Missing file → empty
  registry (the store already handles this).
- `func rebuildMembership()` — on a background task, enumerate the vault's `.md`
  files, extract each note's frontmatter tags, build `[NoteTagRecord]`
  (noteID = the note's file path relative to the vault, or its frontmatter id if
  present — pick one and be consistent), construct a new `TagMembershipIndex`,
  and **lazily register** any tag not already in the registry via
  `registry.ensure(_:now:)`, then persist the registry if it changed. Publish the
  new index + registry on the main actor.
- `func allTagNames() -> [TagName]` — union of registry names and membership
  tags, sorted, deduped.
- `func suggestions(matching fragment: String) -> [TagName]` — normalize the
  fragment through `TagName.normalize`; return tag names that contain it
  (prefix matches first, then substring), capped at ~10. Empty fragment → all
  names (capped).
- `func definition(for name: TagName) -> TagDefinition?`
- `func notes(withTag name: TagName) -> [String]` (from the membership index)
- `func count(for name: TagName) -> Int`
- `@discardableResult func save(_ definition: TagDefinition)` — upsert into the
  registry (bump `modifiedAt`) and persist to disk (background write).
- `func remove(_ name: TagName)` — remove from registry + persist. (Does not
  touch notes' frontmatter — that's a later step.)
- `func applyTemplate(for name: TagName, to content: String) -> String` — if a
  definition exists with a non-empty template, return
  `TagTemplateApplier.apply(...)`, else return content unchanged.

### 2. Frontmatter tag extraction — a pure, testable helper
Add a `static func tagNames(inFrontmatterOf markdown: String) -> [TagName]` (put
it on `TagController` or a small helper type). Algorithm: read the `tags` field
value from the markdown via `EditableFrontmatterDocument`, split with
`NotePropertyClassifier.parseTags`, map each through `TagName(_:)`, drop nils.
This is the one piece we unit-test directly (file I/O is not unit-tested).

For enumerating `.md` files, reuse an existing vault enumerator pattern (see
`Packages/NotoVault/.../NoteRepository.swift` ~line 72 or
`Packages/NotoSearch/.../MarkdownSearchIndexer.swift` ~line 202) — a
`FileManager.default.enumerator` over `vaultURL` filtering `pathExtension == "md"`,
skipping hidden dirs (including `.noto`). Read each file with `String(contentsOf:)`;
tolerate/skip unreadable files.

### 3. Wire into the app — `Noto/NotoApp.swift`, `MainAppView` (~line 378)
- Add `@State private var tagController: TagController` and initialize it in
  `MainAppView.init` (alongside `_store`, ~line 405):
  `_tagController = State(wrappedValue: TagController(vaultURL: vaultURL))`.
- In `body`, inject it into the environment on the `VaultWorkspaceView` alongside
  the existing `.environmentObject(chatStore)`:
  `.environment(tagController)`.
- In the existing `.task { ... }` block (~line 432), after `store.loadItemsInBackground()`,
  call `tagController.load()` then `tagController.rebuildMembership()`.
- In `.onChange(of: fileWatcher.changeCount)` (~line 464), also call
  `tagController.rebuildMembership()` so tag membership tracks external edits.
- Do not change unrelated behavior in this file.

## Verification (run what you can; the parent will run the authoritative app build)
- `cd Packages/NotoTags && swift test` — must still pass (proves you didn't break
  the package; you shouldn't have touched it).
- Build the app if your environment can:
  `xcodebuild -project Noto.xcodeproj -scheme Noto -destination 'generic/platform=iOS Simulator' -configuration Debug build`
  (a clean compile is the bar; if the sandbox can't run xcodebuild, say so and
  ensure the Swift is correct by inspection — the parent will run the build).
- The new frontmatter-extraction unit test in `NotoTests` must pass logically
  (cover: inline `tags: [a, b-c]`, denormalized `tags: [A, "B C"]` →
  `[a, b-c]`, missing tags field → empty, no frontmatter → empty).

## Definition of done
- [ ] `Noto.xcodeproj` links `NotoTags` into the `Noto` target (mirrors NotoVault).
- [ ] `Noto/Storage/TagController.swift` implements the full facade above.
- [ ] Pure `tagNames(inFrontmatterOf:)` helper + a Swift Testing test in `NotoTests`.
- [ ] `MainAppView` constructs, loads, membership-scans, and `.environment`-injects
      `TagController`; refreshes membership on file-watcher changes.
- [ ] `NotoTags` package tests still pass; no edits under `Packages/NotoTags/`.
- [ ] App compiles with `import NotoTags` in use.

## Report back
Files changed (grouped created/edited), exactly which pbxproj entries you added
(with their new IDs), whether you could run xcodebuild and its result, and the
NotoTags `swift test` result.
