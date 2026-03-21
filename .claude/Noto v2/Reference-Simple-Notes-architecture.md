# Architecture Analysis: Simple Notes (pmattos/Simple-Notes)

## Overview

Simple Notes is an iOS note-taking app built in Swift (2019) using UIKit and TextKit 1. It features a custom rich-text formatting engine based on a Markdown-ish plain text encoding. Notes are persisted to Firebase Firestore.

- **Platform:** iOS only (minimum iOS 12.1)
- **UI framework:** UIKit (Storyboard-based, no SwiftUI)
- **Text engine:** TextKit 1 (custom `NSTextStorage` subclass)
- **Persistence:** Firebase Firestore (cloud-only, no local persistence layer)
- **Dependencies:** Firebase/Core, Firebase/Firestore (via CocoaPods)
- **Architecture pattern:** MVC with a singleton data manager

## Project Structure

```
Simple Notes/
├── AppDelegate.swift                  # App entry, Firebase setup, os_log helpers
├── Base.lproj/
│   ├── Main.storyboard                # UINavigationController → NotesViewController → NotesListViewController
│   └── LaunchScreen.storyboard
├── NotesManager.swift                 # Data manager singleton + Note model struct
├── NoteTextStorage.swift              # Core rich-text formatting engine (NSTextStorage subclass)
├── NoteEditorViewController.swift     # Editor VC + NoteTextView (UITextView subclass)
├── NotesListViewController.swift      # List VC (UITableViewController) + parent container VC
├── CheckmarkView.swift                # Core Graphics animated checkmark control
├── String+Helpers.swift               # String/NSString/NSAttributedString/regex extensions
├── NSObject+Helpers.swift             # className helpers
├── StoryboardInstantiatable.swift     # Protocol for storyboard-based VC instantiation
├── UIViewController+Helpers.swift     # Child VC containment, alerts, nav bar helpers, CGRect
├── Assets.xcassets/                   # App icon
├── Info.plist
└── GoogleService-Info.plist           # Firebase config
```

External:
- `Podfile` — Firebase/Core + Firebase/Firestore
- `Screenshots/` — note-editor.png, note-list.png

## Data Model

### Note struct (`NotesManager.swift`)

Notes are plain value types. There is no CoreData, SwiftData, or SQLite — just Firebase Firestore documents.

```swift
struct Note {
    var contents: String          // Markdown-ish plain text (the full note body)
    let creationDate: Date
    private(set) var modifiedDate: Date  // auto-updated on contents didSet
    fileprivate(set) var uid: UID?       // Firestore document ID, nil for new notes

    var title: String { contents.lines.first ?? "" }  // first line = title
}
```

Key design decisions:
- **No separate title field.** Title is derived from the first line of contents.
- **Plain text storage.** The rich formatting is encoded as Markdown-ish syntax (`**bold**`, `*italic*`, `* `, `- `, `1. `, `[x] `, `[_] `). The `NoteTextStorage` class handles converting between this plain text and attributed strings.
- **Value type.** Note is a struct, not a class — simple copy semantics.
- **UID comes from Firestore.** New notes have `uid = nil` until saved.

### Firestore document schema

```
Collection: "notes"
Document fields:
  - contents: String
  - created_at: Timestamp
  - modified_at: Timestamp
```

### NotesManager (singleton)

- `NotesManager.shared` — global singleton
- In-memory `notesByUID: [UID: Note]` dictionary
- `notes` computed property returns all notes sorted by `modifiedDate` descending
- `saveNote(_:)` returns `.saved(Note)`, `.empty`, or `.didNotChange`
- Posts `didUpdateNoteNotification` via NotificationCenter on any change
- Reads all documents from Firestore on startup (`readAllNoteDocuments`)

No local caching — if Firestore is unreachable, notes are lost.

## Architecture Pattern

**MVC with a singleton data manager.** Classic iOS MVC:

- **Model:** `Note` struct + `NotesManager` singleton
- **View:** Storyboard-defined UIKit views + `NoteTextView` (UITextView subclass) + `CheckmarkView` (UIControl subclass)
- **Controller:** `NotesViewController`, `NotesListViewController`, `NoteEditorViewController`

Communication pattern:
- Controllers read from `NotesManager.shared` directly
- NotesManager broadcasts changes via `NotificationCenter` (`didUpdateNoteNotification`)
- `NotesListViewController` observes this notification and reloads the table view
- No delegates between controllers — navigation is push-based via `UINavigationController`

## View Layer

### Navigation Flow

```
UINavigationController (initial VC)
  └── NotesViewController (container)
        └── NotesListViewController (UITableViewController, child VC)
              ├── tap row → push NoteEditorViewController (existing note)
              └── "+" button → push NoteEditorViewController (new empty note)
```

### NotesViewController

Parent container. Contains a `notesListContainer` UIView that hosts the `NotesListViewController` as a child VC (using `addContentController`). Also owns the "+" new note button.

### NotesListViewController

- `UITableViewController` with a single section
- Cells: `NoteCell` — shows `note.title` and `note.modifiedDate.relativeDescription`
- Observes `didUpdateNoteNotification` to reload data
- Tapping a row pushes `NoteEditorViewController` with the selected note

### NoteEditorViewController

- Hosts a `NoteTextView` inside a `noteViewContainer` (storyboard outlet)
- Programmatically creates the TextKit stack: `NoteTextStorage` → `NSLayoutManager` → `NSTextContainer` → `NoteTextView`
- Shows "OK" and "Checklist" buttons in nav bar during editing
- Saves note on `viewDidDisappear` and on end editing
- Handles keyboard show/hide to adjust scroll insets

## Text Editing

This is the most architecturally interesting part of the app.

### TextKit 1 Stack

```
NoteTextStorage (NSTextStorage subclass)
    └── NSLayoutManager
          └── NSTextContainer
                └── NoteTextView (UITextView subclass)
```

### NoteTextStorage — The Formatting Engine

The core of the app. Handles two directions of conversion:

1. **Load (Markdown → Attributed String):** `load(note:)` takes plain text, applies `WordsFormatter.format` then `ListsFormatter.format` to produce an attributed string with custom attributes and visual styling.

2. **Save (Attributed String → Markdown):** `deformatted()` applies `WordsFormatter.deformat` then `ListsFormatter.deformat` to convert back to plain text.

3. **Live formatting:** As the user types, `processEditing()` captures the edited range, and `processRichFormatting()` runs formatters to detect and apply inline formatting.

### Formatting Architecture

Two formatter classes, both subclasses of a base `Formatter`:

**WordsFormatter:**
- Detects `**bold**` and `*italic*` patterns via regex
- On match: replaces the markdown syntax with styled text + trailing space
- Uses custom NSAttributedString attributes (`.bold`, `.italic`) to track formatted ranges
- `deformat` reverses: finds `.bold`/`.italic` attributes and wraps text back in `**`/`*`

**ListsFormatter:**
- Supports 4 list types: bullet (`* `), dashed (`- `), ordered (`1. `), checkmark (`[x] ` / `[_] `)
- Each `ListItem` type has: regex for detection, paragraph style (indentation), item marker character, markdown prefix
- Replaces markdown prefixes with visual markers (bullet → `•`, dash → `–`, checkmark → zero-width space + overlay view)
- Handles list continuation: pressing Enter on a list line auto-inserts the next list item
- Handles list termination: pressing Enter on an empty list line ends the list
- Ordered lists auto-renumber subsequent items when a new item is inserted

### Key TextKit Patterns

- **Custom attributes as metadata:** `.list`, `.bold`, `.italic`, `.caret` — stored as NSAttributedString attributes, used to track formatting state without visual effect
- **Caret positioning:** A `.caret` attribute marks where the cursor should land after a formatting change. `fixCaretPosition` finds this attribute and moves `selectedRange` accordingly (dispatched async to avoid reentrancy)
- **Zero-width space trick:** Checkmark list items use `\u{200B}` (zero-width space) as the marker character, with a `CheckmarkView` overlaid on top. `textViewDidChangeSelection` skips over zero-width spaces when the user moves the cursor.
- **Format → replace cycle:** When a markdown pattern is detected (e.g., `**text**`), the storage replaces the matched range with styled text in-place, modifying the backing store directly.
- **Line-based processing:** All formatting operates on line ranges. `NSAttributedString.mapLines` and `enumerateLines` are custom extensions that iterate attributed strings line by line.

### NoteTextView — Custom UITextView

- Disables spell check, autocorrect
- Enables data detectors for links and phone numbers
- Custom touch handling: detects taps on links/list items vs. starting editing
- `isEditable` toggled on/off — starts as non-editable, becomes editable on tap
- Paste delegate to fix animation glitch
- Manages checkmark overlay views (positioned using `firstRect(for:)` to align with text)

### CheckmarkView — Custom UIControl

- Core Graphics vector drawing (circle background + tick path)
- Stroke animation on toggle
- Sized 25x25, positioned at the left margin of checkmark list lines
- Sends `.primaryActionTriggered` to toggle the checkmark value in `NoteTextStorage`

## Key Design Decisions

### 1. Markdown-ish Plain Text as Canonical Format

The note's `contents` is always plain text with markdown-like syntax. The rich attributed string is a derived view, created on load and converted back on save. This means:
- **Storage is simple** — just a string in Firestore
- **Format is portable** — could be exported/imported as text
- **Tradeoff:** Every load/save requires a full parse/deformat cycle

### 2. No Local Persistence

All data lives in Firestore. No CoreData, no UserDefaults, no file system. The app is non-functional offline. This is a deliberate simplification.

### 3. Singleton Data Manager

`NotesManager.shared` is the single source of truth. All VCs read from it. Changes propagate via NotificationCenter. Simple but not testable or scalable.

### 4. TextKit 1 with Custom NSTextStorage

The formatting engine lives entirely in `NoteTextStorage`. This is the right layer for TextKit 1 — `NSTextStorage` is where you intercept edits and apply attributes. The implementation is clean but complex (~600 lines including formatters).

### 5. Storyboard + Programmatic TextKit Hybrid

The VC hierarchy and layout use storyboards, but the TextKit stack is created entirely in code. This is necessary because `NSTextStorage` subclasses can't be configured in Interface Builder.

### 6. Value Type Note Model

`Note` is a struct. Controllers hold their own copy. The canonical version lives in `NotesManager.notesByUID`. This avoids shared mutable state but requires explicit save-back.

### 7. No Search

There is no search functionality at all. Notes are just listed by modification date.

### 8. No Delete

There is no visible delete functionality in the code. Notes can only be created and edited.

## Relevance to Noto v2

### Patterns worth studying:

1. **Markdown-ish encoding as canonical format.** Noto already uses a similar approach where block content is plain text. Simple Notes validates this pattern — plain text as source of truth with rich rendering as a derived view.

2. **NoteTextStorage architecture.** The formatter pattern (separate WordsFormatter/ListsFormatter classes with `format`/`deformat`/`formatOnEdit` methods) is a clean separation. Noto's `NoteTextStorage` could adopt a similar plugin-style formatter architecture if it adds more inline formatting types.

3. **Caret management via custom attributes.** The `.caret` attribute pattern for post-formatting cursor positioning is clever and avoids complex index arithmetic. Worth considering if Noto's TextKit stack needs to reposition the cursor after formatting changes.

4. **Zero-width space for overlay widgets.** Using `\u{200B}` as a placeholder character with an overlaid UIView (CheckmarkView) is a pragmatic approach for embedding interactive controls in text. Noto could use a similar technique for checkmarks or other inline widgets.

5. **Line-based formatting with `mapLines`/`enumerateLines`.** Clean abstractions for line-by-line attributed string manipulation. Useful utility pattern.

### Patterns to avoid:

1. **Singleton data manager.** Not testable, not suitable for SwiftData or any modern persistence layer.
2. **No local persistence.** Noto needs offline-first with SwiftData.
3. **NotificationCenter for data flow.** Fragile, untyped. Noto should continue using SwiftData's built-in observation.
4. **Storyboards.** Noto is SwiftUI — not relevant.
5. **No search.** Noto already has a sophisticated search stack (FTS5 + HNSW).
6. **Monolithic app target.** All code in one target. Noto's package-based architecture is far superior.

### Key takeaway

Simple Notes is a well-implemented but small-scope reference for **TextKit 1 rich-text editing with markdown-as-source-of-truth**. The `NoteTextStorage` formatting engine is the most valuable reference point — particularly the formatter plugin pattern, the caret attribute trick, and the zero-width space overlay technique. Everything else (data layer, architecture, navigation) is too simplistic to be relevant to Noto v2.
