# Outline Editor Architecture

MVVM architecture for rendering and editing the outline-based note app.

## The Three Layers

```
┌─────────────────────────────────┐
│  View Layer                     │
│  SwiftUI + UIKit TextKit        │
│  "What does the user see?"      │
└──────────────┬──────────────────┘
               │
┌──────────────▼──────────────────┐
│  ViewModel Layer                │
│  BlockEditor                    │
│  "What happens to blocks?"      │
└──────────────┬──────────────────┘
               │
┌──────────────▼──────────────────┐
│  Model Layer                    │
│  Block (SwiftData)              │
│  "What is a block?"             │
└─────────────────────────────────┘
```

## Model — `Block` (NotoModels package)

The source of truth. A SwiftData entity with `id`, `content`, `parent`, `children`, `depth`, `sortOrder`. Knows nothing about views or editing. Lives in its own package, testable independently.

## ViewModel — `BlockEditor` (NotoCore package)

The brain. Takes a root Block and produces a flat list of entries for the view to render. Translates user actions into block mutations:

| User does | BlockEditor method | Block mutation |
|---|---|---|
| Types on line 3 | `updateContent(atLine: 3, ...)` | `block.content = "..."` |
| Presses Enter after line 2 | `insertLine(afterLine: 2)` | New Block inserted as sibling |
| Presses Backspace on empty line | `deleteLine(atLine: 3)` | Block deleted from SwiftData |
| Presses Tab | `indentLine(atLine: 2)` | Block reparented to previous sibling |
| Presses Shift+Tab | `outdentLine(atLine: 2)` | Block reparented to grandparent |
| Long-press drags line | `moveLine(from: 1, to: 3)` | sortOrder updated |

No UIKit imports. No SwiftUI imports. Just Foundation + SwiftData + NotoModels. Fully testable from CLI — 36 tests prove every operation works without any UI.

**Location:** `Packages/NotoCore/Sources/NotoCore/BlockEditor.swift`
**Tests:** `Packages/NotoCore/Tests/NotoCoreTests/BlockEditorTests.swift`

## View — TextKit Stack + SwiftUI (Noto app target)

Three parts that handle rendering and user interaction:

### OutlineTextStorage (`OutlineTextStorage.swift`)

Custom `NSTextStorage`. Receives the flat entry list from BlockEditor and renders each block as a styled line with bullets and indentation based on `indentLevel`. Handles visual formatting only — doesn't know about parent/child relationships.

### OutlineTextView (`OutlineTextView.swift`)

Custom `UITextView`. Handles keyboard input, toolbar (indent/outdent/dismiss), gestures. When the user types or taps a toolbar button, it tells the Coordinator what happened.

### OutlineEditor (`OutlineEditor.swift`)

`UIViewRepresentable` bridge. Contains the Coordinator that wires BlockEditor to TextKit. When the text view reports an edit, the Coordinator calls the appropriate BlockEditor method. When BlockEditor's entries change, the Coordinator tells the TextStorage to re-render.

## Data Flow

```
User types "hello" on line 2
  → OutlineTextView.textViewDidChange()
  → Coordinator detects line 2 changed
  → blockEditor.updateContent(atLine: 2, newContent: "hello")
  → Block.content = "hello" (SwiftData persists)

User presses Tab on line 3
  → OutlineTextView toolbar → indent tapped
  → Coordinator calls blockEditor.indentLine(atLine: 3)
  → BlockEditor reparents block to previous sibling, updates depth
  → BlockEditor.reload() rebuilds flat entries list
  → Coordinator tells TextStorage to re-render with new entries
  → User sees line 3 indent with a bullet
```

## Why This Split

- **BlockEditor is testable without UI** — 36 tests run in 0.12s via `swift test`, no simulator
- **TextStorage only does rendering** — bullets, indentation, text styling. Doesn't touch SwiftData
- **The View manages lifecycle** — keyboard, navigation, layout. Doesn't contain block logic
- **Each layer can change independently** — swap TextKit 2 for TextKit 1, or SwiftUI for AppKit, without touching BlockEditor
