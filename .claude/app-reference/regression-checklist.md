# UAT Checklist — React Native Migration

Acceptance gate for the RN rewrite. Each row is one state from
[01-screens-and-states.md](01-screens-and-states.md), with the reference screenshot to compare
against.

**How to run:** seed a vault with `.maestro/seed-vault.sh <udid> --scale small` so the RN build
sees the same fixtures. Walk each row, compare against `screenshots/<platform>/<ID>.png`, mark
Pass / Fail / N-A, and note deltas.

**Rules:**

- A row passes only when the RN build matches on **layout, copy, and behaviour**. Pixel-exact
  is not required; "a user would not notice the difference" is.
- Rows marked **[P0]** are load-bearing — the app is not shippable if they fail.
- Rows marked **[NC]** were not captured; verify against the written spec instead.
- Accessibility identifiers must be preserved so `.maestro/` flows keep passing.

---

## A. Vault setup

| # | State | Ref | Checks | P | Notes |
|---|---|---|---|---|---|
| A1 | Welcome | `VAULT-01` | Icon, title, subtitle, both cards with correct subtitles | ☐ | |
| A2 | Create New Vault | `VAULT-02` | Opens folder picker; creates a `Noto` folder **inside** the chosen parent | ☐ | |
| A3 | Open Existing Vault | `VAULT-02` | Opens folder picker; uses the chosen folder **as-is** | ☐ | |
| A4 | **[P0]** Vault persists | — | Relaunch reopens the same vault without re-picking | ☐ | Bookmark, not path |
| A5 | **[P0][NC]** Broken bookmark | — | Unwritable vault forces a clean re-pick, never a silent read-only state | ☐ | macOS |

## B. Note list / sidebar

| # | State | Ref | Checks | P | Notes |
|---|---|---|---|---|---|
| B1 | **[P0]** Root populated | `LIST-01` | Folders above notes; header `4 folders · 4 notes`; dock present | ☐ | |
| B2 | Folder subtitles | `LIST-01` | `Empty` / `1 item` / `N items`; counts **all** children | ☐ | |
| B3 | Note subtitles | `LIST-01` | Relative time, `Edited just now` etc. | ☐ | |
| B4 | Sort menu | `LIST-02` | Recent / Name, checkmark on active, default Recent | ☐ | |
| B5 | Sort applies | `LIST-02` | Re-sorts folders and notes within their groups | ☐ | |
| B6 | More menu | `LIST-03` | New Folder + Settings | ☐ | |
| B7 | New folder | `LIST-04` | Alert with Cancel/Create; empty name is a no-op | ☐ | |
| B8 | Empty folder | `LIST-05` | "Empty" / "Tap + to create a note or folder" | ☐ | |
| B9 | Populated folder | `LIST-06` | Header shows note-only count when no subfolders | ☐ | |
| B10 | Back label | `LIST-05` | Back button reads the **parent folder name**, not "Back" | ☐ | |
| B11 | **[P0]** Create note | — | Dock + creates a note, opens editor, caret after `# ` | ☐ | |

## C. Editor — rendering

| # | State | Ref | Checks | P | Notes |
|---|---|---|---|---|---|
| C1 | **[P0]** Headings | `EDIT-01` | `#`/`##` markers visible + muted; heading text bold, scales by level | ☐ | |
| C2 | **[P0]** Markers are real text | `EDIT-01` | Caret/selection traverse the markers; they are not decoration | ☐ | |
| C3 | **[P0]** Todo unchecked | `EDIT-08` | `- [ ] ` renders as a hollow circle | ☐ | |
| C4 | **[P0]** Todo checked | `EDIT-08` | `- [x] ` renders green check + strikethrough + dimmed text | ☐ | |
| C5 | **[P0]** Todo metrics | `EDIT-08` | Caret, selection rects, hit testing stable next to the glyph | ☐ | Body-font metrics at the boundary |
| C6 | **[P0]** Todo empty boundary | — | `- [ ] ` with **no** trailing content behaves correctly | ☐ | Explicit regression case in `CLAUDE.md` |
| C7 | Bullets | `EDIT-09` | `- ` renders as muted dash, text indented | ☐ | |
| C8 | Bullet wrapping | `EDIT-10` | Wrapped lines hang to the text indent, not the marker | ☐ | |
| C9 | Links | `EDIT-12` | Render as blue title text; URL hidden when caret is elsewhere | ☐ | |
| C10 | Link source reveal | `EDIT-12` | Caret on the line reveals raw markdown | ☐ | |
| C11 | HTML comments | `EDIT-12` | Muted monospace, visible and editable | ☐ | Readwise structural markers |
| C12 | Blockquotes | `EDIT-12` | Literal `>` prefix retained | ☐ | |
| C13 | Inline images | `EDIT-12` | Load from vault-relative path | ☐ | |
| C14 | **[P0]** Frontmatter hidden | `EDIT-01` | Not rendered, but round-tripped byte-for-byte on save | ☐ | |
| C15 | Nested indent levels | — | Indent progression correct beyond one level | ☐ | Per `CLAUDE.md` validation rule |

## D. Editor — chrome and actions

| # | State | Ref | Checks | P | Notes |
|---|---|---|---|---|---|
| D1 | Scrolled title | `EDIT-11` | Title appears in nav bar after scrolling past the H1 | ☐ | |
| D2 | Dock hides on scroll | `EDIT-11` | Bottom dock hides while scrolling | ☐ | |
| D3 | More menu | `EDIT-02` | All 4 actions + word and character counts | ☐ | |
| D4 | Counts accurate | `EDIT-02` | Exclude frontmatter; update after edits | ☐ | |
| D5 | Accessory toolbar | `EDIT-01b` | 6 format buttons + right-aligned Hide Keyboard | ☐ | |
| D6 | Toolbar actions | — | Todo, indent, outdent, strikethrough, link, image all work | ☐ | |
| D7 | **[P0]** Find matches | `EDIT-04` | Current match **yellow**, others **grey** | ☐ | |
| D8 | Find counter | `EDIT-04` | Reads `1 / 2`; prev/next cycle | ☐ | |
| D9 | Find hides dock | `EDIT-03` | Dock hidden while find is open | ☐ | |
| D10 | Find above keyboard | — | Bar sits above the keyboard when raised | ☐ | **Gap:** not captured |
| D11 | Properties rows | `EDIT-07` | Folder, Created, Modified, Updated, Add property | ☐ | |
| D12 | Conditional rows | `EDIT-07` | `Updated` only when frontmatter carries it | ☐ | |
| D13 | Add property types | `EDIT-04b` | Text / Tags / Date & time | ☐ | |
| D14 | Move sheet | `EDIT-05` | All folders + Vault Root; current annotated | ☐ | |
| D15 | **[P0]** Move works | `EDIT-05` | File moves on disk; UUID unchanged | ☐ | |
| D16 | Delete confirm | `EDIT-06` | Destructive Delete Note + Cancel | ☐ | |
| D17 | **[P0]** Rename via H1 | — | Editing the H1 renames the file; UUID unchanged | ☐ | |
| D18 | **[P0]** Autosave | — | Edits persist; closing mid-edit loses nothing | ☐ | |
| D19 | Loading placeholder | — | Spinner only after ~300 ms; no flash on fast loads | ☐ | **Gap:** not captured |

## E. Search

| # | State | Ref | Checks | P | Notes |
|---|---|---|---|---|---|
| E1 | Recent | `SEARCH-01` | `LAST EDITED` header, recent notes, "Search or ask AI" | ☐ | |
| E2 | **[P0]** Results | `SEARCH-02` | Title, breadcrumb + time, matched heading, highlighted snippet | ☐ | |
| E3 | Multiple hits per note | `SEARCH-02` | One note can return several rows for different sections | ☐ | |
| E4 | Scope control | `SEARCH-02` | Title + body / Title only; appears only with a query | ☐ | |
| E5 | Title-only scope | `SEARCH-03` | Restricts matching to titles | ☐ | |
| E6 | **[P0]** Semantic fusion | `SEARCH-04` | Non-lexical query still returns nearest notes | ☐ | Do **not** "fix" into an empty state |
| E7 | Tag mode entry | `SEARCH-05` | Leading `#` swaps scope control for tag suggestions | ☐ | |
| E8 | Tag suggestions | `SEARCH-05` | Chips show name + count | ☐ | |
| E9 | Tag results | `SEARCH-06` | Header `TAGGED #<NAME>`, member notes listed | ☐ | |
| E10 | **[NC]** Indexing state | — | "Indexing notes" while the index builds | ☐ | |
| E11 | **[NC]** Searching state | — | "Searching notes" while a query is in flight | ☐ | |
| E12 | **[NC]** Search unavailable | — | Shown when the vault fails to load | ☐ | |
| E13 | Open result | — | Tapping a result opens the note at the matched section | ☐ | |

## F. Chat

| # | State | Ref | Checks | P | Notes |
|---|---|---|---|---|---|
| F1 | Empty composer | `CHAT-01` | Header, "Chat about notes", composer | ☐ | |
| F2 | Auto-context | `CHAT-01` | Open note auto-attached as a removable chip | ☐ | |
| F3 | No-key alert | — | Sending without a key points the user to Settings | ☐ | |
| F4 | **[NC]** Streaming reply | — | Eyebrow, tool steps, sources, thinking indicator | ☐ | Needs a key |
| F5 | **[NC]** Add context sheet | — | Search + select notes | ☐ | |
| F6 | **[NC]** Chat history | — | List, resume, rename, empty state | ☐ | |
| F7 | **[NC]** Edit blocks | — | Accept / dismiss AI edits | ☐ | |
| F8 | **[P0]** Session survives nav | — | Chat state persists when navigation changes the page beneath it | ☐ | Shared `ChatSessionStore` |

## G. Settings

| # | State | Ref | Checks | P | Notes |
|---|---|---|---|---|---|
| G1 | Storage section | `SET-01` | Vault location + destructive Change Vault + footer | ☐ | |
| G2 | Change Vault | — | Confirmation alert; returns to welcome; **deletes no files** | ☐ | |
| G3 | Tags section | `SET-01` | One row per tag with count, or empty message | ☐ | |
| G4 | Index sections | `SET-03` | Keyword + semantic status, Resume, Rebuild | ☐ | |
| G5 | AI Chat | `SET-02` | Key field + Save; Keychain footer | ☐ | |
| G6 | Advanced base URL | `SET-02` | Default URL, Save, Reset | ☐ | |
| G7 | Readwise | `SET-02` | Set Token / Test / Sync; Test+Sync **disabled** with no token | ☐ | |
| G8 | Readwise status | `SET-02` | Token state + last-synced footer | ☐ | |

## H. Daily notes

| # | State | Ref | Checks | P | Notes |
|---|---|---|---|---|---|
| H1 | **[P0]** Today opens | `DAILY-01` | Opens/creates today's note in `Daily Notes/` | ☐ | |
| H2 | Filename + title | `DAILY-01` | `YYYY-MM-DD.md`; H1 renders `03 Aug, 26 (Mon)` | ☐ | |
| H3 | Template | `DAILY-01` | Four H2 prompts, exact copy | ☐ | |
| H4 | Idempotent | — | Today twice opens the same note; never duplicates | ☐ | |
| H5 | **[NC]** Midnight rollover | — | Prewarmer creates the next day's note at rollover | ☐ | |

## I. iPad

| # | State | Ref | Checks | P | Notes |
|---|---|---|---|---|---|
| I1 | **[P0]** Split view | `IPAD-01` | Sidebar + detail; toggle works | ☐ | |
| I2 | Sidebar overlay | `IPAD-01` | Overlays detail in portrait, not a permanent column | ☐ | |
| I3 | **[P0]** Selection state | `IPAD-02` | Selected note highlighted + accented icon | ☐ | Does not exist on iPhone |
| I4 | Detail chrome | `IPAD-03` | Sidebar toggle, back, search, more | ☐ | |
| I5 | **[P0]** Compact centred dock | `IPAD-12` | Dock **is present** in editor; centred, fixed-width search pill | ☐ | iPhone stretches it full-width |
| I6 | Dock has 3 controls | `IPAD-12` | Today, Search, New Note — **no** `chat_button` | ☐ | |
| I7 | **[P0]** Chat entry point | `IPAD-07` | AI Chat lives in the **sidebar More menu** (`sidebar_chat_button`) | ☐ | Only route to chat on iPad |
| I8 | **[P0]** Chat inset form sheet | `IPAD-08` | Floating card leaving sidebar visible — **not** iPhone's full-height sheet | ☐ | |
| I9 | **[P0]** Settings inset sheet | `IPAD-09` | Same inset presentation | ☐ | |
| I10 | Settings dismissal | `IPAD-09` | Leading **back chevron**, not a trailing Done | ☐ | Differs from iPhone |
| I11 | **[P0]** Search page sheet | `IPAD-10` | Near-full-width page sheet (`presentationSizing(.page)`) | ☐ | |
| I12 | Search results parity | `IPAD-11` | Row structure, scope control, dock match iPhone | ☐ | |
| I13 | Keyboard over dock | `IPAD-10` | Software keyboard raises without covering the search field | ☐ | |
| I14 | **[P0]** Properties panel | `IPAD-05` | Centred card + dimmed backdrop, tap-outside dismisses | ☐ | Not a bottom sheet |
| I15 | Magnifier = find | `IPAD-06` | Editor magnifier opens **in-note find**, not global search | ☐ | |
| I16 | Sidebar more menu | `IPAD-07` | New Folder, AI Chat, Settings — one more item than iPhone | ☐ | |
| I17 | Shared data rules | — | Same loading/ordering/title rules as iPhone | ☐ | |

## J. macOS

| # | State | Ref | Checks | P | Notes |
|---|---|---|---|---|---|
| J1 | **[P0]** Split window | `MAC-01` | Permanent sidebar column | ☐ | |
| J2 | Window chrome | `MAC-01` | Hidden title bar, traffic lights in sidebar, matched background | ☐ | |
| J3 | Full-height on open | `MAC-01` | Window expands to visible screen height | ☐ | |
| J4 | Sidebar rows | `MAC-04` | Denser than iOS; header has Today/new/sort/more | ☐ | |
| J5 | **[P0]** Chat inline column | `MAC-02` | Third column, **not** a sheet; editor reflows and stays live | ☐ | Biggest structural delta |
| J6 | Find bar | `MAC-03` | Fixed 12pt bottom inset | ☐ | |
| J6a | **[P0]** Todo glyphs on macOS | `MAC-05` | Circle + green check render, matching iOS | ☑ | Fixed 2026-08-03 via `TodoMarkerRenderer` |
| J6b | **[P0]** Todo click-to-toggle on macOS | `MAC-05` | Clicking the circle toggles the todo | ☐ | Hit-testing exists and shares geometry; **click not yet verified end-to-end** |
| J6c | Bullets render | `MAC-06` | Muted `-` markers, indented text | ☐ | Control case for J6a |
| J6d | **[P0]** Rich rendering parity | `MAC-07` | Links, comments, blockquotes, images, hidden frontmatter | ☐ | Verified matching iOS |
| J6e | Empty folder copy | `MAC-08` | "**Secondary-click** to create a note or folder" | ☐ | Differs from iOS "Tap +" |
| J6f | **[NC]** Sidebar context menu | — | Right-click offers create note / folder | ☐ | Implied by J6e copy; no iOS equivalent |
| J6g | Detail persists across folders | `MAC-08` | Navigating the sidebar keeps the open note in detail | ☐ | iPhone pushes and replaces |
| J7 | **[NC]** Menu bar | — | All 12 commands with correct shortcuts | ☐ | |
| J8 | **[P0][NC]** Per-window routing | — | Commands act only on the key window | ☐ | `NotoCommandTarget.matches` |
| J9 | **[NC]** Multi-window | — | ⌘⇧N opens an independent window | ☐ | |
| J10 | **[P0][NC]** Cross-window sync | — | Editing in one window updates the other via in-process sync | ☐ | Not the file watcher |
| J11 | **[NC]** Settings scene | — | ⌘, opens a native Settings window, not a sheet | ☐ | |
| J12 | **[P0][NC]** Sandbox writes | — | Writes to an external vault succeed; no silent 513 | ☐ | |

## K. Data integrity — the non-negotiables

| # | Behaviour | Checks | P | Notes |
|---|---|---|---|---|
| K1 | **[P0]** UUID is identity | Rename/move preserves `id`; nothing keys on path | ☐ | |
| K2 | **[P0]** Title derives from first line | Never stored separately | ☐ | |
| K3 | **[P0]** Frontmatter round-trip | Rich capture frontmatter survives an edit byte-for-byte | ☐ | |
| K4 | **[P0]** Folders are directories | Create/move/delete map to real fs operations | ☐ | |
| K5 | **[P0][NC]** Remote conflict banner | "Keep Mine" / "Reload"; never silently overwrite | ☐ | |
| K6 | **[P0][NC]** iCloud downloading | Spinner + "Downloading from iCloud…" | ☐ | |
| K7 | **[P0][NC]** iCloud failure | "Note Not Available" + working Try Again | ☐ | |
| K8 | **[P0]** Read-first, not metadata-first | Coordinated read attempted before trusting download status | ☐ | |
| K9 | **[P0]** Crash-safe index queue | Interrupted index work replays on next launch | ☐ | |
| K10 | External edit picked up | Editing a file in Finder updates the app | ☐ | |

## L. Cross-cutting

| # | Behaviour | Checks | P | Notes |
|---|---|---|---|---|
| L1 | Forced dark | No light theme; `#0A0A0A` chrome, `#0E1116` editor body | ☐ | |
| L2 | Accent consistency | Same orange for new-note, selection, folder dots | ☐ | |
| L3 | **[P0]** A11y identifiers | All IDs in the spec preserved | ☐ | `.maestro/` depends on them |
| L4 | **[P0]** Maestro suite | Existing flows in `.maestro/` pass against the RN build | ☐ | Strongest regression signal |
| L5 | Deep links | `onOpenURL` routes to the right note | ☐ | |
| L6 | Restore last note | Relaunch reopens the last note | ☐ | |
| L7 | Note history | Back/forward through visited notes, distinct from nav stack | ☐ | |
| L8 | Foreground refresh | Returning to foreground refreshes store, daily note, index | ☐ | |

---

## Sign-off

| Platform | P0 pass | Total pass | Blockers | Signed | Date |
|---|---|---|---|---|---|
| iPhone | / | / | | | |
| iPad | / | / | | | |
| macOS | / | / | | | |

**Migration is accepted when every [P0] row passes on all three platforms and the `.maestro/`
suite (L4) is green.**

### Baseline corrections

**J6a — fixed 2026-08-03.** Todo markers did not render on macOS; the glyph now lives in the
shared `TodoMarkerRenderer` and is drawn by both platforms. `MAC-05` has been re-captured, with
the pre-fix state kept alongside it as `MAC-05-editor-todos-BEFORE-FIX.png`.

**J6b — still unverified.** macOS click-to-toggle relies on pre-existing hit-testing that shares
geometry with the drawing, so it is expected to work now that the circle is visible. Confirming
it needs cursor-taking GUI automation, which has not been run. Do not tick it on inspection
alone.
