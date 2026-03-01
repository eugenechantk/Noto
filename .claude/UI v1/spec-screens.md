# Feature Spec: Screens

Derived from [PRD-screens.md](PRD-screens.md). Each acceptance criterion is written as a testable scenario.

**Figma source:** [Home view](https://www.figma.com/design/9nh3TpDEoZx8Pt8hVUrJgV/Noto?node-id=23-707), [Node view](https://www.figma.com/design/9nh3TpDEoZx8Pt8hVUrJgV/Noto?node-id=24-705)

---

## Feature: Home Screen Display

### User Story

As a user, I want to see my root blocks as a clean list of text lines so the app feels like a simple note-taking app.

### Acceptance Criteria

**AC-HS-1: Root blocks render as plain text**
- Given: 3 root blocks exist with content "Alpha", "Beta", "Gamma"
- When: The home screen loads
- Then: All three blocks appear as plain text lines in sortOrder sequence
- And: No bullet points or indentation are visible

**AC-HS-2: Only root blocks are shown**
- Given: Root block "Parent" has child "Child A" and grandchild "Grandchild"
- When: The home screen loads
- Then: Only "Parent" appears as plain text
- And: "Child A" and "Grandchild" are NOT visible on the home screen

**AC-HS-3: Empty state shows tappable area**
- Given: No blocks exist in the data store
- When: The home screen loads
- Then: An empty tappable area is displayed
- And: Tapping it creates the first block and enters edit mode

**AC-HS-4: Content uses correct typography**
- Given: Blocks exist on the home screen
- When: Inspecting the content area
- Then: Text is SF Pro Regular 20px, line-height 28px, color #262626, letter-spacing -0.45px
- And: Blocks are separated by 10px vertical gap
- And: Content has 16px horizontal padding

---

## Feature: Home Screen Toolbar

### User Story

As a user, I want to see the app title and have access to sorting/filtering at the top of the home screen.

### Acceptance Criteria

**AC-HT-1: Home title and subtitle displayed**
- Given: The home screen loads
- When: Inspecting the top toolbar
- Then: "Home" appears as a large title (34px SF Pro Bold)
- And: A subtitle area is visible below the title (15px SF Pro Medium, #727272)

**AC-HT-2: Sort/filter button uses Liquid Glass**
- Given: The home screen loads
- When: Inspecting the top toolbar
- Then: A sort/filter button (⇅ icon) appears on the top-right
- And: The button uses `.glassEffect(in: .capsule)` with `.interactive()` (Liquid Glass pill)

**AC-HT-3: Bottom search bar uses Liquid Glass**
- Given: The home screen loads
- When: Inspecting the bottom of the screen
- Then: A pill-shaped search bar is visible using `.glassEffect(in: .capsule)` (Liquid Glass material)
- And: Placeholder text reads "Ask anything or search"
- And: A search icon is on the left, a microphone icon is on the right

---

## Feature: Node Screen Display

### User Story

As a user, I want to drill into a block and see its children as a note page with the block as a heading, so I can focus on one topic at a time.

### Acceptance Criteria

**AC-NS-1: Heading displays node content**
- Given: A block "Not too bad" is double-tapped
- When: The node screen loads
- Then: "Not too bad" appears as a large title heading (34px SF Pro Bold, #1a1a1a)

**AC-NS-2: First-level children render as plain body text**
- Given: A node with children "Idea A", "Idea B", "Idea C"
- When: The node screen loads (collapsed)
- Then: Children appear as body text (20px SF Pro Regular, line-height 25px) with no bullets

**AC-NS-3: Grandchildren render with filled circle bullet**
- Given: A node → child "Idea A" → grandchild "Detail 1"
- When: The node screen loads (collapsed or expanded)
- Then: "Detail 1" appears with a filled circle (•) bullet at 30px indent

**AC-NS-4: Great-grandchildren render with hollow circle bullet**
- Given: A node → child → grandchild → great-grandchild "Sub-detail"
- When: The node screen loads (expanded)
- Then: "Sub-detail" appears with a hollow circle (◦) bullet at 60px indent

**AC-NS-5: Depth 3+ descendants render with dash bullet**
- Given: A descendant at indent level 3 or deeper
- When: Visible on the node screen (expanded)
- Then: It appears with a dash (–) bullet

**AC-NS-6: Indentation formula is correct**
- Given: currentNode.depth = D, a descendant block.depth = D + N
- When: The block is rendered
- Then: Its indent level = N - 1, and visual indent = (N - 1) * 30px

**AC-NS-7: Content spacing matches design**
- Given: Multiple children visible on the node screen
- When: Inspecting the content area
- Then: Blocks are separated by 10px vertical gap
- And: Content has 16px horizontal padding

---

## Feature: Node Screen Toolbar

### User Story

As a user, I want breadcrumb navigation and controls at the top of the node screen to orient myself and navigate.

### Acceptance Criteria

**AC-NT-1: Back button uses Liquid Glass**
- Given: A node screen is displayed
- When: Inspecting the toolbar
- Then: A back button (‹ chevron) appears on the left using `.glassEffect(in: .capsule)` with `.interactive()` (Liquid Glass pill)

**AC-NT-2: Breadcrumb navigation shows path**
- Given: The navigation path is Home → "Not too bad"
- When: The node screen loads
- Then: Breadcrumb text "Home / Not too bad" appears next to the back button (15px SF Pro Medium, #727272)

**AC-NT-3: Nested breadcrumb updates correctly**
- Given: The navigation path is Home → "Parent" → "Child"
- When: The "Child" node screen loads
- Then: Breadcrumb shows "Home / Parent / Child"

**AC-NT-4: Sort/filter button uses Liquid Glass**
- Given: A node screen is displayed
- When: Inspecting the toolbar
- Then: A sort/filter button (⇅ icon) appears on the right using `.glassEffect(in: .capsule)` with `.interactive()` (Liquid Glass pill)
- And: When adjacent to the back button, both are wrapped in `GlassEffectContainer` for proper blending

**AC-NT-5: Tag subtitle displayed under title**
- Given: A node has tag "#daily"
- When: The node screen loads
- Then: "#daily" appears below the title in red text (15px SF Pro Medium)

**AC-NT-6: Bottom search bar uses Liquid Glass**
- Given: A node screen is displayed
- When: Inspecting the bottom of the screen
- Then: The same Liquid Glass pill-shaped search bar as the home screen is visible (`.glassEffect(in: .capsule)`)

---

## Feature: Expand / Collapse Toggle

### User Story

As a user, I want to toggle between seeing just immediate children and all descendants so I can control how much detail I see.

### Acceptance Criteria

**AC-EC-1: Default state is collapsed**
- Given: A node screen is opened
- When: It first loads
- Then: The expand/collapse toggle shows "Expand All"
- And: Only first-level children and their immediate descendants are visible

**AC-EC-2: Expand shows all descendants**
- Given: A node with children, grandchildren, and great-grandchildren
- When: The "Expand All" button is tapped
- Then: All descendants at every depth level become visible
- And: The button text/icon changes to "Collapse"

**AC-EC-3: Collapse hides deep descendants**
- Given: The node screen is in expanded state
- When: The "Collapse" button is tapped
- Then: Only first-level children and their immediate descendants are visible
- And: The button text/icon changes back to "Expand All"

**AC-EC-4: First-level children never have bullets regardless of toggle**
- Given: The node screen is in either collapsed or expanded state
- When: Viewing first-level children
- Then: They always render as plain text without bullets

---

## Feature: Navigation

### User Story

As a user, I want to drill into any block via double-tap and navigate back, creating an unlimited drill-down path.

### Acceptance Criteria

**AC-NAV-1: Double-tap pushes node view**
- Given: A block "Topic A" on the home screen
- When: The user double-taps "Topic A"
- Then: A node view for "Topic A" is pushed onto the NavigationStack

**AC-NAV-2: Nested double-tap continues drill-down**
- Given: The user is in the node view for "Topic A", which has child "Subtopic B"
- When: The user double-taps "Subtopic B"
- Then: A node view for "Subtopic B" is pushed onto the stack
- And: The breadcrumb shows "Home / Topic A / Subtopic B"

**AC-NAV-3: Back button pops to previous screen**
- Given: The navigation path is Home → Topic A → Subtopic B
- When: The user taps the back button
- Then: The "Subtopic B" node view is popped
- And: The user sees the "Topic A" node view

**AC-NAV-4: Back from first node returns to home**
- Given: The navigation path is Home → Topic A
- When: The user taps the back button
- Then: The "Topic A" node view is popped
- And: The user sees the home screen

---

## Feature: Edit Mode (Visual)

### User Story

As a user, I want a keyboard and format bar to appear when I tap on text so I can edit blocks naturally.

### Acceptance Criteria

**AC-EMV-1: Tapping block text shows keyboard and format bar**
- Given: The user is on any screen with blocks
- When: The user taps on a block's text
- Then: The keyboard appears
- And: The format bar appears above the keyboard (iOS)
- And: A cursor appears in the block's text

**AC-EMV-2: Format bar has three buttons**
- Given: Edit mode is active (iOS)
- When: Inspecting the format bar
- Then: Three buttons are visible: Indent (→), Outdent (←), Mention (@)

**AC-EMV-3: Indent disabled for first sibling**
- Given: The user is editing the first block (no previous sibling)
- When: Inspecting the format bar
- Then: The Indent button is greyed out / disabled

**AC-EMV-4: Outdent disabled for root block**
- Given: The user is editing a root-level block (depth = 0)
- When: Inspecting the format bar
- Then: The Outdent button is greyed out / disabled

**AC-EMV-5: Mention button greyed out in v1**
- Given: Edit mode is active (iOS)
- When: Inspecting the format bar
- Then: The Mention (@) button is greyed out / disabled

**AC-EMV-6: Tapping outside exits edit mode**
- Given: The user is in edit mode
- When: The user taps outside the text area
- Then: The keyboard and format bar dismiss
- And: The block's content is saved
