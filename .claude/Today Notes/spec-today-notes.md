# Feature Spec: Today's Notes

Derived from [PRD-today-notes.md](PRD-today-notes.md). Each acceptance criterion is written as a testable scenario.

**Figma source:** [Home view with Today button](https://www.figma.com/design/9nh3TpDEoZx8Pt8hVUrJgV/Noto?node-id=94-465), [Today view with breadcrumb](https://www.figma.com/design/9nh3TpDEoZx8Pt8hVUrJgV/Noto?node-id=94-552)

---

## Feature: Today's Notes Root Block

### User Story

As a user, I want a permanent "Today's Notes" block pinned to the top of my home screen so I always have a dedicated place for daily notes.

### Acceptance Criteria

**AC-TNR-1: Root block created on first launch**
- Given: The app is launched for the first time (no blocks exist)
- When: The home screen loads
- Then: A root block with content "Today's Notes" exists
- And: It has `parentId = nil`, `depth = 0`
- And: Its `sortOrder` is `Double.leastNormalMagnitude` (always sorts first)

**AC-TNR-2: Root block is idempotent**
- Given: A "Today's Notes" root block already exists
- When: The app launches again
- Then: No duplicate "Today's Notes" root block is created
- And: The existing root block is unchanged

**AC-TNR-3: Root block pinned to top**
- Given: Root blocks "Alpha" (sortOrder 1.0), "Beta" (sortOrder 2.0) exist alongside "Today's Notes"
- When: The home screen loads
- Then: "Today's Notes" appears as the first block in the list (above "Alpha" and "Beta")

**AC-TNR-4: Root block resists reordering**
- Given: "Today's Notes" is the first root block on the home screen
- When: The user attempts to reorder "Today's Notes" via long-press drag
- Then: The reorder operation is a no-op (`isReorderable = false`)
- And: "Today's Notes" remains at the top

**AC-TNR-5: Root block drills into node view**
- Given: "Today's Notes" root block exists
- When: The user double-taps "Today's Notes"
- Then: A node view for "Today's Notes" is pushed onto the NavigationStack
- And: Year blocks (if any) appear as first-level children

---

## Feature: Block Protection Properties

### User Story

As a user, I want structural blocks (Today's Notes, year, month, week, day) to have individual protections so I can see exactly what's restricted and I don't accidentally destroy the time hierarchy.

### Acceptance Criteria

**AC-BP-1: isDeletable = false prevents deletion**
- Given: The "2026" year block has `isDeletable = false` and is empty
- When: The user focuses on "2026" and presses Backspace
- Then: The block is NOT deleted
- And: No content or structural changes occur

**AC-BP-2: isContentEditableByUser = false prevents editing**
- Given: The "March" month block has `isContentEditableByUser = false`
- When: The user taps on the "March" text to enter edit mode
- Then: The block's content cannot be modified
- And: The system-managed label "March" remains unchanged

**AC-BP-3: isReorderable = false prevents reordering**
- Given: Year blocks "2025" and "2026" exist under Today's Notes, both with `isReorderable = false`
- When: The user long-presses "2026" to reorder
- Then: The reorder gesture is a no-op
- And: "2025" and "2026" remain in their original order

**AC-BP-4: isMovable = false prevents indent and outdent**
- Given: The "March" month block has `isMovable = false` under "2026"
- When: The user attempts to indent or outdent "March"
- Then: The operation is a no-op
- And: "March" remains a child of "2026"

**AC-BP-5: Children of restricted blocks are freely deletable**
- Given: The user has created child blocks "Idea A" and "Idea B" under the restricted "Mar 1, 2026" day block
- When: The user empties "Idea A" and presses Backspace
- Then: "Idea A" is deleted normally
- And: "Idea B" and the "Mar 1, 2026" day block remain

**AC-BP-6: Children of restricted blocks support all editing**
- Given: Child blocks exist under a restricted day block
- When: The user indents, outdents, reorders, or edits those child blocks
- Then: All operations work identically to any other node view

**AC-BP-7: All properties default to true for regular blocks**
- Given: The user creates a new block on the home screen or in any node view
- When: The block is created
- Then: `isDeletable`, `isContentEditableByUser`, `isReorderable`, and `isMovable` are all `true`
- And: The block can be deleted, reordered, indented, outdented, and edited normally

**AC-BP-8: Auto-built blocks have all restrictions set**
- Given: Block building runs for a new date
- When: Year, month, week, and day blocks are created
- Then: All four blocks have `isDeletable = false`, `isContentEditableByUser = false`, `isReorderable = false`, `isMovable = false`

---

## Feature: Auto-Building

### User Story

As a user, I want the Year → Month → Week → Day hierarchy to be created automatically and instantly for today's date, so I never have to set up the structure manually and can start writing immediately.

### Acceptance Criteria

**AC-AB-1: Full hierarchy built on first navigation**
- Given: "Today's Notes" root exists with no children; today is Mar 2, 2026 (a Monday)
- When: The user navigates to the Today's Notes root (or taps the Today button)
- Then: Four new blocks are created:
  - "2026" (child of Today's Notes, depth 1)
  - "March" (child of "2026", depth 2)
  - "Week 1 (2/3 - 8/3)" (child of "March", depth 3)
  - "Mar 2, 2026" (child of "Week 1 (2/3 - 8/3)", depth 4)

**AC-AB-2: Building is idempotent**
- Given: Today is Mar 2, 2026; the full hierarchy already exists for this date
- When: The user navigates to the Today's Notes root again
- Then: No new blocks are created
- And: The existing hierarchy is unchanged

**AC-AB-3: New day within same week**
- Given: Today's hierarchy (Mar 2, 2026) exists under "Week 1 (2/3 - 8/3)"
- When: Tomorrow (Mar 3, 2026) arrives and the user navigates to Today's Notes
- Then: Only one new block is created: "Mar 3, 2026" under the existing "Week 1 (2/3 - 8/3)"
- And: "2026", "March", and "Week 1 (2/3 - 8/3)" are reused

**AC-AB-4: New week within same month**
- Given: Blocks exist for "March" with "Week 1 (2/3 - 8/3)"
- When: Mar 9, 2026 (next Monday) arrives and the user navigates to Today's Notes
- Then: Two new blocks are created:
  - "Week 2 (9/3 - 15/3)" under "March"
  - "Mar 9, 2026" under "Week 2 (9/3 - 15/3)"
- And: "2026" and "March" are reused

**AC-AB-5: New month**
- Given: Blocks exist for "2026" with "March"
- When: Apr 6, 2026 (a Monday) arrives and the user navigates to Today's Notes
- Then: Three new blocks are created:
  - "April" under "2026"
  - "Week 1 (6/4 - 12/4)" under "April"
  - "Apr 6, 2026" under "Week 1 (6/4 - 12/4)"
- And: "2026" is reused

**AC-AB-6: New year**
- Given: Blocks exist for "2026"
- When: Jan 5, 2027 (first Monday of Jan 2027) arrives and the user navigates to Today's Notes
- Then: Four new blocks are created:
  - "2027" under Today's Notes root
  - "January" under "2027"
  - "Week 1 (5/1 - 11/1)" under "January"
  - "Jan 5, 2027" under "Week 1 (5/1 - 11/1)"

**AC-AB-7: Year blocks sort chronologically**
- Given: Year blocks "2026" and "2027" exist
- When: Viewing Today's Notes root
- Then: "2026" appears before "2027" (sorted by sortOrder)

**AC-AB-8: Month blocks sort chronologically**
- Given: Month blocks "January", "February", "March" exist under "2026"
- When: Viewing the "2026" node
- Then: Months appear in calendar order (January, February, March)

**AC-AB-9: Week assigned to month of its Monday**
- Given: Today is Mar 1, 2026 (Sunday); the Monday of this week is Feb 23, 2026
- When: Block building runs for Mar 1, 2026
- Then: The week block "Week 9 (23/2 - 1/3)" is created under "February" (not "March")
- And: The day block "Mar 1, 2026" lives under that week in "February"

**AC-AB-10: Day blocks sort chronologically within week**
- Given: Day blocks "Mar 2, 2026", "Mar 3, 2026", "Mar 4, 2026" exist in the same week
- When: Viewing the week node
- Then: Days appear in chronological order

**AC-AB-11: Building triggers on navigating to any Today's Notes descendant**
- Given: The user navigates directly to "2026" (a year block under Today's Notes)
- When: The node view loads
- Then: Block building still runs, ensuring today's hierarchy exists

**AC-AB-12: Building is instant — no visible latency**
- Given: The user taps the Today button or navigates to Today's Notes
- When: Block building runs
- Then: The view appears immediately with no loading spinner or async delay
- And: Navigation feels identical to opening any other node view

---

## Feature: Block Builder Service

### User Story

As a developer, I want a generic block builder service so that any feature can programmatically create hierarchical block structures without duplicating logic.

### Acceptance Criteria

**AC-BB-1: Service creates missing blocks along a path**
- Given: A root block with no children
- When: `buildPath(root, path: [step1, step2, step3])` is called
- Then: Three new child blocks are created, each nested under the previous
- And: The deepest block is returned

**AC-BB-2: Service reuses existing blocks**
- Given: A root block with child "A" (matching step1.content)
- When: `buildPath(root, path: [step1, step2])` is called
- Then: "A" is reused (not duplicated)
- And: Only one new block is created (for step2, under "A")

**AC-BB-3: Service handles fully existing path**
- Given: The full path [step1, step2, step3] already exists
- When: `buildPath(root, path: [step1, step2, step3])` is called
- Then: No new blocks are created
- And: The existing deepest block is returned

**AC-BB-4: Service sets correct parent and depth**
- Given: Root block at depth 0
- When: `buildPath(root, path: [step1, step2])` is called
- Then: step1 block has depth 1, parentId = root.id
- And: step2 block has depth 2, parentId = step1Block.id

**AC-BB-5: Service uses provided sortOrder**
- Given: `step1.sortOrder = 3.0`
- When: The block for step1 is created
- Then: The new block's sortOrder = 3.0

**AC-BB-6: Service sets protection properties from BuildStep**
- Given: `step1.isDeletable = false, step1.isContentEditableByUser = false, step1.isReorderable = false, step1.isMovable = false`
- When: The block for step1 is created
- Then: The new block's protection properties match the BuildStep values

**AC-BB-7: Service matches by exact content (exactContent strategy)**
- Given: Root has children "Alpha" and "Alpha Beta"; step uses `.exactContent`
- When: `buildPath(root, path: [BuildStep(content: "Alpha", ...)])` is called
- Then: "Alpha" is matched (exact match), not "Alpha Beta"

**AC-BB-8: Service ignores archived blocks**
- Given: Root has child "Alpha" with `isArchived = true`
- When: `buildPath(root, path: [BuildStep(content: "Alpha", ...)])` is called
- Then: A new "Alpha" block is created (archived one is ignored)

**AC-BB-8a: Service sets extensionData from BuildStep**
- Given: `step1.extensionData = someData`
- When: The block for step1 is created
- Then: The new block's `extensionData` equals `someData`
- And: If `extensionData` is nil (default), the block's `extensionData` is nil

**AC-BB-9: Date-aware matching finds fuzzy day match**
- Given: A week block has child "March 1" (user-created); step uses `.dateAware(.day)` with content "Mar 1, 2026"
- When: `buildPath` is called
- Then: "March 1" is matched as the same day
- And: Its content is renamed to "Mar 1, 2026"

**AC-BB-10: Date-aware matching finds fuzzy month match**
- Given: A year block has child "Mar" (user-created); step uses `.dateAware(.month)` with content "March"
- When: `buildPath` is called
- Then: "Mar" is matched as the same month
- And: Its content is renamed to "March"

**AC-BB-11: Date-aware matching finds fuzzy week match**
- Given: A month block has child "Week 1" (user-created); step uses `.dateAware(.week)` with content "Week 1 (2/3 - 8/3)"
- When: `buildPath` is called
- Then: "Week 1" is matched as the same week
- And: Its content is renamed to "Week 1 (2/3 - 8/3)"

**AC-BB-12: Date-aware matching does not match unparseable content**
- Given: A year block has child "My March Notes" (user-created); step uses `.dateAware(.month)` with content "March"
- When: `buildPath` is called
- Then: "My March Notes" is NOT matched (cannot parse as a month)
- And: A new "March" block is created alongside it

**AC-BB-13: Date-aware rename preserves block identity**
- Given: "March 1" block has child blocks "Idea A" and "Idea B"
- When: The builder matches "March 1" and renames it to "Mar 1, 2026"
- Then: The block's `id` is unchanged
- And: "Idea A" and "Idea B" remain as children

---

## Feature: Today's Notes Date Formatting

### User Story

As a user, I want time hierarchy blocks to have consistent, readable date labels so I can quickly find notes by time period.

### Acceptance Criteria

**AC-DF-1: Year format**
- Given: The year is 2026
- When: A year block is created
- Then: Its content is `"2026"`

**AC-DF-2: Month format**
- Given: The month is March 2026
- When: A month block is created
- Then: Its content is `"March"` (full month name, no year)

**AC-DF-3: Week format — standard week**
- Given: A week starting Monday 2/3/2026 and ending Sunday 8/3/2026
- When: A week block is created
- Then: Its content is `"Week 1 (2/3 - 8/3)"` (hyphen separator, D/M format)
- And: The week number is relative to the month (first week whose Monday falls in March = Week 1)

**AC-DF-4: Week format — week spanning month boundary**
- Given: A week starting Monday 23/2/2026 and ending Sunday 1/3/2026
- When: A week block is created (under February, per the Monday rule)
- Then: Its content is `"Week 4 (23/2 - 1/3)"`

**AC-DF-5: Day format**
- Given: The date is March 1, 2026
- When: A day block is created
- Then: Its content is `"Mar 1, 2026"` (MMM D, YYYY)

**AC-DF-6: Week numbering resets per month**
- Given: The first Monday-containing week of March is Week 1
- When: The next week starts
- Then: It is numbered Week 2, and so on

**AC-DF-7: Week number calculation**
- Week number within a month is determined by counting how many Mondays in that month have occurred up to and including the current week's Monday
- The first week whose Monday falls in the month is Week 1

**AC-DF-8: Week boundaries are Monday to Sunday**
- Given: Any week block
- When: Inspecting its date range
- Then: The first date (left of hyphen) is always a Monday
- And: The second date (right of hyphen) is always a Sunday

---

## Feature: Global Today Button

### User Story

As a user, I want a one-tap button on every screen to jump directly to today's day block, so I can capture thoughts instantly from anywhere in the app.

### Acceptance Criteria

**AC-GT-1: Today button appears on home screen bottom bar**
- Given: The home screen loads
- When: Inspecting the bottom toolbar
- Then: A Today button (calendar icon, Liquid Glass pill) appears to the left of the search bar
- And: There is a 12px gap between the Today button and the search bar

**AC-GT-2: Today button appears on all node view bottom bars**
- Given: The user is in any node view (regular or Today's Notes descendant)
- When: Inspecting the bottom toolbar
- Then: The same Today button appears to the left of the search bar

**AC-GT-3: Today button navigates to today's day block**
- Given: The user taps the Today button; today is Mar 1, 2026
- When: Navigation completes
- Then: The user is on the node view for the "Mar 1, 2026" day block
- And: The NavigationStack contains the full path: Today's Notes → 2026 → March → Week 9 (23/2 - 1/3) → Mar 1, 2026

**AC-GT-4: Today button builds hierarchy if needed**
- Given: Today is a new date with no existing hierarchy
- When: The user taps the Today button
- Then: The missing Year/Month/Week/Day blocks are built first (instantly)
- And: Then navigation proceeds to the newly created day block

**AC-GT-5: Today button is a no-op when already on today**
- Given: The user is already viewing today's day block
- When: The user taps the Today button
- Then: Nothing happens (or subtle visual feedback is provided)

**AC-GT-6: Today button uses correct Liquid Glass styling**
- Given: The bottom toolbar is visible
- When: Inspecting the Today button
- Then: It uses `.glassEffect(in: .capsule)` with `.interactive()`
- And: It is 48px height with a calendar SF Symbol icon (17px SF Pro Medium, #1a1a1a)

**AC-GT-7: Today button pushes full navigation path**
- Given: The user taps the Today button from any screen
- When: Navigation completes
- Then: The user can tap Back to navigate up through each level of the Today's Notes hierarchy

---

## Feature: Scrollable Breadcrumb

### User Story

As a user, I want the breadcrumb to handle deep Today's Notes paths gracefully by scrolling horizontally and always showing where I currently am.

### Acceptance Criteria

**AC-SB-1: Breadcrumb is right-aligned**
- Given: The breadcrumb path is "Home / Today's Notes / 2026 / March / Week 9 (23/2 - 1/3) / Mar 1, 2026"
- When: The breadcrumb renders in the toolbar
- Then: The rightmost segments (deepest/current) are always visible
- And: Earlier segments clip off to the left

**AC-SB-2: Breadcrumb is horizontally scrollable**
- Given: The breadcrumb overflows the available space
- When: The user scrolls the breadcrumb to the left
- Then: Earlier segments become visible (e.g., "Home / Today's Notes / 2026")

**AC-SB-3: Breadcrumb shows block content directly**
- Given: The navigation path is Today's Notes → 2026 → March → Week 9 (23/2 - 1/3) → Mar 1, 2026
- When: The breadcrumb renders
- Then: Each segment shows the block's content as-is: "Home / Today's Notes / 2026 / March / Week 9 (23/2 - 1/3) / Mar 1, 2026"

**AC-SB-4: Breadcrumb uses correct typography**
- Given: The breadcrumb is visible
- When: Inspecting the breadcrumb text
- Then: It uses 15px SF Pro Medium, #727272, -0.25px letter-spacing, `whitespace: nowrap`
- And: Segments are separated by " / " with 10px gap between elements

**AC-SB-5: Breadcrumb fills available space**
- Given: A node view toolbar with back button (left) and sort/filter button (right)
- When: The breadcrumb renders
- Then: It fills the remaining horizontal space between the buttons (flex: 1)
- And: There is a 24px gap between the leading group and trailing group

**AC-SB-6: Scrollable breadcrumb works for all node views**
- Given: The user is in a deeply nested regular (non-Today's Notes) node
- When: The breadcrumb overflows
- Then: It scrolls and clips the same way as for Today's Notes paths

---

## Feature: Home Screen Integration

### User Story

As a user, I want Today's Notes to appear on my home screen as the first item, visually distinguishable from regular notes.

### Acceptance Criteria

**AC-HSI-1: Today's Notes appears first on home screen**
- Given: Root blocks "Alpha", "Beta", and "Today's Notes" exist
- When: The home screen loads
- Then: "Today's Notes" appears as the first block
- And: "Alpha" and "Beta" appear after it in their normal sort order

**AC-HSI-2: Today's Notes has visual indicator**
- Given: The home screen displays "Today's Notes" as the first block
- When: Inspecting the block
- Then: There is a visual distinction from regular blocks (e.g., pin icon, different text styling, or a subtle separator)

**AC-HSI-3: Today's Notes persists across app restarts**
- Given: The app is closed and reopened
- When: The home screen loads
- Then: "Today's Notes" still appears as the first pinned block
- And: All previously built time blocks still exist

---

## Feature: Day Block Editing

### User Story

As a user, I want to write journal entries and dump ideas as child blocks under a day block, using all the standard editing features.

### Acceptance Criteria

**AC-DBE-1: Creating blocks under a day**
- Given: The user is in the node view for "Mar 2, 2026" (a day block)
- When: The user presses Return or taps empty space
- Then: A new child block is created under the day block
- And: The block enters edit mode

**AC-DBE-2: All editing interactions work**
- Given: Child blocks exist under a day block
- When: The user edits, indents, outdents, or reorders blocks
- Then: All operations work identically to any other node view

**AC-DBE-3: Content persists**
- Given: The user writes "Had a great idea about X" under the day block
- When: The user navigates away and comes back
- Then: The content "Had a great idea about X" is still there

**AC-DBE-4: Day blocks support deep nesting**
- Given: The user is in a day block node view
- When: The user indents blocks multiple levels
- Then: Blocks can be nested arbitrarily deep within the day block (depth 5+)

---

## Feature: Edge Cases

### User Story

As a user, I want Today's Notes to behave predictably across unusual scenarios like timezone changes, manual edits to time blocks, and midnight rollovers.

### Acceptance Criteria

**AC-EC-1: Manual blocks coexist with auto-built blocks**
- Given: "Week 1 (2/3 - 8/3)" exists under "March"
- When: The user manually creates a sibling block "My Custom Week" under "March"
- Then: Both "Week 1 (2/3 - 8/3)" and "My Custom Week" exist
- And: Block building does not affect "My Custom Week"

**AC-EC-2: Renamed time block causes new block creation**
- Given: The user renames "March" to "March Notes"
- When: Block building runs for a March date
- Then: A new "March" block is created under "2026"
- And: "March Notes" remains as a separate block with its children intact

**AC-EC-3: Block building uses device timezone**
- Given: The device timezone is set to UTC+8
- When: Block building runs at 11pm UTC (7am next day in UTC+8)
- Then: The day block corresponds to the UTC+8 date (next day), not the UTC date

**AC-EC-4: No timer-based block building**
- Given: The app is open at 11:59pm
- When: Midnight passes (new day begins)
- Then: No new blocks are automatically created mid-session
- And: Block building triggers only on next navigation to Today's Notes or tap of Today button

**AC-EC-5: Archived day block gets re-created**
- Given: The user archives (soft-deletes) "Mar 2, 2026" day block
- When: Block building runs for Mar 2, 2026
- Then: A new "Mar 2, 2026" block is created (the archived one is ignored)

---

## Required Tests

### Block Protection Property Tests

- `testIsDeletableFalsePreventsBackspaceDelete` — Backspace on empty block with `isDeletable = false` is a no-op
- `testIsContentEditableFalsePreventsEditing` — Block with `isContentEditableByUser = false` cannot enter edit mode
- `testIsReorderableFalsePreventsReorder` — Reorder gesture is no-op on blocks with `isReorderable = false`
- `testIsMovableFalsePreventsIndent` — Indent is no-op on blocks with `isMovable = false`
- `testIsMovableFalsePreventsOutdent` — Outdent is no-op on blocks with `isMovable = false`
- `testChildrenOfRestrictedBlockDeletable` — User-created children under restricted blocks delete normally
- `testChildrenOfRestrictedBlockEditable` — All editing operations work on children of restricted blocks
- `testAllPropertiesDefaultTrue` — New blocks have all four properties set to `true` by default
- `testAutoBuiltBlocksHaveAllRestrictions` — Auto-built blocks have all four set to `false`

### Block Builder Service Tests

- `testBuildPathCreatesFullPath` — Creating blocks from empty root produces all levels
- `testBuildPathReusesExistingBlocks` — Existing intermediate blocks are not duplicated
- `testBuildPathIdempotent` — Running twice for the same path creates no duplicates
- `testBuildPathSetsCorrectDepth` — Each level has correct depth relative to root
- `testBuildPathSetsCorrectParent` — Each block's parentId points to the block above it
- `testBuildPathUsesProvidedSortOrder` — Sort orders from BuildStep are applied
- `testBuildPathSetsProtectionProperties` — Protection property values from BuildStep are applied
- `testBuildPathIgnoresArchivedBlocks` — Archived children are not matched
- `testBuildPathExactContentMatch` — Partial content matches are not matched
- `testBuildPathSetsExtensionData` — Extension data from BuildStep is applied to created block

### Today's Notes Date Logic Tests

- `testYearContentFormat` — Formats year as "YYYY" (e.g., "2026")
- `testMonthContentFormat` — Formats month as full name (e.g., "March")
- `testWeekContentFormat` — Formats week as "Week N (D/M - D/M)" with hyphen
- `testDayContentFormat` — Formats day as "MMM D, YYYY" (e.g., "Mar 1, 2026")
- `testWeekAssignedToMondayMonth` — Cross-month week belongs to Monday's month
- `testWeekNumberResetsPerMonth` — Week numbering starts at 1 each month
- `testWeekBoundariesMondayToSunday` — Week range always starts Monday, ends Sunday
- `testWeekSortOrder` — Week blocks sort chronologically within month
- `testDaySortOrder` — Day blocks sort chronologically within week
- `testMonthSortOrder` — Month blocks sort chronologically within year
- `testYearSortOrder` — Year blocks sort chronologically

### Today's Notes Building Integration Tests

- `testBuildTodayCreatesFullHierarchy` — From empty Today's Notes root, creates Year → Month → Week → Day
- `testBuildTodayIdempotent` — Running for the same date twice creates no duplicates
- `testBuildNewDaySameWeek` — Only creates the new day block
- `testBuildNewWeekSameMonth` — Creates new week and day blocks
- `testBuildNewMonth` — Creates new month, week, and day blocks
- `testBuildNewYear` — Creates new year, month, week, and day blocks
- `testBuildCrossMonthWeek` — Week spanning month boundary lives under Monday's month

### Today's Notes Root Tests

- `testTodayNotesRootCreatedOnLaunch` — Root block exists after first launch
- `testTodayNotesRootIdempotent` — No duplicate root on subsequent launches
- `testTodayNotesRootPinnedFirst` — SortOrder ensures it sorts before other root blocks
- `testTodayNotesRootReorderBlocked` — Reorder gesture is no-op for Today's Notes root

### Global Today Button Tests

- `testTodayButtonNavigatesToDayBlock` — Full path pushed onto NavigationStack
- `testTodayButtonBuildsIfNeeded` — Missing blocks created before navigation
- `testTodayButtonAppearsOnHomeScreen` — Button visible in home screen bottom bar
- `testTodayButtonAppearsOnAllNodeViews` — Button visible in all node view bottom bars
- `testTodayButtonNoOpWhenOnToday` — No navigation when already on today's day block

### Scrollable Breadcrumb Tests

- `testBreadcrumbShowsFullPath` — All segments present for deep paths
- `testBreadcrumbRightAligned` — Deepest segments visible, earlier ones clipped
- `testBreadcrumbScrollable` — User can scroll to reveal clipped segments
- `testBreadcrumbShowsBlockContent` — Each segment matches its block's content
- `testBreadcrumbWorksForAllNodeViews` — Scrollable behavior applies to non-Today's Notes nodes too
