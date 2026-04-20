# Noto — New macOS + iPadOS UI Analysis & Implementation Plan

_Reference: `noto_mac.png` mockup, 2026-04-20. The design applies to **macOS and iPadOS (regular size class)** — both platforms share the same floating-sidebar + full-width editor layout. iPhone and iPad compact size class continue to use the existing drill-in `NavigationStack` flow untouched._

---

## 1. Visual breakdown of the mockup

### 1.1 Window / scene chrome

**macOS**
- Standard **unified title bar** (height ~28pt) with traffic-light controls at top-left.
- A **sidebar-toggle icon** (`sidebar.left` SF Symbol) sits immediately to the right of the traffic lights.
- Window title **"Noto"** is centered in the title bar.
- **No visible toolbar** — no Today button, no Settings gear, no new-note button. These move to menu-bar `Commands`.
- Title bar is transparent / continuous with the sidebar (no hard line).

**iPadOS (regular size class)**
- No traffic lights; instead a floating **navigation bar** with the same centered "Noto" title and a leading sidebar-toggle button.
- Status bar + home indicator respected via safe-area insets (the editor's `.backgroundExtensionEffect()` runs under the nav bar).
- Split-view behavior: `NavigationSplitView` with `.navigationSplitViewStyle(.balanced)` or `.prominentDetail`. On iPad, users also get the built-in edge-swipe gesture to show/hide the sidebar.
- No toolbar buttons in the nav bar chrome itself; commands surface via keyboard shortcuts when a keyboard is attached (`⌘T` today, `⌘,` settings, `⌃⌘S` sidebar toggle) and via menus built with `.commands` that also populate the iPad hardware-keyboard command palette.

**iPhone / iPad compact** — out of scope for this redesign. Keeps existing `NavigationStack` drill-in flow in `FolderContentView`.

### 1.2 Two-pane layout — **floating sidebar, content flows beneath (Liquid Glass)**

Per Apple HIG ([Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars), June 2025 update), Noto uses the modern floating-sidebar pattern:

> _"A sidebar floats above content without being anchored to the edges of the view."_
>
> _"Extend content beneath the sidebar. In iOS, iPadOS, and macOS … sidebars float above content in the **Liquid Glass layer**. To reinforce the separation and floating appearance of the sidebar, extend content beneath it either by letting it horizontally scroll or applying a **background extension view**, which mirrors adjacent content to give the impression of stretching it under the sidebar. For developer guidance, see **backgroundExtensionEffect()**."_

| Pane    | Width  | Treatment                                              |
| ------- | ------ | ------------------------------------------------------ |
| Sidebar | ~256pt | System Liquid Glass material (provided by `NavigationSplitView`) |
| Editor  | full   | Near-black (#0A0A0A), **`.backgroundExtensionEffect()`** applied so content appears to extend beneath the sidebar |

**Key behaviors:**
- No hard divider — the Liquid Glass layer provides separation.
- Toggling the sidebar off (`⌃⌘S`) does not reflow the editor; content stays put, the glass layer disappears.
- Sidebar toggle button in the titlebar is system-provided via `NavigationSplitView`.
- Sidebar icons use the user's **accent color** (HIG: _"sidebar icons use the current accent color… Avoid stylizing your app by specifying a fixed color for all sidebar icons."_).
- On macOS, the sidebar respects the user's General → Sidebar icon size preference (small / medium / large).

**Implementation:** use SwiftUI `.backgroundExtensionEffect()` on the detail view's top-level content (iOS 26 / macOS 26+). Noto's `/ios-design-liquid-glass` skill covers the glass API surface. Do NOT roll a custom `sidebarBackground` color token — the system handles material treatment.

### 1.3 Sidebar contents

- **Search field** at top: pill-shaped, rounded-10pt corners, magnifying glass leading icon, "Search" placeholder in muted gray. Full width of sidebar minus ~12pt side padding.
- **File tree** below the search — a fully expanded outline, not a drill-in Finder-style list. All visible items share the same row height (~24pt) with a single-line label.
- **HIG constraint — 2 levels max**: _"In general, show no more than two levels of hierarchy in a sidebar."_ Noto's vaults are arbitrarily deep. The mockup happens to show 3 nested folder levels; v1 ships with the flat tree (off-spec but matches mockup). If deep-nesting UX becomes an issue, migrate to a 3-column `NavigationSplitView` (sidebar → folder contents → editor), which is what Mail/Notes/Reminders do and what HIG recommends for deep hierarchies.
- **Row anatomy:**
  - **Icon** (16pt, accent-colored per HIG, slightly filled) — either folder-closed, folder-open, or document.
  - **Label** (`.body` text style, 13pt on macOS / iPad, single line, truncated).
  - **Indent** — each level adds ~16pt of left padding. The root is flush-left at ~16pt.
  - **Row height** — macOS ~24pt (pointer device); **iPadOS ~44pt minimum (touch target)**. Switch via `@Environment(\.horizontalSizeClass)` and platform check, not a fixed value.
- **Icon semantics (three distinct states):**
  - Closed folder (child rows not shown below it) — `folder` outline style.
  - Open folder (has expanded children directly below) — `folder` with a partial opening, as shown for the three nested parents.
  - Note file — `doc` outline with a dog-ear fold.
- **No disclosure triangles (chevrons).** Expansion state is conveyed purely by icon change + whether children are visible beneath.
- **No selected-row highlight visible** in the mockup (no row currently has focus styling, though the editor shows a note loaded — implying selection exists but is not painted).

### 1.4 Editor contents

Order from top to bottom:

1. **Note title** — large, bold, wraps to three lines. Looks like ~28pt / SF Pro Display Bold / primaryText color. Acts as the page heading.
2. **Body paragraph** — "What is this that is going to help me do this…" in secondaryText at ~15pt regular.
3. **Horizontal rule** — a thin 1pt separator (matches `AppTheme.separator`).
4. **Heading 2** — "This is heading 2", ~22pt bold, primaryText.
5. **Bulleted list** — outer bullet at ~14pt with 8pt space before bullet glyph and nested children indented further. Bullet glyph is a small filled dot (·/•), not a hyphen.
6. **Heading 3** — "This is heading 3", ~17pt bold.
7. **Body paragraph** — same style as (2).
8. **Word + character counter (status line)** — pinned to the **bottom-right of the editor pane**, rendered in muted gray. Two labels separated by a gap: `"32 words"` then `"1,234 characters"`. Font is small (~11–12pt), muted color (`mutedText`), right-aligned with ~24pt trailing padding and ~16pt bottom padding. It floats over the editor content (the editor scrolls beneath it) and is always visible — not a modal status bar.

Padding: body content starts ~32pt below the window top and is left-aligned with ~56pt left padding. The editor has **one** status element — the counter overlay at bottom-right.

### 1.5 Typography scale — Apple HIG semantic text styles per platform

Reference: [Apple HIG — Typography Specifications](https://developer.apple.com/design/human-interface-guidelines/typography#Specifications). Values below are verbatim from the live HIG (fetched 2026-04-20).

Using Apple's **semantic text styles** (not raw point sizes) is mandatory:
1. **Cross-platform rendering** — `.font(.largeTitle)` auto-resolves to 26pt on macOS and 34pt on iPadOS. SwiftUI handles the platform switch; we don't branch.
2. **Dynamic Type (iOS/iPadOS)** — users adjust text size in Settings; only `preferredFont(forTextStyle:)` / SwiftUI `.font(.title)` respect it. Hard-coded `Font.system(size: 22)` breaks accessibility.
3. **Line height** — Apple bakes the correct leading into each style. Matching by hand is error-prone.

#### macOS built-in text styles (verbatim from HIG)

| Style         | SwiftUI         | AppKit `.textStyle` | Size | Line height | Default weight | Emphasized weight |
| ------------- | --------------- | ------------------- | ---- | ----------- | -------------- | ----------------- |
| Large Title   | `.largeTitle`   | `.largeTitle`       | 26   | 32          | Regular        | Bold              |
| Title 1       | `.title`        | `.title1`           | 22   | 26          | Regular        | Bold              |
| Title 2       | `.title2`       | `.title2`           | 17   | 22          | Regular        | Bold              |
| Title 3       | `.title3`       | `.title3`           | 15   | 20          | Regular        | Semibold          |
| Headline      | `.headline`     | `.headline`         | 13   | 16          | Bold           | Heavy             |
| Body          | `.body`         | `.body`             | 13   | 16          | Regular        | Semibold          |
| Callout       | `.callout`      | `.callout`          | 12   | 15          | Regular        | Semibold          |
| Subheadline   | `.subheadline`  | `.subheadline`      | 11   | 14          | Regular        | Semibold          |
| Footnote      | `.footnote`     | `.footnote`         | 10   | 13          | Regular        | Semibold          |
| Caption 1     | `.caption`      | `.caption1`         | 10   | 13          | Regular        | Medium            |
| Caption 2     | `.caption2`     | `.caption2`         | 10   | 13          | Medium         | Semibold          |

**macOS does not support Dynamic Type** per HIG — these sizes are fixed. macOS does honor System Settings → Appearance → Text Size as a bucketed preference, but there's no sliding scale.

#### iOS / iPadOS Dynamic Type — Large (default size, what most users see)

| Style         | SwiftUI         | UIKit `.textStyle` | Size | Leading | Default weight | Emphasized weight |
| ------------- | --------------- | ------------------ | ---- | ------- | -------------- | ----------------- |
| Large Title   | `.largeTitle`   | `.largeTitle`      | 34   | 41      | Regular        | Bold              |
| Title 1       | `.title`        | `.title1`          | 28   | 34      | Regular        | Bold              |
| Title 2       | `.title2`       | `.title2`          | 22   | 28      | Regular        | Bold              |
| Title 3       | `.title3`       | `.title3`          | 20   | 25      | Regular        | Semibold          |
| Headline      | `.headline`     | `.headline`        | 17   | 22      | Semibold       | Semibold          |
| Body          | `.body`         | `.body`            | 17   | 22      | Regular        | Semibold          |
| Callout       | `.callout`      | `.callout`         | 16   | 21      | Regular        | Semibold          |
| Subheadline   | `.subheadline`  | `.subheadline`     | 15   | 20      | Regular        | Semibold          |
| Footnote      | `.footnote`     | `.footnote`        | 13   | 18      | Regular        | Semibold          |
| Caption 1     | `.caption`      | `.caption1`        | 12   | 16      | Regular        | Semibold          |
| Caption 2     | `.caption2`     | `.caption2`        | 11   | 13      | Regular        | Semibold          |

**iOS/iPadOS supports Dynamic Type** — every size scales across 7 user-selectable levels (xSmall → xxxLarge) plus 5 accessibility levels (AX1 → AX5). The table above is the "Large" default. At xSmall the Large Title drops to 31pt; at xxxLarge it grows to 40pt; at AX5 it reaches 58pt. See the live HIG for the full matrix.

#### Cross-platform delta — why the iPad title looks bigger than Mac

For the same semantic role, iPadOS sizes are roughly **25–35% larger than macOS**:

| Role              | macOS | iPadOS | Delta  |
| ----------------- | ----- | ------ | ------ |
| Large Title       | 26pt  | 34pt   | +31%   |
| Title 1           | 22pt  | 28pt   | +27%   |
| Title 2           | 17pt  | 22pt   | +29%   |
| Body              | 13pt  | 17pt   | +31%   |
| Caption 1         | 10pt  | 12pt   | +20%   |

This is **intentional** per Apple HIG — touch interfaces sit farther from the eye and use-contexts vary. We honor it. The note title in Noto will appear larger and "chunkier" on iPad than on Mac; that's the correct platform-native look. Do not fight this by hard-coding sizes.

Font is **SF Pro** on both platforms (system default). The OS automatically picks SF Pro Display at ≥20pt and SF Pro Text at smaller — no manual selection needed.

**Noto's semantic mapping** — every visual element in the mockup gets an HIG style plus (optional) weight override + color token. Column "mac / iPad size" shows the resulting rendered size on each platform so we know what to expect visually:

| Role in Noto UI              | HIG style      | Weight override | Color token      | mac / iPad size | Where it appears                    |
| ---------------------------- | -------------- | --------------- | ---------------- | --------------- | ----------------------------------- |
| Note title                   | `.largeTitle`  | `.bold`         | `primaryText`    | 26 / 34pt       | Top of editor pane                  |
| H1 (`#`)                     | `.title`       | `.bold`         | `primaryText`    | 22 / 28pt       | Markdown heading level 1            |
| H2 (`##`)                    | `.title`       | `.bold`         | `primaryText`    | 22 / 28pt       | "This is heading 2" in mockup       |
| H3 (`###`)                   | `.title2`      | `.bold`         | `primaryText`    | 17 / 22pt       | "This is heading 3" in mockup       |
| H4 (`####`)                  | `.title3`      | `.semibold`     | `primaryText`    | 15 / 20pt       | Deeper markdown headings            |
| Body paragraph               | `.body`        | default         | `secondaryText`  | 13 / 17pt       | Editor body, bulleted lists         |
| Sidebar row label            | `.body`        | default         | `secondaryText`  | 13 / 17pt       | Folder/note names in sidebar        |
| Search placeholder           | `.body`        | default         | `mutedText`      | 13 / 17pt       | Sidebar search field                |
| Word/char counter            | `.caption`     | default         | `mutedText`      | 10 / 12pt       | Bottom-right of editor pane         |
| Window title ("Noto")        | system default | default         | primary          | system          | Titlebar — handled by system        |

Sizes shown are the **Large (default)** iPadOS values. When iPad users pick a different Dynamic Type size, every row above scales proportionally — which is the whole point of using semantic styles.

> **Mockup calibration note.** The mockup's note title reads closer to ~28pt, which is slightly larger than HIG's Large Title (26pt). Two options: (a) accept 26pt Bold via `.largeTitle.bold()` for HIG compliance, or (b) use a named custom size like `.system(size: 28, weight: .bold)` for the exact visual. **Recommend (a)** — the 2pt difference is imperceptible and accessibility + Dynamic Type are worth the trade. Same logic for "H2" in mockup (~22pt) → `.title` (22pt). The mockup's H3 (~17pt) → `.title2` (17pt). All three map cleanly.

**Implementation token (`AppTheme.TypeScale`):**

```swift
enum TypeScale {
    static let noteTitle: Font     = .largeTitle.bold()
    static let h1: Font            = .title.bold()
    static let h2: Font            = .title.bold()     // same as h1 in HIG, differentiate via weight/color if needed
    static let h3: Font            = .title2.bold()
    static let h4: Font            = .title3.weight(.semibold)
    static let body: Font          = .body
    static let sidebarLabel: Font  = .body
    static let counter: Font       = .caption
}
```

Editor-side (TextKit 2) needs AppKit equivalents — `NSFont.preferredFont(forTextStyle: .largeTitle)` then `NSFontManager.shared.convert(_:toHaveTrait: .boldFontMask)` for weight.

### 1.6 Color system (inferred, maps cleanly to current `AppTheme`)

| Role                   | Current token                | In mockup?            |
| ---------------------- | ---------------------------- | --------------------- |
| Editor bg              | `background` (#0A0A0A)       | Yes — matches         |
| Sidebar bg             | _(needs new token)_          | Slightly lighter      |
| Primary text           | `primaryText` (#E5E5E5)      | Yes                   |
| Secondary/body text    | `secondaryText` (#D4D4D4)    | Yes                   |
| Muted/placeholder      | `mutedText` (#525252)        | Yes                   |
| Divider / hr           | `separator` (#27272A)        | Yes                   |
| Selected row           | `selectedRowBackground`      | Not visibly shown     |

~~One new token needed: `sidebarBackground`~~ — **no longer needed.** Per HIG's June 2025 update, the sidebar uses the system Liquid Glass layer and content flows beneath it via `.backgroundExtensionEffect()`. Don't add a custom sidebar bg color.

---

## 2. Gap analysis — what exists vs. what the mockup demands

### 2.1 What's already there

- `NavigationSplitView` skeleton in `NoteListView` (`os(macOS)` branch).
- `SidebarView` with recursive `SidebarFolderRow` that _can_ show nested content via `DisclosureGroup` — but only on demand.
- `AppTheme` with all the dark colors the mockup uses.
- Block-based TextKit 2 editor (`TextKit2EditorView`) that already styles headings, bullets, todo, code.
- `MarkdownNoteStore` with folder/note CRUD and frontmatter parsing.

### 2.2 What needs to change

| # | Area | Current | Needed for mockup |
| - | ---- | ------- | ----------------- |
| 1 | Window chrome | Standard titlebar with Today + Settings toolbar buttons | Transparent titlebar, centered "Noto" title, only sidebar-toggle visible, Today/Settings moved to menu bar or sidebar |
| 2 | Sidebar style | `List` with `.listStyle(.sidebar)` — shares bg with editor | Distinct sidebar material/bg; no divider with editor |
| 3 | Sidebar top | `HStack` with back-button + new-note plus | `TextField`-based search pill (no back button, no plus) |
| 4 | Sidebar tree | Drill-in folder stack; DisclosureGroup expansion lazy per-folder | Fully expanded tree, all folders & notes visible at their depth from first paint |
| 5 | Folder icons | Same `folder.fill` for closed/open | Three states: closed folder, open folder (has expanded kids), note doc |
| 6 | Disclosure chevrons | Present via `DisclosureGroup` | Hidden — no chevrons; click row to toggle, icon change communicates state |
| 7 | Editor title | Title is derived from first line of markdown, rendered inside the TextKit editor | Title is a distinct, large-bold visual element at the top of the detail view |
| 8 | Horizontal rule | Markdown `---` may or may not be rendered as a styled divider — needs verification | Must render as a 1pt separator line |
| 9 | Nested bullets | Block editor supports `bullet(indent: Int)`; visual indent driven by NSParagraphStyle | Verify visual matches mockup — indent unit and bullet glyph |
| 10 | Typography | Uses SwiftUI defaults + editor-side typography | Audit and lock down a scale: title/h2/h3/body sizes as above |
| 11 | Search | No implementation | Functional filter across all note titles & folder names (minimum), full-text later |
| 12 | Word/char counter | Not present | Live "N words  N characters" overlay pinned to editor's bottom-right |

---

## 3. Implementation plan (phased, test-driven)

Follows `/ios-development` discipline: feature doc → tests → implementation → verification per phase. Each phase is independently shippable.

### 3.0 Platform strategy — shared code for macOS and iPadOS regular

The redesign targets **two presentations of one layout**: macOS windowed and iPadOS in regular size class. Both use `NavigationSplitView`, floating Liquid Glass sidebar, full-width editor, and the same typography scale. The existing iPhone + iPad-compact drill-in flow (`FolderContentView` inside a `NavigationStack`) is untouched.

**What's shared across macOS + iPadOS regular:**

| Component                    | Location                                            | Notes                                  |
| ---------------------------- | --------------------------------------------------- | -------------------------------------- |
| Sidebar tree + search        | `Noto/Views/Shared/NotoSidebarView.swift`           | Branches on `horizontalSizeClass` for row height only |
| `SidebarNode` model + loader | `Packages/NotoVault/…/SidebarTreeLoader.swift`      | Pure logic, platform-agnostic          |
| Editor + title rendering     | `Noto/Editor/TextKit2EditorView.swift` (**reused as-is**) | Already has iOS/macOS internal branches — no rewrite |
| `EditorStatusOverlay`        | `Noto/Views/Shared/EditorStatusOverlay.swift`       | SwiftUI only                           |
| `AppTheme.TypeScale`         | `Noto/Support/AppTheme.swift`                       | Apple semantic text styles — identical on both |
| `WordCounter` logic          | `Packages/NotoVault/…/WordCounter.swift`            | Pure, cross-platform                   |
| `.backgroundExtensionEffect()` on editor root | `Noto/Views/NoteEditorScreen.swift` | iOS 26+ / macOS 26+ API, same call site |

**What stays platform-specific (behind narrow `#if` or environment checks):**

| Concern                 | macOS                                       | iPadOS                                      |
| ----------------------- | ------------------------------------------- | ------------------------------------------- |
| Scene / window          | `WindowGroup` + `.windowStyle(.hiddenTitleBar)` + `SettingsScene` | `WindowGroup` + nav-bar transparency; `sceneTitle("Noto")` |
| Commands surface        | Menu bar via `.commands { CommandMenu … }`  | Hardware-keyboard palette via the same `.commands` modifier |
| Sidebar row height      | 24pt                                        | 44pt (touch)                                |
| Sidebar icon size       | Respects General → Sidebar icon size        | Fixed (no user preference)                  |
| Sidebar show/hide       | `⌃⌘S` + View menu items                     | `⌃⌘S` + built-in edge-swipe gesture         |
| Settings presentation   | `SettingsScene` (`⌘,`)                      | Sheet-presented `SettingsView`              |
| Safe areas              | n/a                                         | Respect status bar / home indicator insets; let extension effect run under nav bar |

**Routing in `NoteListView`:**

```swift
#if os(macOS)
    NotoSplitView(...)                    // always — macOS only has one size class
#elseif os(iOS)
    if horizontalSizeClass == .regular {
        NotoSplitView(...)                // iPad regular → same view as macOS
    } else {
        NavigationStack { FolderContentView(...) }   // iPhone + iPad compact → existing drill-in
    }
#endif
```

`NotoSplitView` is the new shared entry point that composes `NotoSidebarView` + editor + glass extension effect. It replaces the current macOS-only branch.

**Decision log for this strategy:**

- **Why `horizontalSizeClass` over `UIDevice`:** iPad users resize windows in Stage Manager; a 1/3-width iPad window is compact even on a 13" device. Size class adapts; device identity doesn't.
- **Why not unify iPhone too:** drill-in navigation is genuinely better on phones (no wasted sidebar space, native back-gesture). Trying to use a sidebar here fights the platform. Apple's own Notes/Reminders/Mail all do exactly this split.
- **Why the same `NotoSplitView` on iPad and macOS:** maintenance cost of divergent split-view code is high and the HIG explicitly says iPad/macOS share the floating sidebar pattern. One view, two size-class branches inside it.

---

### Phase 1 — Window / scene chrome (low risk, high visual payoff)

**Goal:** Window/scene looks like the mockup on both platforms — transparent titlebar on macOS, transparent nav bar on iPadOS, centered "Noto" title, no custom toolbar buttons.

**Changes (macOS):**
- In `NotoApp.swift`, apply `.windowStyle(.hiddenTitleBar)` + `.toolbarStyle(.unified)` on the `WindowGroup`.
- Remove the Today and Settings `ToolbarItem`s from `NoteListView`'s macOS branch.
- Move Today (`⌘T`) and Settings (`⌘,` via `SettingsScene`) to menu-bar `.commands { CommandMenu("File") { … } }`.
- Confirm traffic lights + sidebar-toggle render (system-provided by `NavigationSplitView`).

**Changes (iPadOS):**
- In `NotoApp.swift` iOS scene: configure `UINavigationBarAppearance` with transparent background + centered title. Title set via `.navigationTitle("Noto")` on the split view root.
- Remove the `ToolbarItem`s from `NoteListView`'s iOS regular branch too — keep the chrome clean. Surface Today/Settings via `.commands` (hardware keyboard palette) and a sidebar-bottom affordance only if dogfooding shows discoverability issues.
- Settings on iPad: sheet-presented `SettingsView` triggered by a menu command, not a chrome button.

**Tests:**
- Manual macOS: `flowdeck run -S "Noto-Test-<id>"` → compare with `noto_mac.png`.
- Manual iPadOS: `flowdeck run --device "iPad Pro (13-inch) (M4)"` → confirm nav bar matches mockup, sidebar toggle present, no toolbar clutter.
- Automated: `.claude/features/mac-ui-redesign.md` feature doc lists the chrome invariants as success criteria.

### Phase 2 — Sidebar redesign (floating + tree + search)

**Goal:** Sidebar looks and behaves like the mockup; content flows beneath it per HIG.

**Changes:**

- Apply `.backgroundExtensionEffect()` to the detail view's root container (editor area). This is the HIG-specified API for "content flows beneath sidebar."
- Use the system-provided Liquid Glass material on the sidebar — do not paint a custom background.
- Use accent color for sidebar icons (default SwiftUI behavior when the row label uses `Image(systemName:)`).
- New `Noto/Views/Shared/NotoSidebarView.swift` — shared between iPad regular and macOS per §3.0. Keep iPhone + iPad compact drill-in flow untouched.
- Build a flattened tree data source:
  - New model `SidebarNode { id, kind: .folder(isExpanded)/.note, depth, name, url, children? }`.
  - `SidebarTreeLoader` walks the vault recursively once (cap depth or use lazy-load if perf becomes an issue) and publishes `[SidebarNode]`. Subscribe to `VaultFileWatcher` for refresh.
  - Expansion state persisted in a `Set<URL>` of expanded folder URLs (UserDefaults).
- Render as a single `List { ForEach(flattenedRows) { … } }` — not `DisclosureGroup`. This gives full control over icons and chevron visibility.
- Row view: `HStack { Image(sfSymbolFor(node)); Text(node.name) }.padding(.leading, CGFloat(node.depth) * 16)`.
  - SF Symbols: `folder` (closed), `folder` + `.variableColor` or a custom "folder open" shape (use `folder` vs `folder.fill`, or explicitly `rectangle.portrait.and.arrow.right` for a specific "open" look — easiest is `folder` for closed, `folder.fill` for open, and `doc` for notes).
- Clicking a folder row toggles expansion (updates `expandedURLs`, re-flattens). No chevron rendered.
- Clicking a note row selects it (`selectedNote = note`).
- Search field at top bound to `@State searchText`. When non-empty, filter the flattened list to rows whose name contains the query (case-insensitive); keep ancestor folders visible so hits retain context.
- Use `.listStyle(.sidebar)` + `scrollContentBackground(.hidden)` + `AppTheme.sidebarBackground`. Hide system disclosure UI by not using `DisclosureGroup`.

**Tests:**

- Unit tests (`NotoVault` package): `SidebarTreeLoader` produces expected flat rows given a fixture vault tree.
- Unit tests: search filter keeps ancestors in result.
- UI: manual screenshot comparison.

### Phase 3 — Editor shell: word/character counter overlay

**Goal:** Add the only new editor shell element: a live word/character counter pinned to the bottom-right of the editor pane.

This phase intentionally does **not** add tags, frontmatter fields, a separate title field, or extra editor chrome.

#### Reuse principle — no new editor view

**We do not build a new Mac/iPad editor.** The existing `TextKit2EditorView` already handles both iOS and macOS via internal `#if` branches (text engine, first-responder handling, iCloud download flow, re-entrancy guards). It continues to be the single editor on every platform.

What Phase 3 touches:

| What | Where | Kind of change |
| ---- | ----- | -------------- |
| Word/character counter | New SwiftUI overlay, composed by `NoteEditorScreen` | **New outside-the-editor overlay** |
| Word-count logic | `Packages/NotoVault/…/WordCounter.swift` | **Pure logic** — strips frontmatter and counts body text |

Everything else in `TextKit2EditorView`, `BlockEditorView+macOS.swift`, `NoteEditorSession`, and the block model stays as-is. `NoteEditorScreen` remains the single cross-platform host — it wraps the existing editor with the counter overlay only. Platform branches (if any) live there, not in the editor itself.

#### Counter overlay

- New `EditorStatusOverlay.swift`: a small `HStack` with two `Text` labels separated by ~16pt spacing. Muted color (`AppTheme.mutedText`), 11–12pt font, localized number formatting (NumberFormatter with grouping → `1,234`).
- Place it in `NoteEditorScreen` as an `.overlay(alignment: .bottomTrailing)` on the editor body, with `.padding(.trailing, 24).padding(.bottom, 16)`. Because it's an overlay, the editor's scroll content flows beneath it.
- Counter source: compute from `session.content` (the source of truth). Words = split on whitespace/newlines, drop empties, count; characters = `content.count` (Swift grapheme clusters — user-visible count).
  - **Exclude frontmatter** from the count. Parse content minus the `---\n...\n---` prefix before counting.
  - Include the title block in the count, because the title is still user-authored markdown text.
- Debounce: the counter can update on every keystroke (cheap); no throttling needed for documents under ~100k chars. If profiling shows hitches, debounce at 150ms.
- Accessibility: `.accessibilityElement(children: .combine)` with label `"32 words, 1,234 characters"`.

**Tests:**

- Unit: `WordCounter.count(in:)` fixtures — empty, single word, multiline, frontmatter-stripped, unicode/emoji grapheme clusters.
- Visual: overlay stays pinned while scrolling; doesn't overlap the last line of a long document awkwardly (test with 200-line note).
- Accessibility: VoiceOver reads the combined label.

**Files:**
- New: `Noto/Views/Shared/EditorStatusOverlay.swift`
- New: `Packages/NotoVault/Sources/NotoVault/WordCounter.swift` (pure logic → package per the "no UI in packages" rule)
- `Noto/Views/NoteEditorScreen.swift` — add the `.overlay`.

### Phase 4 — Typography audit & polish

- Codify `AppTheme.TypeScale` per section 1.5. Replace every `Font.system(size: …)` and every raw `NSFont.systemFont(ofSize: …)` in the codebase with a semantic text style from the table. Grep for both patterns and convert.
- The editor's block renderer (`MarkdownTextStorage` / `BlockEditorView+macOS` / `TextKit2EditorView`) currently uses hardcoded font sizes for headings, body, bullets. Swap to `NSFont.preferredFont(forTextStyle: .title1)` etc., then apply bold trait via `NSFontManager.convert(_:toHaveTrait:)`.
- Tune padding: editor horizontal padding to ~56pt on macOS; increase top padding of first block to ~32pt.
- Verify bullet glyph matches mockup (· dot, not hyphen). Adjust in the bullet-block renderer.
- Add selected-row styling for sidebar (subtle `primaryText.opacity(0.08)` pill). Mockup doesn't show one, but we need _some_ affordance — keep it subtle.
- **Verify Dynamic Type on iPadOS (macOS doesn't support it per HIG):**
  - iPadOS: Settings → Display & Brightness → Text Size → drag the slider across all 7 standard levels; then enable *Larger Accessibility Text Sizes* and test AX1–AX5. Confirm sidebar, editor body, note title, and word counter all scale. Anything that stays fixed is still using a raw size — fix.
  - macOS: no Dynamic Type slider to test, but verify layouts still look right at the default sizes and that System Settings → Appearance → Text Size (the bucketed preference) is respected on controls that use `NSFont.preferredFont(forTextStyle:)`.
- **Verify touch targets on iPadOS:** every sidebar row should be ≥44pt tall. Use Accessibility Inspector or manual measurement.

### Phase 5 — Search feature (can be deferred)

- Phase 2 already filters by name. True content search (FTS5, like v1's `NotoFTS5` archive) is a bigger lift — defer until the shell redesign is shipped. When we pick it up, revive the v1 FTS5 package into a new `NotoSearch` Swift package per the "packages for non-UI logic" rule.

---

## 4. Risk & sequencing

- **Lowest risk / highest payoff first:** Phase 1 (chrome) and Phase 2 (sidebar) change zero file-format behavior. Land them, dogfood, iterate.
- **Low-to-medium risk:** Phase 3 adds an editor overlay and pure counter logic. It does not change file format, frontmatter, title behavior, or editor storage.
- **Low risk:** Phase 4 is pure visual polish.
- **Deferrable:** Phase 5 search is a real product feature; mockup only shows the pill.

Each phase should go through `/ios-development` with its own feature doc under `.claude/features/` and its own tests. Do **not** bundle all phases into one PR.

---

## 5. Concrete files that will change

### Phase 1 (macOS + iPadOS chrome)
- `Noto/NotoApp.swift` — macOS window styling + iOS nav-bar appearance; `.commands` for Today/Settings on both platforms.
- `Noto/Views/NoteListView.swift` — remove both macOS and iOS-regular toolbar items.

### Phase 2 (shared sidebar)
- New: `Noto/Views/Shared/NotoSidebarView.swift` (shared macOS + iPad regular)
- New: `Noto/Views/Shared/SidebarNode.swift`
- New: `Packages/NotoVault/Sources/NotoVault/SidebarTreeLoader.swift`
- New: `Noto/Views/Shared/NotoSplitView.swift` (composes sidebar + editor + `.backgroundExtensionEffect()`)
- `Noto/Views/NoteListView.swift` — route macOS + iOS-regular to `NotoSplitView`; iPhone + iPad-compact remain on existing drill-in.

### Phase 3 (editor shell counter overlay — reuse existing `TextKit2EditorView`, no rewrite)
- New: `Packages/NotoVault/Sources/NotoVault/WordCounter.swift`
- New: `Noto/Views/Shared/EditorStatusOverlay.swift`
- `Noto/Views/NoteEditorScreen.swift` — add bottom-right overlay.

### Phase 4 (typography)
- `Noto/Support/AppTheme.swift` — `TypeScale` enum with SwiftUI `Font` + AppKit `NSFont` companions.
- Various views + `MarkdownTextStorage` — swap hard-coded fonts for semantic text styles.

---

## 6. Open questions to resolve before Phase 3

1. Sidebar toggle keyboard shortcut: standard `⌘⌥S`? (Yes — matches Mail/Notes.)
