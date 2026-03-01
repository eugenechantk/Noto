# Screens

Layout, navigation, and visual design for the two primary screens. The key design principle: it should feel like a normal note-taking app (Apple Notes), not an outliner with bullets and indentation.

**Figma source:** [Home view](https://www.figma.com/design/9nh3TpDEoZx8Pt8hVUrJgV/Noto?node-id=23-707), [Node view](https://www.figma.com/design/9nh3TpDEoZx8Pt8hVUrJgV/Noto?node-id=24-705)

---

## Shared Typography & Spacing

From the Figma designs:

| Element | Font | Size | Weight | Line Height | Color | Letter Spacing |
|---|---|---|---|---|---|---|
| Large title | SF Pro | 34px | Bold (700) | 41px | #1a1a1a | +0.4px |
| Subtitle / breadcrumb | SF Pro | 15px | Medium | 20px | #727272 | -0.25px |
| Content (home) | SF Pro | 20px | Regular (400) | 28px | #262626 | -0.45px |
| Content (node) | SF Pro | 20px | Regular (400) | 25px | black | -0.45px |
| Tag subtitle | SF Pro | 15px | Medium | 20px | red (system) | -0.25px |

- **Block spacing:** 10px vertical gap between blocks
- **Content padding:** 16px horizontal
- **Bullet indent:** 30px per level

---

## Liquid Glass Design Convention

All chrome UI elements (toolbars, buttons, search bar) use Apple's **Liquid Glass** design language. Implementation uses the `.glassEffect()` modifier (SwiftUI) or `UIGlassEffect` + `UIVisualEffectView` (UIKit).

Key principles:
- Use `.glassEffect()` instead of `.background(.material)` for all glass surfaces
- Wrap multiple glass elements in `GlassEffectContainer` for proper blending and morphing
- Use `.glassEffect(.regular.interactive())` for touchable elements (buttons)
- Use `.buttonStyle(.glass)` for glass-styled buttons
- Use `@Namespace` + `.glassEffectID()` for morphing transitions between states

---

## Shared UI Elements

### Bottom Search Bar

Both home and node screens have a bottom toolbar with a search/ask bar:

- Pill-shaped container using `.glassEffect(in: .capsule)` — Liquid Glass material
- Search icon (left), "Ask anything or search" placeholder text (center), microphone icon (right)
- Positioned at the bottom with safe area padding (28px horizontal, 32px bottom)
- **v1 status:** Visually present, functionally a placeholder

### Toolbar Buttons

Buttons in the top toolbar use **Liquid Glass pill** styling:

- 44px height, capsule shape via `.glassEffect(in: .capsule)`
- Use `.glassEffect(.regular.interactive())` for touch responsiveness
- SF Pro Medium 17px for icon symbols
- When multiple toolbar buttons are adjacent, wrap in `GlassEffectContainer` for blending

---

## Home Screen

The home screen is the root of the app. It displays only root blocks (`parentId == nil`), ordered by `sortOrder` ascending. Each root block is displayed as a line of text — no bullet points or indentation, just clean text lines like Apple Notes. If a root block has children, there is no visual indicator on the home screen; children are only revealed in the node view.

### Top Toolbar

- **Top-left:** "Home" label in subtitle style (15px medium, #727272)
- **Title area:** Large title "Home" (34px bold) with subtitle "Add tag here" below (15px medium, #727272, placeholder for v1)
- **Top-right:** Sort/filter button (⇅ icon) in a Liquid Glass pill (`.glassEffect(in: .capsule)` with `.interactive()`)

### Content Area

Only root blocks are displayed as plain text lines:

- **Root blocks (depth 0):** Plain text, no bullet, no indentation
- Children are **not visible** on the home screen — they are revealed when drilling into a node view

Content is rendered in SF Pro Regular 20px, line-height 28px, color #262626, with 10px gap between blocks. Long text wraps naturally.

### Empty State

An empty screen (no blocks) shows a tappable empty area to create the first block.

### Navigation

- Double-tapping any block's text pushes a **node view** onto the NavigationStack
- Navigation path: Home → Node A → Node A's child → ... (unlimited depth)

---

## Node Screen

Pushed onto the NavigationStack when a block is double-tapped (from home screen or another node view).

### Top Toolbar

- **Left:** Back button (‹ chevron icon) in a Liquid Glass pill (`.glassEffect(in: .capsule)` with `.interactive()`)
- **Center-left (next to back button):** Breadcrumb navigation showing the path, e.g., "Home / Not too bad" (15px medium, #727272, separated by " / ")
- **Right:** Sort/filter button (⇅ icon) in a Liquid Glass pill (same styling as home). When multiple toolbar buttons are present, wrap in `GlassEffectContainer` for proper blending

### Title Area

- **Heading:** The selected node's `content` displayed as a large title (34px SF Pro Bold, #1a1a1a)
- **Tag subtitle:** If the node has tags, shown below the title in red text (15px SF Pro Medium), e.g., "#daily". Placeholder for v1.

### Content Area

Displays the node's descendants:

- **First-level children:** Plain body text (20px SF Pro Regular, line-height 25px) with no bullets — maintains a regular note look and feel
- **Grandchildren:** Bulleted with filled circle (•) at 30px indent
- **Great-grandchildren:** Bulleted at 60px indent
- **Deeper descendants:** Continue with bullets, 30px per additional level

Content gap: 10px between blocks.

### Indentation Formula

```
indent level = block.depth - currentNode.depth - 1
```

| Indent Level | Relationship | Visual |
|---|---|---|
| 0 | First-level children | Plain text (no bullet) |
| 1 | Grandchildren | Filled circle (•) |
| 2 | Great-grandchildren | Hollow circle (◦) |
| 3+ | Deeper descendants | Dash (–) |

Indent 30px per level.

### Expand / Collapse Toggle

Located in the menu bar (right side) — shares the same button position as the sort/filter button:

- **Collapsed (default):** Only first-level children shown as plain text, with their immediate descendants visible as bullets
- **Expanded:** All descendants of the current node are shown. First-level children remain as plain text. All deeper descendants shown with bullets at their respective indent levels. The button text/icon toggles between "Expand All" and "Collapse"

### Navigation

- Double-tapping any child block's text pushes another node view onto the stack (drill-down continues)
- Back button pops the current node view off the NavigationStack

---

## Edit Mode (Visual)

When a block's text is tapped, edit mode activates. The visual elements:

- **Keyboard** appears (standard iOS keyboard)
- **Format bar** sits above the keyboard (iOS only) with three items:
  1. **Indent (→)** — greyed out if block is first sibling
  2. **Outdent (←)** — greyed out if block is at root level
  3. **Mention (@)** — greyed out (placeholder for v1)
- **Cursor** appears in the tapped block's text
- Tapping outside text or on another block exits edit mode

On macOS, there is no format bar. Indent/Outdent use Tab/Shift+Tab. Mention uses right-click context menu (greyed out for v1).

See the [Interactions PRD](PRD-interactions.md) for the full behavioral specification of edit mode actions.

---

## Platform Considerations

| Aspect | iOS | macOS |
|---|---|---|
| Edit mode trigger | Tap | Click |
| Node view trigger | Double tap | Double-click |
| Format bar | Above keyboard | Not present (keyboard shortcuts) |
| Reorder trigger | Long press + drag | Long press + drag |

---

## State Management

| State | Type | Scope |
|---|---|---|
| Current screen | NavigationStack path | App-wide |
| Expand all toggle | `@State isExpanded: Bool = false` | Per node view |
| Block data (home) | Root blocks (`parentId == nil`), sorted by `sortOrder` | Home screen |
| Block data (collapsed) | `parentId == currentNodeId`, sorted by `sortOrder` | Node view |
| Block data (expanded) | All descendants of `currentNodeId`, sorted by `depth` then `sortOrder` | Node view |

---

## Not in Scope for v1

These features exist in the data model but will not have UI in v1:

- Search (bottom bar is visually present but functionally disabled)
- Tags (subtitle area is visually present but functionally disabled)
- Metadata fields
- Mention/linking (button is placeholder only)
- Templates
- Sync
- Today notes / Inbox
