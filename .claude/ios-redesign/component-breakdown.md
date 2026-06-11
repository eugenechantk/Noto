# Noto iPhone Redesign — Component Breakdown

Source: `Design/v2` (claude.ai/design export). Ground-truthed against the **rendered** output (local server), not just component source — dead/unrendered code excluded (see Caveats). Target: native SwiftUI/UIKit (iOS 26), dark-only v1.

This doc decomposes the four iPhone surfaces into implementable components, each mapped to a native view, the existing Noto file it touches, and where non-UI logic lives (`Packages/NotoVault`).

---

## 0. The four iPhone surfaces (from `Noto System.html`)

| Surface | Design component | States (artboards) |
|---|---|---|
| **File view** | `NoTabsNoteList` (`noto-notabs-screens.jsx`) | Vault root · Captures · Captures›AI Products (one folder level per page) |
| **Editor** | `NotoMinimalEditor` (`noto-minimal-editor.jsx`) | editing · reading · scrolled |
| **Properties** | `NotoMinimalEditor` props states + `noto-properties-hig.jsx` | sheet (medium) · expanded · type-menu · add · swipe-delete · edit-long-value |
| **Search** | `Exp03ArticleV3Search` (`noto-explorations-v3-3-search.jsx`) | empty (Last edited) · results |

Navigation model: **File view is home** (bottom dock = today/daily · search · new). Tap a note → **Editor** (chrome-free, back returns). Dock search → **Search**. Properties open as a **bottom sheet** over the editor. **No tabs anywhere.**

---

## 1. Foundation layer — design tokens  → `NotoTheme` (new, app target)

**Colors**
- Surfaces: bg `#0E1116`, ink `#ECECEE`, head `#FFFFFF`, muted `rgba(236,236,238,0.62)`, faint `rgba(236,236,238,0.34)`, hairline `rgba(255,255,255,0.07–0.10)`.
- Accent: **`#FF6A2E`** (caret, selection, accent rows). ⚠️ the keyboard toolbar source uses `#FF5A1F` for "active" — standardize on `#FF6A2E`.
- Grouped list (properties): groupedBg `#111419`, card `#1C2027`, secondary `rgba(235,235,245,0.62)`, tertiary `rgba(235,235,245,0.32)`, separator `rgba(84,84,88,0.55)`, chip fill `rgba(118,118,128,0.24)`.
- Status amber `#E6B62A`, destructive red `#FF3B30`.
- Glass (dock/find/search pill/type-menu): `rgba(28,30,36,0.55)` + `backdrop blur(28px) saturate(180%)` + hairline `rgba(255,255,255,0.10)`.

**Type ramp** (SF Pro / `-apple-system`)
- Large title 33 / 700 / -0.7 · note title 25 / 700 / -0.4 · H2 18–20 / 700 · body 16 / line 1.55 / -0.1 · row label & value 16 / -0.2 · folder/note row title 15.5–17 / 600 · subtitle 12.5–13 · chip 13.5.

**Other**
- Caret: 2px, `#FF6A2E`, blink 1.05s steps.
- SF Symbols map: folder, doc(text), calendar, clock, tag, link, smallcircle.filled.circle (status), person, textformat, number, checklist, plus, chevron.right, checkmark, trash, magnifyingglass, ellipsis, chevron.left (back), square.and.pencil (new), sidebar.

→ One `NotoTheme` with `Color`/`Font` tokens, used by every component below.

---

## 2. Semantic component library (mined from the JSX)

Components extracted by the rule of thumb: **(1)** aligns with an Apple HIG component, **(2)** isolated function, **(3)** repeated across a screen. The **Source JSX** column gives the exact `file · function` to open as reference when implementing. **Native** flags whether to build a custom view or **theme a system control** — do not rebuild what iOS gives you (segmented control, sheet, menu, search field, swipe actions, caret, status bar).

> **JSX path key:** `c/` = `Design/v2/components/`; root files are `Design/v2/design-canvas.jsx`, `Design/v2/ios-frame.jsx`. To see any component live, use the local render at `http://localhost:8765/Noto%20System.html`.

### 2a. Atoms — primitives that recur on most screens

| Component | Rule / HIG | Source JSX (`c/` = `Design/v2/components/`) | Used in (repetition) | Native |
|---|---|---|---|---|
| **Icon** | SF Symbols | `c/noto-shared.jsx·NIcon` · `c/noto-properties-hig.jsx·Sym` · `c/noto-toolbar.jsx·NotoIcons` · `c/noto-notabs-screens.jsx·folderGlyph/fileGlyph` | everywhere | SF Symbol, themed |
| **IconButton** | Buttons / toolbar items | `c/noto-shared.jsx·NCircle/NPill/NPillBtn` · `c/noto-minimal-editor.jsx·SheetCircleBtn` · `c/noto-toolbar.jsx·NotoToolbarArticle(iconBtn)` | nav bars, dock, sheet ✕/✓, keyboard toolbar, explorer actions | custom; variants: plain · glass-circle · filled-accent-circle · icon+label |
| **GlassSurface** | Materials / Liquid Glass | `c/noto-notabs-screens.jsx·glassStyle` · `c/noto-explorations-v3-3-search.jsx·glassStyle` · `c/noto-properties-hig.jsx·NotoTypeMenu` · `c/noto-shared.jsx·NPill` | dock, search dock, find bar, type menu | `.background(.ultraThinMaterial)` + token tint |
| **Caret** | isolated + repeated | `c/noto-minimal-editor.jsx·Caret` · `c/noto-properties-hig.jsx·Caret` · `c/noto-notabs-screens.jsx·FindBar` · `c/noto-explorations-v3-3-search.jsx·SearchDock` | editor, properties (source/adding), search pill, find bar | native tint; custom only for static mocks |
| **Chip / Token** | Token fields | `c/noto-properties-hig.jsx·Chip` | properties Tags (+ future filters) | `TagChip` |
| **DotLabel** | repeated | `c/noto-properties-hig.jsx·Folder` (accent-dot+name) · `·Status` (colored-dot+label) | properties Folder & Status values | small view |
| **MetadataLine** | repeated | `c/noto-notabs-screens.jsx·FolderRow/FileRow` (subtitles) · `c/noto-explorations-v3-3-search.jsx·Row` | file view, search | subtitle slot of `ListRow` |
| **FadeEdge / Scrim** | isolated + repeated | `c/noto-minimal-editor.jsx·TopBar`(scrim)`/Surface`(fade) · `c/noto-notabs-screens.jsx·NoTabsNoteList`(fade) · `c/noto-explorations-v3-3-search.jsx·Body`(fade) | editor (top scrim + bottom fade), file-view & search bottom fades | `LinearGradient` overlay |
| **StatusBar / HomeIndicator** | Status bar | `c/noto-shared.jsx·NStatusBar` · frame `Design/v2/ios-frame.jsx` | all | system (free) |

### 2b. Controls — HIG-named (mostly system controls to theme)

| Component | Rule / HIG | Source JSX (`c/` = `Design/v2/components/`) | Used in | Native |
|---|---|---|---|---|
| **NavigationBar (Top bar)** | Toolbars / navigation | `c/noto-minimal-editor.jsx·TopBar` · `c/noto-notabs-screens.jsx·TopBar/ExplorerTopBar` | editor, file view | custom top bar; **scrolled-scrim** variant carries the title |
| **LargeTitleHeader** | Large title | `c/noto-minimal-editor.jsx`(notelist title) · `c/noto-notabs-screens.jsx·NoTabsNoteList`(header) | file view | iOS large title |
| **★ ListRow** | Lists and tables — row | `c/noto-shared.jsx·NFolderRow/NNoteRow/NCompactNoteRow` · `c/noto-notabs-screens.jsx·FolderRow/FileRow` · `c/noto-properties-hig.jsx·Row` · `c/noto-explorations-v3-3-search.jsx·Row` · `c/noto-sheet.jsx·SheetSampleContent` | **file view, search, properties, sheet** | ONE `ListRow`: leading glyph · title · subtitle/value · trailing accessory (chevron / value / checkmark / none). **The single most repeated structure — unifies ~5 row impls.** |
| **SectionHeader** | Lists — section header | `c/noto-explorations-v3-3-search.jsx·SectionTitle` | search ("Last edited" / "Search results") | List section header |
| **InsetGroupedList** | Lists — inset grouped | `c/noto-properties-hig.jsx·NotoPropertyList` | properties | inset-grouped `List` |
| **SearchField** | Search fields | `c/noto-explorations-v3-3-search.jsx·SearchDock` · `c/noto-notabs-screens.jsx·FindBar`/`FloatingDock`(search pill) | search, find-in-note, file-view dock | themed `.searchable` / custom glass field |
| **SegmentedControl** | Segmented controls | `c/noto-explorations-v3-3-search.jsx·Segmented` | search results scope | `Picker(.segmented)` |
| **Sheet (+ Grabber)** | Sheets | `c/noto-sheet.jsx·IOSSheet` (used by `c/noto-minimal-editor.jsx` properties states) | properties | `.sheet` + `.presentationDetents` + `.presentationDragIndicator` |
| **PullDownMenu** | Menus / pull-down | `c/noto-properties-hig.jsx·NotoTypeMenu` | properties type picker | `Menu` |
| **SwipeDeleteAction** | Lists — swipe to delete | `c/noto-properties-hig.jsx·Row` (`onTrash`/`swiped`) | properties tags (extensible to rows) | `.swipeActions(role:.destructive)` |
| **KeyboardAccessoryToolbar** | Keyboards | `c/noto-toolbar.jsx·NotoToolbarArticle` (rail + pinned Done) | editor | `inputAccessoryView`; actions → `TodoMarkdown`/`BlockEditingCommands`/`EditorFind` |
| **FloatingDock** | Toolbars (bottom bar) | `c/noto-notabs-screens.jsx·FloatingDock` · `c/noto-shared.jsx·NFloatingCapsule` | file view | custom (today/daily · search · new) |
| **FindBar** | Search fields | `c/noto-notabs-screens.jsx·FindBar`/`NoTabsFindInText` | editor find-in-note | glass field + prev/next/count/Done |

### 2c. Markdown content primitives — editor body (HIG: text views / image views)

| Component | Source JSX (`c/` = `Design/v2/components/`) | Native |
|---|---|---|
| **Heading** (visible `#` syntax) | `c/noto-shared.jsx·NHeading` · `c/noto-minimal-editor.jsx·h2` | TextKit attributes in `TextKit2EditorView` |
| **BodyParagraph** | `c/noto-shared.jsx·NBody` · `c/noto-minimal-editor.jsx·para` | TextKit |
| **BulletList item** | `c/noto-minimal-editor.jsx·Bullet` | TextKit |
| **FigureCard** (image + label + caption) | `c/noto-minimal-editor.jsx·Figure` | image block in editor |
| code / quote / todo / link / table | existing Noto renderers | inherit the theme/ramp |

### 2d. Component → Apple HIG mapping

Canonical HIG page per component (open before implementing the iOS-native behavior). `—` = no dedicated HIG component (extracted by rule 2 isolated / rule 3 repeated).

| Component | Apple HIG component | HIG page |
|---|---|---|
| Icon | **SF Symbols** | https://developer.apple.com/design/human-interface-guidelines/sf-symbols |
| IconButton | **Buttons** (in **Toolbars**) | https://developer.apple.com/design/human-interface-guidelines/buttons · /toolbars |
| GlassSurface | **Materials** | https://developer.apple.com/design/human-interface-guidelines/materials |
| Chip / Tag | **Token fields** | https://developer.apple.com/design/human-interface-guidelines/token-fields |
| MetadataLine · DotLabel | **Labels** | https://developer.apple.com/design/human-interface-guidelines/labels |
| Caret · FadeEdge/Scrim | — (rule 2) | — |
| StatusBar / HomeIndicator | **Status bars** | https://developer.apple.com/design/human-interface-guidelines/status-bars |
| NavigationBar (Top bar) · LargeTitleHeader | **Toolbars** (navigation bar / large title) | https://developer.apple.com/design/human-interface-guidelines/toolbars |
| ListRow · InsetGroupedList · SectionHeader · SwipeDeleteAction | **Lists and tables** | https://developer.apple.com/design/human-interface-guidelines/lists-and-tables |
| SearchField · FindBar | **Search fields** (+ Searching) | https://developer.apple.com/design/human-interface-guidelines/search-fields |
| SegmentedControl | **Segmented controls** | https://developer.apple.com/design/human-interface-guidelines/segmented-controls |
| Sheet (+ Grabber) | **Sheets** | https://developer.apple.com/design/human-interface-guidelines/sheets |
| PullDownMenu / TypeMenu | **Menus** / **Pull-down buttons** | https://developer.apple.com/design/human-interface-guidelines/menus · /pull-down-buttons |
| KeyboardAccessoryToolbar | **Virtual keyboards** (+ Toolbars) | https://developer.apple.com/design/human-interface-guidelines/virtual-keyboards |
| FloatingDock | **Toolbars** (+ Tab bars) | https://developer.apple.com/design/human-interface-guidelines/toolbars · /tab-bars |
| Heading · BodyParagraph · BulletList | **Text views** | https://developer.apple.com/design/human-interface-guidelines/text-views |
| FigureCard | **Image views** | https://developer.apple.com/design/human-interface-guidelines/image-views |

iPad/macOS adaptations additionally use **Sidebars** (/sidebars) and **Split views** (/split-views).

> The surface sections (§3–§6) compose from this library. Headline: factoring **`ListRow`**, **`IconButton`**, **`GlassSurface`**, **`Caret`**, **`Chip`**, **`MetadataLine`**, and **`FadeEdge`** removes most per-screen duplication; the rest (`SegmentedControl`, `Sheet`, `PullDownMenu`, `SearchField`, `SwipeDeleteAction`) are **system controls** we theme rather than build.

---

## 3. File view — `NoTabsNoteList`  → restyle `NoteListView.swift`

**Four components: Top bar · Bottom bar · List view · List item.**

| Component | Spec | Native / logic |
|---|---|---|
| **Top bar** | leading `‹ ParentName` (accent) when nested; trailing new-folder · sort · `•••`; carries the large folder title (28/700) + "N folders · M notes" subtitle that collapses on scroll | `ExplorerTopBar` in `NoteListView` + iOS large title |
| **Bottom bar** | glass dock: `today` (calendar + date badge) · search pill · new-note (+, accent) — the `noSidebar` dock | new `NotoFloatingDock` (Shared) |
| **List view** | scrollable container; immediate subfolders first, then notes; hairline separators; bottom fade into BG | `List`/`ScrollView`; data from `VaultManager`/`MarkdownNoteStore` |
| **List item** | one row with two variants: **folder** (folder glyph + name 15.5/600 + "N items" + trailing chevron → pushes next level) · **note** (doc glyph + name + "Edited <when>"; active → accent-tint bg + accent glyph → opens editor) | one `FileSystemRow` with `.folder` / `.note` cases |

**Logic → `Packages/NotoVault`:** vault tree = real directories; one level per page (immediate subfolders + `.md` files); folders-first ordering. Nav: `NavigationStack` push per level.

---

## 4. Editor — `NotoMinimalEditor`  → `NoteEditorScreen` + `TextKit2EditorView`

**Two components: Top bar · Editor.**

| Component | Spec | Native / logic |
|---|---|---|
| **Top bar** | back + `•••`, no fill; on scroll → translucent gradient scrim (~138pt) carrying the centered note title (15/600) as the body tucks under | `IOSEditorNavigationChrome` + `EditorChromeMode` (restyle) |
| **Editor** | the note body + editing surface: title 25/700, lede, figure card (12pt radius, label chip, caption), H2, bullets, paragraphs, **visible `#` markdown syntax**, accent caret. Sub-states: **editing** (caret + keyboard toolbar [todo · indent± · strike · link · image · Done] + keyboard) · **reading** (no keyboard, bottom fade) · **scrolled** (title in scrim) | **`TextKit2EditorView`** re-themed (re-skin, not new) + `EditorKeyboardToolbar` accessory; session/save via `NoteEditorSession` |

Markdown elements beyond the mockup (code/quote/todo/link/table) inherit the theme from existing renderers.

---

## 5. Properties — bottom sheet  → new `PropertiesSheet` + `Packages/NotoVault` property model

**Presentation:** `.sheet` over the editor; `.presentationDetents([.medium, .large])`; grabber (`.presentationDragIndicator(.visible)`, 36×5); rounded top (40); **circular ✕ (leading) / ✓ orange (trailing) header** + centered "Properties" title. System dims/recedes the presenter automatically.

| Component | Spec | Native / logic |
|---|---|---|
| **PropertiesSheet** (container) | grabber + ✕/✓ nav row + inset-grouped list | new SwiftUI sheet (replaces `IOSSheet` shell) |
| **SheetCircleButton** | ✕ glass circle (~32) / ✓ filled-accent circle | new (reuse from `[[project_sheet_header_hig]]`) |
| **PropertyRow** | leading SF Symbol (22 box, 13 gap), label 16, value trailing secondary; 44pt min; hairline inset 51pt (label edge) | inset-grouped `List` row |
| **Row variants** | Folder (chevron + accent-dot + name) · Created/Modified (read-only dim, no chevron) · **Tags** (uses the Tag component ↓) · Source (editable, caret) · Status (colored dot + chevron) · Author (value) | — |
| **Tag component** | a **tag chip** (pill, fill `rgba(118,118,128,0.24)`, 24pt tall, radius 7, label 13.5); the **Tags row** is a horizontally-scrolling collection of chips with trailing fade mask + **swipe → red trash** delete (`.swipeActions`). **Reusable** beyond Properties | new `TagChip` + `TagsField` (Shared) |
| **AddPropertyRow** | accent `+` insert row | List footer row |
| **TypeMenu** | pull-down glass menu: Text · Tags · Date & time (checkmark on selected); overlays, never reflows | `Menu` / `.contextMenu` |
| **AddingRow** | fixed **120px key column** w/ horizontal scroll + trailing fade; value anchored | custom row; preserves no-layout-shift |

**Logic → `Packages/NotoVault`:** a `Property` model (key, type, value) ↔ YAML frontmatter (`Frontmatter`, `EditableFrontmatter`); folder/status/tags/source/author as typed fields; add/delete/edit. Detents + sheet are pure UI.

---

## 6. Search — `Exp03ArticleV3Search`  → new `SearchScreen`

**Screen (no header):** Body (Last edited list | Search results) · [results] segmented "Title + body / Title only" · SearchDock (glass pill "Search or ask AI" + filter chip + close ✕) · keyboard.

| Component | Spec | Native / logic |
|---|---|---|
| **SearchResultRow** | doc glyph + title (15/500) + "in <Folder> · <when>" + 2-line snippet with **highlighted match** (amber `rgba(230,182,42,0.32)`) | List row |
| **LastEditedRow** | title + "in <Folder> · <when>" (no snippet) | List row |
| **SectionTitle** | uppercase 11/600, +0.6 tracking | section header |
| **Segmented** | Title+body / Title only | `Picker(.segmented)` |
| **SearchDock** | glass pill, magnifier + input ("Search or ask AI") + filter chip + outside ✕ | `GlassCapsule` |

**Logic → `Packages/NotoVault` (or new `NotoSearch`):** title + body match across vault, recency for "Last edited", snippet extraction + match highlight, Title-only vs Title+body scope. **AI search = placeholder wording only for v1** (no backend).

---

## 7. Component → native file map (summary)

**New — shared library (§2):** `NotoTheme`, `Icon`, `IconButton`, `GlassSurface`, `Caret`, `Chip`/`TagChip` + `TagsField`, `MetadataLine`, `FadeEdge`, **`ListRow`** (base for every row), `NavigationBar`, `LargeTitleHeader`, `SectionHeader`, `NotoFloatingDock`, `EditorKeyboardToolbar`, `FindBar`.
**New — screens/logic:** `PropertiesSheet` (+ `SheetCircleButton`, `PropertyRow`=ListRow, `TypeMenu`), `SearchScreen` (+ `SearchResultRow`=ListRow), `Property` model + search (NotoVault).
**Theme system controls (don't build):** segmented control, sheet+detents+grabber, pull-down menu, search field, swipe-to-delete, caret, status bar/home indicator.
**Restyle/extend:** `NoteListView` (file browser), `NoteEditorScreen` + `TextKit2EditorView` (re-theme), `IOSEditorNavigationChrome` + `EditorChromeMode` (minimal chrome + scrolled title).
**Reuse as-is:** `NoteEditorSession`, `VaultManager`/`MarkdownNoteStore`, `Frontmatter`, `TodoMarkdown`, `BlockEditingCommands`, `EditorFind`.

## 8. Suggested build order

1. **`NotoTheme`** (tokens) — everything depends on it.
2. **File view** (`NoteListView` restyle + folder nav + `FloatingDock`) — the home/entry surface; exercises VaultManager.
3. **Editor re-theme** (`TextKit2EditorView` + chrome + keyboard toolbar) — the core surface.
4. **Properties sheet** (+ NotoVault property model) — depends on editor + frontmatter.
5. **Search** (+ NotoVault search) — independent; can parallelize with 4.

---

## Caveats / decisions (carried from analysis)

- **Read rendered, not source.** Excluded dead code: search `Header` ("Search or ask in … workspace") is defined but never rendered; the `TABS` array is unused. Only the pill placeholder "Search or ask AI" + Last edited/Search results render.
- **Accent inconsistency:** toolbar `#FF5A1F` vs body/caret `#FF6A2E` → standardize on `#FF6A2E`.
- **Dark-only v1**; no light tokens in the design.
- **Markdown coverage:** mockup shows headings/body/bullets/figure only; code/quote/todo/link/table inherit the new theme from existing renderers.
- **Find-in-note** (`NoTabsFindInText`) exists in the export (glass find bar over keyboard) — include via the editor `•••` menu, backed by `EditorFind.swift`.
