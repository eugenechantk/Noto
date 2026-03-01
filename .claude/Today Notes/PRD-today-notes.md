# PRD: Today's Notes

## Overview

Today's Notes is a structured journaling and idea-capture feature built on top of the existing Block primitive. It provides a time-organized hierarchy (Year → Month → Week → Day) that auto-builds as time progresses, giving users a frictionless place to dump ideas and journal daily.

**Key insight from the user:** "I associate random thoughts with the day I thought of it + I can keep my journal there as well."

**Scope Decisions:**

- **Templates:** Deferred — auto-fill day blocks with journal prompts is a future feature dependent on the Tags + Templates system
- **AI integration:** Deferred — the auto-building primitive is designed to be reusable by AI editing features later
- **Sync:** Inherits from the app's current local-only approach

---

## Core Requirements

| Requirement                  | Implication                                                                            |
| ---------------------------- | -------------------------------------------------------------------------------------- |
| Time-organized hierarchy     | Fixed 4-level structure: Year → Month → Week → Day                                     |
| Auto-block building on app open | Automatically create missing Year/Month/Week/Day blocks for today                      |
| Idempotent block building       | Never create duplicates — check existence before creating                              |
| Reusable primitive           | The block auto-creation logic must be a generic service, not hard-wired to Today's Notes |
| Built on Block               | Uses the same Block model as everything else — no new data models                      |
| Global "Today" button        | Bottom bar on every screen has a one-tap shortcut to today's day block                 |
| Protected structural blocks  | System-created time hierarchy blocks cannot be accidentally deleted                    |

---

## Block Hierarchy

Today's Notes is a root-level Block whose descendants follow a fixed time structure:

```
Today's Notes                        (root, depth 0)
├── 2026                             (year, depth 1)
│   ├── January                      (month, depth 2)
│   │   ├── Week 1 (5/1 - 11/1)     (week, depth 3)
│   │   │   ├── Jan 5, 2026          (day, depth 4)
│   │   │   │   ├── [user content]    (depth 5+)
│   │   │   │   └── ...
│   │   │   ├── Jan 6, 2026
│   │   │   └── ...
│   │   ├── Week 2 (12/1 - 18/1)
│   │   └── ...
│   ├── February
│   └── ...
└── 2027
```

### Block Content Formats

| Level | Content format          | Example              |
| ----- | ----------------------- | -------------------- |
| Root  | `"Today's Notes"`       | Today's Notes        |
| Year  | `"YYYY"`                | 2026                 |
| Month | `"MMMM"`               | March                |
| Week  | `"Week N (D/M - D/M)"` | Week 9 (23/2 - 1/3) |
| Day   | `"MMM D, YYYY"`         | Mar 1, 2026          |

### Date Conventions

- Day format: `MMM D, YYYY` (e.g., "Mar 1, 2026")
- Month format: Full month name only (e.g., "March") — no year, since the year is the parent block
- Week numbering: Sequential within the month, starting from 1
- Week boundaries: **Monday to Sunday** (ISO 8601 convention)
- Week range in content: `D/M - D/M` showing the Monday and Sunday of that week, hyphen separator

### Week Assignment Rule

A week belongs to whichever month contains the **Monday** of that week. If a week spans two months, it belongs to the month of its Monday.

---

## Block Protection Properties

### New Block Properties

Four new Bool properties are added to the Block model. Each controls a specific restriction independently, making the block's capabilities visible at a glance when inspecting its properties.

```
Block
├── ... (existing fields)
├── isDeletable: Bool       // default true; false = backspace-delete is a no-op
├── isContentEditableByUser: Bool // default true; false = content is read-only (system-managed)
├── isReorderable: Bool     // default true; false = long-press drag reorder is a no-op
└── isMovable: Bool         // default true; false = indent/outdent is a no-op
```

All four default to `true`, so existing blocks and user-created blocks are unaffected.

### Which Blocks Are Restricted

All auto-built structural blocks are created with all four flags set to restrict:

| Block | isDeletable | isContentEditableByUser | isReorderable | isMovable |
|---|---|---|---|---|
| Today's Notes (root) | false | false | false | false |
| Year blocks (e.g., "2026") | false | false | false | false |
| Month blocks (e.g., "March") | false | false | false | false |
| Week blocks (e.g., "Week 9 (23/2 - 1/3)") | false | false | false | false |
| Day blocks (e.g., "Mar 1, 2026") | false | false | false | false |
| User-created content under day blocks | true | true | true | true |

### Behavior per Property

| Property | When `false` | UI effect |
|---|---|---|
| `isDeletable` | Backspace on empty block is a no-op | Block cannot be removed at its level |
| `isContentEditableByUser` | Tap does not enter edit mode for this block's text | Content is read-only; system-managed label stays unchanged |
| `isReorderable` | Long-press drag gesture is a no-op | Block stays in its chronological position |
| `isMovable` | Indent/outdent operations are no-ops | Block cannot change parent or depth |

**Key:** These flags only affect the block itself when viewed at its own level. Children of restricted blocks are **not** affected — they retain full `true` defaults and can be freely created, edited, deleted, and reordered.

### Why Separate Properties

- **Inspectability:** Each capability is visible directly on the Block model, rather than being a side effect of a single `isProtected` flag
- **Composability:** Future features may need partial restrictions (e.g., a block that's non-deletable but content-editable, or non-reorderable but movable)
- **Clarity:** UI code checks `block.isDeletable` instead of inferring behavior from `block.isProtected`

### Implementation Notes

- All four properties are persisted via SwiftData like other Block fields
- The block builder service sets all four to their restricted values (`false`) when creating structural blocks
- `BuildStep` has optional overrides for each property (defaults: all `false` for structural blocks)
- UI layers check each property independently:
  - `NoteTextView`: checks `isDeletable` before backspace-delete, `isReorderable` before drag gesture
  - `NoteTextEditor`/`ContentView`/`NodeView`: checks `isContentEditableByUser` before entering edit mode, `isMovable` before indent/outdent

---

## Auto-Building

### Trigger

Auto-block building runs every time the user navigates to the Today's Notes root block or any of its descendants, and when the global Today button is tapped. It ensures the block hierarchy for today's date exists.

### Performance

The auto-build must feel **instant** — no visible latency when navigating. This is achievable because:

- At most 4 blocks are created (year + month + week + day) on the very first use
- On a typical day, only 1 block is created (the new day), or 0 if it already exists
- Each `findChildByContent` is a simple in-memory array scan of the parent's children (small N)
- SwiftData inserts are single-digit milliseconds (in-memory + SQLite write)
- The build runs synchronously on the main actor before the view loads, not as a background task

**No loading spinners, no async indicators.** The navigation and block creation happen in one synchronous pass.

### Algorithm

```
function buildTodayHierarchy(todayNotesRoot, today):
    // 1. Find or create the year block
    yearContent = format(today, "YYYY")
    yearBlock = findChildByContent(todayNotesRoot, yearContent)
    if yearBlock is nil:
        yearBlock = createBlock(
            parent: todayNotesRoot,
            content: yearContent,
            sortOrder: sortOrderForYear(today)
        )

    // 2. Find or create the month block
    monthContent = format(today, "MMMM")  // e.g. "March"
    monthBlock = findChildByContent(yearBlock, monthContent)
    if monthBlock is nil:
        monthBlock = createBlock(
            parent: yearBlock,
            content: monthContent,
            sortOrder: sortOrderForMonth(today)
        )

    // 3. Find or create the week block
    weekContent = formatWeek(today)  // e.g. "Week 9 (23/2 - 1/3)"
    weekBlock = findChildByContent(monthBlock, weekContent)
    if weekBlock is nil:
        weekBlock = createBlock(
            parent: monthBlock,
            content: weekContent,
            sortOrder: sortOrderForWeek(today)
        )

    // 4. Find or create the day block
    dayContent = format(today, "MMM D, YYYY")  // e.g. "Mar 1, 2026"
    dayBlock = findChildByContent(weekBlock, dayContent)
    if dayBlock is nil:
        dayBlock = createBlock(
            parent: weekBlock,
            content: dayContent,
            sortOrder: sortOrderForDay(today)
        )

    return dayBlock
```

### Sort Order Strategy

Auto-building uses the existing `Block.sortOrder` property — no new sorting mechanism. The builder simply sets `sortOrder` to chronological values when creating blocks, so they sort correctly via the standard `sortedChildren` (which sorts by `sortOrder` ascending).

| Level | sortOrder value | Example |
|---|---|---|
| Year | Year number as Double | 2026.0, 2027.0 |
| Month | Month index (1–12) | 1.0 (Jan), 3.0 (Mar), 12.0 (Dec) |
| Week | Week number within month | 1.0, 2.0, 3.0 |
| Day | Day-of-month | 1.0, 2.0, 15.0 |

This ensures chronological ordering regardless of creation order, using the same `sortOrder` property that all blocks already use.

### Matching Strategy

The builder uses **date-aware matching** to find existing blocks. Rather than requiring an exact content string match, the matcher understands what date/period a block represents and matches any content that resolves to the same period. If the content doesn't match the canonical format, the block's content is corrected.

**Why not exact match:** The user may manually create a block like "March 1" or "1 Mar" that represents the same day as "Mar 1, 2026". The builder should recognize this as the same day, match it (not create a duplicate), and rename it to the canonical format.

**Match + rename behavior per level:**

| Level | Canonical format | Example fuzzy matches | Matching logic |
|---|---|---|---|
| Year | `"2026"` | (unlikely to vary) | Exact match — year strings are unambiguous |
| Month | `"March"` | "Mar", "march", "Mar 2026", "March 2026", "03" | Parse to month index; match if same month |
| Week | `"Week 1 (2/3 - 8/3)"` | "Week 1", "W1", "week 1" | Parse week number; match if same week number within the month |
| Day | `"Mar 1, 2026"` | "March 1", "1 March", "1/3", "1/3/2026", "Mar 1", "march 1 2026" | Parse to a calendar date; match if same day |

**Rename on match:** When a block is matched via fuzzy matching but its content differs from the canonical format, the builder updates the block's content to the canonical format. For example, if the user created "March 1" and the builder matches it for Mar 1, 2026, the content is renamed to "Mar 1, 2026".

**Parse strategy:** The date parser should attempt multiple common date formats and normalize to the target period. It does not need to handle every possible format — just the reasonable ones a user might type when manually creating a block. If the content cannot be parsed at all (e.g., "random notes"), it is not matched, and the builder creates a new block alongside it.

---

## Reusable Block Builder Service

The auto-building logic should be extracted into a generic service that other features can use. The service is not specific to Today's Notes — it can create any block hierarchy from a specification.

### Interface

```
BlockBuilder

function buildPath(
    root: Block,
    path: [BuildStep],
    context: ModelContext
) -> Block

// Returns the deepest block in the path, creating any missing blocks along the way
```

### BuildStep

```
BuildStep
├── content: String              // The content to match / create
├── sortOrder: Double            // Sort order if creating
├── isDeletable: Bool            // default false for structural blocks
├── isContentEditableByUser: Bool      // default false for structural blocks
├── isReorderable: Bool          // default false for structural blocks
├── isMovable: Bool              // default false for structural blocks
├── matchStrategy: MatchStrategy // How to find existing blocks
└── extensionData: Data?         // default nil; optional metadata for the block
```

### MatchStrategy

```
enum MatchStrategy:
    case exactContent                // Exact string match (default for generic use)
    case dateAware(DateMatchType)    // Parse content as a date/period, match semantically + rename to canonical
    case metadata(key, value)        // Match by metadata field (future)

enum DateMatchType:
    case year       // Parse as year (e.g., "2026")
    case month      // Parse as month name (e.g., "March", "Mar", "Mar 2026")
    case week       // Parse as week number (e.g., "Week 1", "W1")
    case day        // Parse as calendar date (e.g., "Mar 1, 2026", "March 1", "1/3")
```

### Usage by Today's Notes

Today's Notes calls the service with a 4-step path, using date-aware matching:

```
buildPath(
    root: todayNotesRoot,
    path: [
        BuildStep(content: "2026", sortOrder: 2026.0, match: .dateAware(.year)),
        BuildStep(content: "March", sortOrder: 3.0, match: .dateAware(.month)),
        BuildStep(content: "Week 9 (23/2 - 1/3)", sortOrder: 9.0, match: .dateAware(.week)),
        BuildStep(content: "Mar 1, 2026", sortOrder: 1.0, match: .dateAware(.day))
    ],
    context: modelContext
)
```

### Usage by Other Features (Future)

AI editing could use the same service to create structured block hierarchies programmatically — e.g., block building a meeting notes template, a project plan, etc.

---

## Navigation & UI

### Entry Point

Today's Notes appears as a dedicated entry point, separate from the regular home screen list. Two options considered:

**Option A — Pinned root block:** Today's Notes is a regular root block on the home screen, but always pinned to the top (sorted first). Users drill into it like any other block. Navigation: Home → Today's Notes → 2026 → March → Week 1 (2/3 - 8/3) → Mar 2, 2026.

**Option B — Tab or sidebar entry:** Today's Notes has its own navigation entry (tab bar item, sidebar item, or floating button) that directly opens the Today's Notes root.

**Decision: Option A (pinned root block).** This keeps the architecture simple — Today's Notes is just a Block, navigated like any other Block. Pinning is achieved by giving it a very low sortOrder (e.g., `Double.leastNormalMagnitude`) so it always sorts first. A visual indicator (e.g., a pin icon or different styling) distinguishes it from regular root blocks.

### Global "Today" Button (Bottom Bar)

**Figma source:** [Home view with Today button](https://www.figma.com/design/9nh3TpDEoZx8Pt8hVUrJgV/Noto?node-id=94-465)

Every screen (home screen and all node views) has a **Today button** in the bottom toolbar, positioned to the **left of the search bar**. Tapping it navigates directly to today's day block from anywhere in the app.

**Visual spec (from Figma):**
- Liquid Glass pill button (`.glassEffect(in: .capsule)` with `.interactive()`)
- 48px height, capsule shape — same height as the search bar
- Contains a calendar icon (SF Symbol `calendar`, 17px SF Pro Medium, color #1a1a1a)
- 12px gap between the Today button and the search bar
- Both the Today button and search bar sit inside the bottom toolbar (28px horizontal padding, 32px bottom padding, 4px top padding)

**Behavior:**
- Tapping the Today button builds today's date hierarchy if needed, then pushes the full navigation path onto the NavigationStack: Today's Notes → Year → Month → Week → Day
- Works from any screen — home screen, any node view, even from within the Today's Notes hierarchy itself
- If the user is already on today's day block, the button is a no-op (or provides subtle visual feedback)

**Layout:**
```
┌─────────────────────────────────────────────┐
│  [📅]  [🔍 Ask anything or search     🎤]  │
│  Today   Search bar                         │
│  button                                     │
└─────────────────────────────────────────────┘
```

### Scrollable Breadcrumb

**Figma source:** [Today view with breadcrumb](https://www.figma.com/design/9nh3TpDEoZx8Pt8hVUrJgV/Noto?node-id=94-552)

The node view breadcrumb (top toolbar, between back button and trailing buttons) is updated to handle deep navigation paths gracefully.

**Problem:** Today's Notes paths can be 6 levels deep (Home / Today's Notes / 2026 / March / Week 9 (23/2 - 1/3) / Mar 1, 2026), which overflows the available horizontal space.

**Solution (from Figma):**
- The breadcrumb is **horizontally scrollable** and **right-aligned** — the deepest (current) segments are always visible, and earlier segments clip/scroll off to the left
- All segments are present in the scroll view — no collapsing or "+N" indicator
- Each breadcrumb segment displays the block's content directly — no label transformation needed
- "Home" (the root) is the only non-block label, always the first segment

**Visual spec:**
- Breadcrumb text: 15px SF Pro Medium, #727272, -0.25px letter-spacing, `whitespace: nowrap`
- Segments separated by " / " with 10px gap between elements
- The breadcrumb container has `overflow: clip` and is horizontally scrollable (no visible scrollbar)
- Content is **right-aligned** within the container — the rightmost (deepest/current) segments are always visible; earlier segments scroll off to the left
- The breadcrumb area fills remaining horizontal space between the back button (left) and sort/filter button (right), flexing (`flex: 1`)
- 24px gap between the leading group (back button + breadcrumb) and the trailing group (sort/filter button)

**Example:** For the path Home → Today's Notes → 2026 → March → Week 9 (23/2 - 1/3) → Mar 1, 2026:
```
Full breadcrumb:    Home / Today's Notes / 2026 / March / Week 9 (23/2 - 1/3) / Mar 1, 2026
Visible portion:                                          Week 9 (23/2 - 1/3) / Mar 1, 2026
                    ← scrollable ←
```

**Scope:** The scrollable breadcrumb applies to **all node views**, not just Today's Notes descendants. Regular (non-Today's Notes) node views also benefit from the overflow handling when deeply nested.

### Day Block View

The day block view is a standard NodeView. The user's journal entries and random thoughts are children of the day block. They can create, edit, indent, outdent, and reorder blocks exactly like in any other node view.

### Today's Notes Root View

When viewing the Today's Notes root block, the display follows the standard NodeView conventions:

- Year blocks appear as first-level children (plain text, no bullets)
- Month blocks appear as grandchildren (bulleted)
- Collapse/expand toggle works as normal

---

## First-Time Setup

### Creating the Today's Notes Root

On first launch (or if no "Today's Notes" root block exists), the app creates the root block:

```
function ensureTodayNotesRoot(context):
    // Search for existing root block with content "Today's Notes"
    root = fetchRootBlock(content: "Today's Notes", context: context)
    if root is nil:
        root = createBlock(
            parent: nil,
            content: "Today's Notes",
            sortOrder: Double.leastNormalMagnitude,
            depth: 0
        )
    return root
```

**When to run:** On app launch, before the home screen loads. This ensures the Today's Notes block always exists.

### Pinning Behavior

The Today's Notes root block stays pinned to the top of the home screen via its very low sortOrder. If the user reorders root blocks, Today's Notes should resist being moved (the reorder gesture is a no-op for the Today's Notes root block on the home screen).

---

## Edge Cases

### Midnight Rollover

If the user has the app open at midnight, auto-building does not trigger automatically mid-session. It triggers the next time they navigate to a Today's Notes descendant. This is acceptable — the block building is navigation-triggered, not timer-triggered.

### Timezone Changes

The block building uses the device's current locale/timezone. If the user travels across timezones, the "today" date changes accordingly. This may result in a day block being created in a different timezone than expected, which is acceptable for v1.

### Manual Block Creation

Users can manually create blocks at any level within Today's Notes. If the user creates a block that parses to the same date/period as a canonical block (e.g., "March 1" for Mar 1, 2026), the builder matches it and renames it to the canonical format. Blocks that don't parse as dates coexist alongside auto-built ones.

### Renaming Time Blocks

If a user renames a time block to something that still parses as the same date/period (e.g., "Mar" instead of "March"), the builder matches it and renames it back to the canonical format. If renamed to something unparseable (e.g., "My March Notes"), the builder cannot match it and creates a new canonical block alongside it.

### Week Spanning Two Months

A week that spans two months (e.g., Jan 29 – Feb 4) belongs to the month containing the Monday. So if Monday is Jan 29, the whole week lives under "January" (the 2026 year block), even if the user opens the app on Feb 1 (a Saturday in that week).

---

## State Management

| State                        | Type                          | Scope                    |
| ---------------------------- | ----------------------------- | ------------------------ |
| Today's Notes root block       | Fetched on app launch         | App-wide                 |
| Today's built day block      | Computed on navigation        | Per navigation event     |
| Pinned sort order            | `Double.leastNormalMagnitude` | Persistent on root block |

---

## Not in Scope

- **Templates / auto-fill:** Filling day blocks with journal prompt templates requires the Tags + Templates feature first
- **Notifications / reminders:** No push notifications to remind the user to journal
- **Calendar integration:** No reading from or writing to the system calendar
- **Recurring blocks:** No repeating block patterns beyond the time hierarchy
- **Time-of-day blocks:** Blocks are organized by day, not by hour/time

---

## Files to Create / Modify

| File                                          | Action | Description                                                                                  |
| --------------------------------------------- | ------ | -------------------------------------------------------------------------------------------- |
| `Noto/Models/Block.swift`                     | Modify | Add `isDeletable`, `isContentEditableByUser`, `isReorderable`, `isMovable` properties              |
| `Noto/Services/BlockBuilder.swift`            | Create | Generic reusable service for programmatically creating block hierarchies                     |
| `Noto/Services/TodayNotesService.swift`       | Create | Today's Notes–specific date formatting and build path construction                           |
| `Noto/Views/GlassTodayButton.swift`           | Create | Liquid Glass "Today" button component for the bottom toolbar                                 |
| `Noto/Views/ScrollableBreadcrumb.swift`       | Create | Horizontally scrollable, right-aligned breadcrumb view                                       |
| `Noto/ContentView.swift`                      | Modify | Pin Today's Notes root block, add Today button to bottom bar, guard protected blocks           |
| `Noto/Views/NodeView.swift`                   | Modify | Add Today button to bottom bar, integrate scrollable breadcrumb, guard protected blocks      |
| `Noto/TextKit/NoteTextView.swift`             | Modify | Disable backspace-delete and reorder gestures on protected blocks                            |
| `Noto/NotoApp.swift`                          | Modify | Ensure Today's Notes root exists on launch                                                     |
| `NotoTests/TodayNotesTests.swift`             | Create | Unit tests for block building and date logic                                                    |
| `NotoTests/BlockProtectionTests.swift`        | Create | Unit tests for block protection properties                                                   |

---

## Success Criteria

### Today's Notes Root

- [ ] "Today's Notes" root block is created on first app launch
- [ ] "Today's Notes" is always pinned to the top of the home screen
- [ ] Today's Notes root block cannot be reordered on the home screen
- [ ] Today's Notes root block can be drilled into like any other block

### Block Protection Properties

- [ ] `isDeletable`, `isContentEditableByUser`, `isReorderable`, `isMovable` added to Block model (all default `true`)
- [ ] All auto-built structural blocks have all four set to `false`
- [ ] `isDeletable = false`: Backspace on empty block is a no-op
- [ ] `isContentEditableByUser = false`: Tap does not enter edit mode for the block's text
- [ ] `isReorderable = false`: Long-press drag is a no-op
- [ ] `isMovable = false`: Indent/outdent operations are no-ops
- [ ] Children of restricted blocks retain full `true` defaults (freely editable, deletable, etc.)
- [ ] Existing (non-Today's Notes) blocks remain unaffected (all default to `true`)

### Auto-Building

- [ ] Opening Today's Notes builds Year → Month → Week → Day for today
- [ ] Block building is idempotent — running it twice for the same date creates no duplicates
- [ ] Year blocks sort chronologically
- [ ] Month blocks sort chronologically within their year
- [ ] Week blocks sort chronologically within their month
- [ ] Day blocks sort chronologically within their week
- [ ] Week assignment follows the Monday rule (week belongs to month of its Monday)

### Block Builder Service

- [ ] `BlockBuilder.buildPath()` creates missing blocks along a path
- [ ] Existing blocks are reused, not duplicated
- [ ] Service returns the deepest block in the path
- [ ] Service works with any block hierarchy, not just Today's Notes

### Global Today Button

- [ ] Today button appears in bottom toolbar on every screen (home + all node views)
- [ ] Tapping Today button navigates directly to today's day block from anywhere
- [ ] Today button builds today's hierarchy if needed before navigating
- [ ] Today button is a no-op when already on today's day block
- [ ] Today button uses Liquid Glass pill styling with calendar icon

### Scrollable Breadcrumb

- [ ] Breadcrumb is horizontally scrollable, right-aligned
- [ ] Deepest (current) segments are always visible
- [ ] Earlier segments clip/scroll off to the left
- [ ] Each segment shows the block's content directly (no label transformation)
- [ ] Standard node view drill-down works through the full hierarchy
- [ ] Scrollable breadcrumb works for all node views, not just Today's Notes

### Day Block Usage

- [ ] User can create child blocks under a day block (journal entries)
- [ ] All standard editing interactions work (create, delete, indent, outdent, reorder)
- [ ] Content is persisted like any other block

### Edge Cases

- [ ] Manual block creation within Today's Notes works alongside auto-built blocks
- [ ] Renamed time blocks don't prevent new block building
- [ ] Cross-month weeks are assigned to the month of their Monday
