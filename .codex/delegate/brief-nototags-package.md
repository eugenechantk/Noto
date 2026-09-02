# Delegation Brief: NotoTags Swift package (Step 1 of the Tag System)

## Goal
Create a new **UI-free, independently testable** Swift package `NotoTags` under
`Packages/NotoTags/` that owns all tag *definition* logic for the Noto note app:
tag-name normalization, the tag registry (name + content template), JSON
persistence, a tag→notes membership index, and idempotent template application.
No UIKit/SwiftUI/AppKit. Everything validated by `swift test`.

## Context you need (Codex has none of this session's context)
Noto is a markdown note app. Every note is a `.md` file with YAML frontmatter.
A note's tags are stored in its frontmatter as a `tags:` inline flow list, e.g.:

```
---
id: 550e8400-...
created: 2026-01-01T00:00:00Z
updated: 2026-01-02T00:00:00Z
tags: [podcast-script, idea]
---
# My note
body...
```

This package does NOT read/write note files' membership directly at runtime for
persistence — membership lives in each note's frontmatter (owned elsewhere). This
package owns the **registry of tag definitions** and **pure helpers**.

## Constraints
- `Package.swift`: `swift-tools-version: 5.10`, `platforms: [.iOS(.v17), .macOS(.v14)]`,
  one library target `NotoTags` + a test target `NotoTagsTests`. Match the shape of
  `Packages/NotoVault/Package.swift` exactly (no external dependencies).
- **Tests use the Swift Testing framework** (`import Testing`, `@Test`, `#expect`) —
  NOT XCTest. Match the existing style in `Packages/NotoVault/Tests`.
- Put a **test-case index comment block at the top of each test file** and a
  one-line description above each `@Test` (house convention).
- Pure Foundation only. All types `Sendable` where reasonable. Public API `public`.
- Do NOT modify any files outside `Packages/NotoTags/`. This step is the package only;
  app wiring is a later step.

## Spec — types and behavior

### 1. `TagName` (value type, the normalization chokepoint)
A validated, dash-delimited tag name. Normalize on creation:
- lowercase; trim whitespace
- strip a single leading `#` if present
- replace any run of whitespace or `_` with a single `-`
- drop any character not in `[a-z0-9-]`
- collapse repeated `-` into one; trim leading/trailing `-`
Examples: `"Podcast Script"` → `podcast-script`; `"#Idea"` → `idea`;
`"my__cool  tag!"` → `my-cool-tag`; `"---"` → invalid (empty after normalize).

Interface (spec, implement as you see fit):
```
public struct TagName: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let rawValue: String              // the normalized value
    public init?(_ input: String)            // nil if empty after normalization
    public static func normalize(_ input: String) -> String  // exposed for callers
}
```
Codable should encode/decode as the plain string (single value), not an object.

### 2. `TagDefinition`
```
public struct TagDefinition: Codable, Sendable, Equatable, Identifiable {
    public var id: TagName { name }
    public let name: TagName
    public var template: String              // markdown appended to note body; may be ""
    public var createdAt: Date
    public var modifiedAt: Date
}
```
Design so more per-tag properties can be added later without breaking JSON
(decode should tolerate missing optional future keys).

### 3. `TagRegistry`
An in-memory collection of `TagDefinition` keyed by `TagName`. Provide:
- `definition(for: TagName) -> TagDefinition?`
- `allDefinitions() -> [TagDefinition]` (stable sort by name)
- `upsert(_ def: TagDefinition)` / mutating add-or-replace
- `remove(_ name: TagName)`
- `ensure(_ name: TagName, now: Date) -> TagDefinition` — lazy registration: returns
  existing, or creates one with empty template + timestamps and inserts it.
Codable as `{ "version": 1, "tags": [ {name, template, createdAt, modifiedAt}, ... ] }`.

### 4. `TagRegistryStore`
Loads/saves a `TagRegistry` as JSON at a caller-provided file URL (the app will pass
`<vault>/.noto/tags.json`; the package must NOT hardcode that path). Behavior:
- `load(from: URL) throws -> TagRegistry` — if the file does not exist, return an
  **empty** registry (do not throw). Tolerate an empty/whitespace file → empty registry.
- `save(_ registry: TagRegistry, to: URL) throws` — create intermediate directories
  (e.g. `.noto/`) if missing; write atomically; pretty-printed, stable key order,
  ISO8601 dates. Round-trip must be lossless.
Keep file I/O injectable enough to unit-test against a temp directory.

### 5. `TagMembershipIndex`
Builds a `TagName -> [String]` map (tag → note identifiers) from parsed note tags.
This package should NOT do filesystem scanning itself; instead accept already-parsed
input so it stays pure and testable:
```
public struct NoteTagRecord: Sendable, Equatable { public let noteID: String; public let tags: [TagName] }
public struct TagMembershipIndex: Sendable {
    public init(records: [NoteTagRecord])
    public func notes(withTag: TagName) -> [String]     // stable order
    public func allTags() -> [TagName]                  // sorted, deduped
    public func count(for: TagName) -> Int
}
```

### 6. `TagTemplateApplier`
Pure function that appends a tag's template to note **body** text, idempotently.
```
public enum TagTemplateApplier {
    public static func apply(template: String, forTag: TagName, to content: String) -> String
    public static func isApplied(template: String, forTag: TagName, in content: String) -> Bool
}
```
Rules:
- If `template` is empty/whitespace → return content unchanged.
- Idempotency: use a **stable, invisible marker** tied to the tag name so re-applying
  the same tag never duplicates. Suggested marker: an HTML comment line
  `<!-- noto:tag-template:<tagname> -->` emitted immediately before the appended
  template block. `isApplied` checks for that marker. This keeps markdown rendering
  clean and survives round-trips.
- Append at the **end** of the body: ensure exactly one blank line separates existing
  content from the marker+template block; template block ends with a trailing newline.
- `apply` must NOT touch frontmatter — it only appends to the body. (Content passed in
  may include frontmatter; append after everything. Simplest correct behavior: append
  to the end of the whole string. If frontmatter-vs-body splitting is needed, keep it
  minimal and documented.) Prefer: operate on the full content string, append at end.

## Verification (run these; all must pass)
```
cd Packages/NotoTags && swift build && swift test
```
Write thorough `@Test` coverage:
- `TagName`: every normalization rule above + the invalid/empty cases + Codable
  round-trips as a plain string.
- `TagDefinition`/`TagRegistry`: upsert replaces, remove, `ensure` lazy-creates once,
  stable sorted `allDefinitions`, JSON round-trip, tolerant decode of missing future keys.
- `TagRegistryStore`: missing file → empty registry; save creates `.noto/` dir;
  save→load round-trip lossless; empty file → empty registry. Use a temp dir.
- `TagMembershipIndex`: notes(withTag:), allTags dedupe/sort, count, empty input.
- `TagTemplateApplier`: empty template no-op; append once; **apply twice = applied once**
  (idempotent via marker); multiple different tags each appended once; marker detection.

## Definition of done
- [ ] `Packages/NotoTags/` exists with `Package.swift`, `Sources/NotoTags/*`, `Tests/NotoTagsTests/*`.
- [ ] All six types implemented per spec, `public` API, `Sendable`, no UI imports.
- [ ] `swift build` succeeds; `swift test` passes with the coverage listed above.
- [ ] No files changed outside `Packages/NotoTags/`.

## Report back
Files created, full `swift test` output (pass counts), and anything you deviated from
in the spec and why.
