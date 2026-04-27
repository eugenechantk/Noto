# Noto Architecture And Lifecycle

Snapshot date: 2026-04-27

Scope: active app code in `Noto/`, active packages in `Packages/NotoVault`, `Packages/NotoSearch`, and the Readwise sync package integration. `archive/` contains legacy experiments and is not on the active path.

## High-Level Architecture

Noto is a SwiftUI app with a file-backed markdown vault. The app shell is thin: it resolves a vault, owns a root `MarkdownNoteStore`, watches the vault for filesystem changes, starts background sync/index work, and routes into list/sidebar/editor surfaces.

```mermaid
flowchart TD
    App[NotoApp.swift<br/>App entry + commands] --> VaultLoc[VaultLocationManager<br/>bookmark/local/direct vault]
    App --> Main[MainAppView<br/>root app runtime]
    Main --> RootStore[MarkdownNoteStore<br/>root vault store]
    Main --> Watcher[VaultFileWatcher<br/>NSFilePresenter]
    Main --> SearchRefresh[SearchIndexRefreshCoordinator<br/>single-flight indexing actor]
    Main --> Readwise[ReadwiseSyncController]
    Main --> Daily[DailyNotePrewarmer]

    Main --> NoteList[NoteListView<br/>platform navigation router]
    NoteList --> Compact[FolderContentView<br/>iPhone compact list]
    NoteList --> Split[NotoSplitView<br/>iPad/macOS split shell]
    Split --> Sidebar[NotoSidebarView<br/>tree sidebar]
    Split --> EditorScreen[NoteEditorScreen]
    Compact --> EditorScreen

    EditorScreen --> Session[NoteEditorSession<br/>load/edit/save/rename/sync state]
    EditorScreen --> EditorContent[EditorContentView<br/>download/remote/find/editor composition]
    EditorContent --> TextKit[TextKit2EditorView.swift<br/>UITextView/NSTextView adapters + markdown rendering]

    RootStore --> CoordFS[CoordinatedFileManager<br/>NSFileCoordinator reads/writes]
    RootStore --> VaultPkg[NotoVault package<br/>directory/tree/title helpers]
    SearchRefresh --> SearchPkg[NotoSearch package<br/>SQLite FTS index]
    Readwise --> ReadwisePkg[NotoReadwiseSync package<br/>Reader/Readwise API sync engine]
    TextKit --> Commands[BlockEditingCommands / TodoMarkdown / EditorFind]
```

## Directory Map

- `Noto/NotoApp.swift`
  - App entry point, app commands, window setup, root dependency ownership.
  - `MainAppView` owns the root store, vault watcher, daily-note prewarmer, search-index refresh, and Readwise automatic sync.

- `Noto/Views/`
  - `VaultSetupView.swift`: first-run vault picker and macOS/iOS folder-picking UI.
  - `SettingsView.swift`: vault reset plus Readwise token/sync controls.
  - `NoteListView.swift`: platform router. iPhone compact uses `NavigationStack`; iPad/macOS use `NotoSplitView`.
  - `Shared/NotoSplitView.swift`: split-view shell, sidebar/detail composition, note history, global search presentation.
  - `Shared/NotoSidebarView.swift`: shared sidebar tree with expansion state, selection, creation, deletion, and sidebar filtering.
  - `NoteEditorScreen.swift`: editor screen owner; creates the session, chrome, find state, word count, delete flow, sync notifications.
  - `Shared/EditorContentView.swift`: download/error/content switch, remote update banner, find bar, and `TextKit2EditorView`.
  - `iOS/IOSEditorNavigationChrome.swift` and `macOS/MacEditorNavigationChrome.swift`: platform chrome around the same editor core.

- `Noto/Editor/`
  - `TextKit2EditorView.swift`: live iOS/iPadOS/macOS editor path. Contains shared markdown semantics plus platform TextKit adapters.
  - `NoteEditorSession.swift`: load/save/autosave/rename/conflict state machine.
  - `BlockEditingCommands.swift`: pure markdown text transforms for todo, indent/outdent, inline marks, hyperlinks, images, page mentions.
  - `TodoMarkdown.swift`: todo-line parsing and checkbox toggling.
  - `EditorFind.swift`: find matcher and navigation model.
  - `BlockEditorView*` and `Block.swift`: legacy/alternate block editor code; current live editor is `TextKit2EditorView`.

- `Noto/Storage/`
  - `MarkdownNoteStore.swift`: main app-facing store for notes/folders. File-backed, main-actor observable, delegates listing to `NotoVault`.
  - `CoordinatedFileManager.swift`: all coordinated reads/writes/moves/deletes and iCloud availability helpers.
  - `VaultLocationManager.swift`: vault persistence, bookmarks, local vault, direct vault, launch-argument test hooks.
  - `VaultFileWatcher.swift`: `NSFilePresenter` wrapper that debounces external changes.
  - `NoteTemplate.swift`: daily-note template.

- `Noto/Support/`
  - `NoteSyncCenter.swift`: same-process note-save notification bus between open editor sessions/windows.
  - `DebugTrace.swift`: lightweight runtime trace log.
  - `AppTheme.swift`: shared colors and theme primitives.

- `Noto/SearchIndexRefreshCoordinator.swift`
  - Actor that single-flights full index refreshes, debounces file refreshes, and posts `.notoSearchIndexDidChange`.

- `Noto/Sync/`
  - `ReadwiseSyncController.swift`: app-level token state and sync task orchestration.
  - `ReadwiseSecretStore.swift`: secure token storage and bundled token plumbing.

- `Packages/NotoVault/`
  - Platform-neutral vault listing and metadata helpers.
  - `VaultDirectoryLoader`: one-directory folder/note listing, ordering, metadata strategy.
  - `SidebarTreeLoader`: recursive tree rows, expansion filtering, sidebar search filtering.
  - `NoteTitleResolver`, `Frontmatter`, `WordCounter`, `VaultManager`, `NoteFile`: domain helpers.

- `Packages/NotoSearch/`
  - Platform-neutral search indexing and query layer.
  - `MarkdownSearchIndexer`: scans vault markdown files, refreshes changed files, refreshes/removes single files.
  - `MarkdownSearchDocumentExtractor`: markdown/frontmatter/heading/section/plaintext extraction.
  - `SearchIndexStore`: SQLite/FTS store.
  - `MarkdownSearchEngine`: query normalization and search facade.
  - `SearchTypes`: documents, sections, stats, results.

- `Packages/NotoReadwiseSync/`
  - Readwise/Reader import logic. The app calls this via `PackageReadwiseSyncRunner`.

## Ownership Model

- `NotoApp` owns app-global state:
  - `VaultLocationManager`
  - `ReadwiseSyncController`

- `MainAppView` owns per-vault runtime state:
  - root `MarkdownNoteStore`
  - one `VaultFileWatcher`
  - one `DailyNotePrewarmer`
  - search-index refresh kickoff
  - automatic Readwise sync kickoff

- Navigation views own selection state:
  - Compact iPhone: `NavigationPath` of `NoteRoute`, plus `NoteNavigationHistory`.
  - iPad/macOS split: `selectedNote`, `selectedNoteStore`, `selectedIsNew`, plus history in `NotoSplitView`.
  - iPad detail additionally mirrors selected notes into a native `NavigationStack` through `NoteStackNavigationState`.

- Each editor screen owns one `NoteEditorSession`.
  - The session is the source of truth for loaded content, pending edits, autosave, rename, conflicts, download state, and delete state.
  - The TextKit view owns platform text view mechanics and calls the session via `onTextChange`.

## App Lifecycle

```mermaid
sequenceDiagram
    participant OS
    participant App as NotoApp
    participant Loc as VaultLocationManager
    participant Main as MainAppView
    participant Store as MarkdownNoteStore
    participant Watch as VaultFileWatcher
    participant Search as SearchIndexRefreshCoordinator
    participant Daily as DailyNotePrewarmer
    participant Readwise as ReadwiseSyncController

    OS->>App: launch process
    App->>App: reset DebugTrace, configure iOS nav, install crash handler
    App->>Loc: init + resolve saved vault
    alt vault unavailable
        App->>OS: render VaultSetupView
    else vault configured
        App->>Main: render MainAppView(vaultURL)
        Main->>Store: create root store autoload=false, metadata=fileOnly
        Main->>Store: task: loadItemsInBackground()
        Main->>Daily: task: start(vaultURL)
        Daily-->>Daily: detached utility ensure today's note
        Main->>Readwise: refresh token + startAutomaticSync()
        Main->>Search: refresh(vaultURL)
        Main->>Watch: onAppear watch(vaultURL)
    end

    OS->>Main: scenePhase active
    Main->>Store: refreshForForegroundActivation()
    Main->>Daily: start(vaultURL)
    Main->>Readwise: startAutomaticSync()
    Main->>Search: refresh(vaultURL)

    Watch-->>Main: debounced external changeCount
    Main->>Store: loadItemsInBackground()
    Main->>Search: refresh(vaultURL)

    OS->>Main: scenePhase background
    Main->>Daily: stop midnight/prewarm tasks
```

## Vault Setup Lifecycle

```mermaid
flowchart TD
    Launch[NotoApp launch] --> Resolve[VaultLocationManager.resolveVault]
    Resolve -->|saved local| Local[Documents/Noto]
    Resolve -->|valid bookmark| External[security-scoped external/direct vault]
    Resolve -->|missing/invalid| Setup[VaultSetupView]
    Setup --> Create[Create New Vault<br/>choose parent, create Noto/]
    Setup --> Open[Open Existing Vault<br/>direct folder]
    Create --> Bookmark[save bookmark + flags]
    Open --> Bookmark
    Bookmark --> Main[MainAppView]
    Main --> Settings[SettingsView]
    Settings --> Reset[resetVault clears saved config]
    Reset --> Setup
```

## List, Sidebar, And Navigation Lifecycle

```mermaid
flowchart TD
    NoteList[NoteListView] --> Device{size/platform}
    Device -->|iPhone compact| Compact[NavigationStack + FolderContentView]
    Device -->|iPad regular| SplitIOS[NotoSplitView iOS]
    Device -->|macOS| SplitMac[NotoSplitView macOS]

    Compact --> FolderLoad[FolderContentView.onAppear loadItemsInBackground]
    Compact --> Route[NoteRoute folder/note/settings/today]
    Route --> Editor[NoteEditorScreen]

    SplitIOS --> Sidebar[NotoSidebarView]
    SplitMac --> Sidebar
    Sidebar --> Tree[SidebarTreeLoader detached loadRows]
    Sidebar --> Select[select note -> selectedNote/Store]
    Select --> SplitDetail[NotoSplitView.splitEditor]
    SplitDetail --> Editor

    SplitIOS --> History[NoteNavigationHistory + NoteStackNavigationState]
    SplitMac --> History2[NoteNavigationHistory]
```

Notes:

- `MarkdownNoteStore.loadItemsInBackground()` is the standard directory-load path for responsive list/sidebar rendering.
- Root launch uses `VaultDirectoryLoader(noteMetadataStrategy: .fileOnly)` to avoid reading every note at startup.
- `NotoSidebarView` owns persisted expanded-folder URLs in `UserDefaults`, reloads tree rows off-main, and reloads searchable rows only when sidebar filtering is active.
- Compact iPhone routes notes through `NoteRoute`; split views keep selection bindings and route detail composition through `NotoSplitView`.

## Opening A Note Lifecycle

```mermaid
sequenceDiagram
    participant UI as List/Sidebar/Search
    participant Nav as NoteListView/NotoSplitView
    participant Store as MarkdownNoteStore
    participant Screen as NoteEditorScreen
    participant Session as NoteEditorSession
    participant Content as EditorContentView
    participant TextKit as TextKit2EditorView
    participant FS as CoordinatedFileManager

    UI->>Nav: user selects note
    Nav->>Store: create directory store for note folder, usually autoload=false
    Nav->>Screen: render NoteEditorScreen(store,note,isNew)
    Screen->>Session: State(NoteEditorSession)
    Screen->>Session: task loadNoteContent()
    Session->>FS: detached coordinated read
    alt readable
        FS-->>Session: markdown content
        Session->>Session: applyLoadedContent and update title metadata
        Session-->>Content: content, hasLoaded=true
        Content->>TextKit: bind text + callbacks
    else iCloud needs download
        Session-->>Content: isDownloading=true
        Content-->>UI: downloading view
        Session->>FS: startDownloading + poll readable content
    else unreadable current file
        Session-->>Content: downloadFailed=true
        Content-->>UI: failure view
    end
```

## Editing And Saving Lifecycle

```mermaid
sequenceDiagram
    participant User
    participant TextKit as TextKit2EditorViewController
    participant Coord as TextKit2EditorCoordinator
    participant Session as NoteEditorSession
    participant Store as MarkdownNoteStore
    participant FS as CoordinatedFileManager
    participant Index as SearchIndexRefreshCoordinator
    participant Sync as NoteSyncCenter
    participant Screen as NoteEditorScreen

    User->>TextKit: type / toolbar command / todo toggle / image insert
    TextKit->>TextKit: update TextKit text, markdown attributes, overlays
    TextKit->>Coord: updateText(newText)
    Coord->>Session: onTextChange -> handleEditorChange(newText)
    Session->>Session: update content/latestEditorText and set pendingLocalEdits
    Session->>Store: updateTitleFromContent()
    Session->>Session: debounce autosave 500ms
    opt title changed
        Session->>Session: debounce rename 800ms
    end

    Session->>Store: autosave persistEditorText()
    Store->>FS: read existing body
    alt body changed
        Store->>FS: write updated timestamp + content
        Store->>Index: schedule file refresh 900ms
        Store-->>Session: SaveResult didWrite=true
        Session->>Sync: publish NoteSyncSnapshot
        Session->>Session: pendingLocalEdits=false
    else unchanged
        Store-->>Session: SaveResult didWrite=false
    end

    opt rename debounce fires
        Session->>Store: renameFileIfNeeded()
        Store->>FS: move file if title maps to new filename
        Store->>Index: replace indexed file path
    end

    Screen->>Session: onDisappear persistFinalSnapshotIfNeeded()
```

Important save semantics:

- Saves compare non-frontmatter body content first; unchanged body does not update timestamps.
- Autosave is debounced. Disappear forces a final save if latest editor text diverges from persisted text.
- Same-process synchronization is notification-based through `NoteSyncCenter`, not `VaultFileWatcher`.
- `VaultFileWatcher` is for filesystem/external changes and list/index refreshes.

## External Change And Same-Process Sync Lifecycle

```mermaid
flowchart TD
    Save[Editor A saves note] --> Publish[NoteSyncCenter publishes snapshot]
    Publish --> EditorB[Editor B receives snapshot]
    EditorB --> SameSession{same editorSessionID?}
    SameSession -->|yes| Ignore[ignore own save]
    SameSession -->|no| Pending{Editor B has local edits?}
    Pending -->|yes| Conflict[pendingRemoteSnapshot -> banner]
    Pending -->|no| Apply[applyRemoteSnapshot -> content updates]

    External[External/iCloud filesystem change] --> Presenter[VaultFileWatcher NSFilePresenter]
    Presenter --> Debounce[500ms debounce]
    Debounce --> Change[changeCount + lastChangedFileURL]
    Change --> Lists[lists/sidebar reload]
    Change --> OpenEditor[open editor handleExternalChange]
    OpenEditor --> HasLocal{pending local edits?}
    HasLocal -->|yes| Skip[skip disk reload]
    HasLocal -->|no| Read[read disk and reload if body changed]
```

## Daily Note Lifecycle

```mermaid
sequenceDiagram
    participant Main as MainAppView
    participant Daily as DailyNotePrewarmer
    participant File as DailyNoteFile
    participant Store as MarkdownNoteStore
    participant UI as Today button/route

    Main->>Daily: app task/start active
    Daily->>File: detached ensure(vaultRootURL, today)
    File-->>Daily: created/applied/no-op
    Daily->>Daily: schedule next local midnight while active

    UI->>Store: todayNote() fallback
    Store->>File: ensure(vaultRootURL, Date())
    Store-->>UI: daily folder store + MarkdownNote
```

The prewarmer makes first open usually instant, but `todayNote()` remains the correctness fallback when the app was killed/suspended or the prewarm did not complete.

## Mention Menu Lifecycle

```mermaid
sequenceDiagram
    participant User
    participant TextKit as TextKit2EditorViewController
    participant PM as PageMentionMarkdown
    participant Screen as NoteEditorScreen
    participant Store as MarkdownNoteStore
    participant Search as NotoSearch index
    participant Session as NoteEditorSession

    User->>TextKit: type @query
    TextKit->>PM: activeQuery(text, selection)
    alt no active query
        TextKit->>TextKit: hide suggestions
    else active query
        TextKit->>Screen: pageMentionProvider(query)
        Screen->>Store: pageMentionDocuments(matching, excluding current note)
        Store->>Search: title search if SQLite index exists
        alt index unavailable/fails
            Store->>Store: fallback vault scan, title from filename
        end
        Store-->>TextKit: PageMentionDocument[]
        TextKit->>TextKit: show popover/sheet, keyboard selection
        User->>TextKit: select result
        TextKit->>PM: markdownLink(for document)
        TextKit->>TextKit: replace @query with markdown link
        TextKit->>Session: normal text change -> autosave lifecycle
    end
```

Platform notes:

- iOS has both inline suggestion popover support and a sheet path for compact/editor conditions.
- macOS uses an `NSStackView` popover anchored to the text layout.
- Page mentions currently search titles, prefer the SQLite index when available, and exclude the active note.

## Global Search Sheet Lifecycle

```mermaid
sequenceDiagram
    participant User
    participant Shell as NoteListView/NotoSplitView
    participant Sheet as NoteSearchSheet
    participant Coord as SearchIndexRefreshCoordinator
    participant Index as MarkdownSearchIndexer/SearchIndexStore
    participant Store as MarkdownNoteStore
    participant Nav as Navigation/Selection

    User->>Shell: tap Search or Cmd-K
    Shell->>Sheet: present NoteSearchSheet(rootStore)
    Sheet->>Sheet: focus search field
    Sheet->>Index: check existing search.sqlite
    alt index exists with notes
        Sheet->>Sheet: skip sheet-open refresh
    else no usable index
        Sheet->>Coord: refresh(vaultURL)
        Coord->>Index: refreshChangedFiles()
        Coord-->>Sheet: index ready + notification
    end

    User->>Sheet: type query / change scope
    Sheet->>Sheet: debounce 120ms
    Sheet->>Index: detached SQLite search
    alt SQLite fails
        Sheet->>Index: destroy + refreshChangedFiles + retry
    end
    alt retry fails
        Sheet->>Index: fallback vault scan
    end
    Sheet->>Store: map SearchResult -> MarkdownNote/store
    Sheet-->>User: result rows
    User->>Sheet: select result
    Sheet->>Nav: onSelect(result)
    Nav->>Nav: open note and close search
```

Search index refresh sources:

- `MainAppView.task` and scene active refresh.
- `VaultFileWatcher` change events.
- `MarkdownNoteStore` create/save/rename/move/delete single-file operations.
- `NoteSearchSheet.prepareIndex()` when no existing index is present.
- `DailyNotePrewarmer` and `todayNote()` when daily note creation/template application changes a file.

## Find-In-Note Lifecycle

```mermaid
flowchart TD
    CmdF[Cmd-F / editor search button] --> Notify[NoteEditorCommands.showFind notification]
    Notify --> Screen[NoteEditorScreen.showFind]
    Screen --> Bar[EditorFindBar visible]
    Bar --> Query[findQuery binding changes]
    Query --> TextKit[TextKit2EditorView.updateFind]
    TextKit --> Matcher[EditorFindMatcher.ranges]
    Matcher --> Highlights[platform highlight overlays/backgrounds]
    Bar --> Nav[Next/Previous]
    Nav --> Request[EditorFindNavigationRequest id+direction]
    Request --> TextKit
    TextKit --> Scroll[select + scroll to match]
    Close[Close / Esc] --> Reset[clear find query/status/request]
```

## TextKit Editor Internal Architecture

`TextKit2EditorView.swift` is intentionally dense. It has three layers in one file:

1. Shared markdown model and style layer:
   - `MarkdownBlockKind`, `MarkdownSemanticAnalyzer`, `MarkdownRenderableBlock`
   - `MarkdownFrontmatter`, `MarkdownLineRanges`, `MarkdownVisualSpec`, `MarkdownTheme`
   - `MarkdownParagraphStyler`, `MarkdownTypingAttributes`
   - hyperlink, divider, image-link, XML-like tag, todo geometry helpers

2. TextKit layout layer:
   - `MarkdownTextDelegate`
   - custom `NSTextParagraph`
   - custom layout fragments for hidden frontmatter, todos, image previews
   - image dimension/cache/loader

3. Platform adapters:
   - iOS: `UIViewControllerRepresentable`, `UITextView`, input accessory toolbar, PHPicker, keyboard avoidance.
   - macOS: `NSViewControllerRepresentable`, `NSTextView`, drop/import support, command notification observers.

Both adapters feed text changes through `TextKit2EditorCoordinator`, then into `NoteEditorSession`.

## Current Architectural Pressure Points

- `TextKit2EditorView.swift` is the largest concentration of behavior: parsing, styling, layout fragments, platform adapters, page mentions, image previews, find, hyperlinks, todo overlays, and keyboard/scroll behavior all live together.
- `NoteListView.swift` owns several concerns at once: routing, compact list UI, bottom toolbar, search sheet, and search execution/fallback logic.
- `MarkdownNoteStore.swift` is both persistence facade and app-domain service: CRUD, daily note creation, image attachments, mention lookup, index updates, and file resolution.
- The code already has good package seams for `NotoVault` and `NotoSearch`; more logic could move there when it is platform-neutral and does not depend on SwiftUI/TextKit.

## Practical Mental Model

- App lifecycle starts in `NotoApp` and `MainAppView`.
- Vault state lives in `VaultLocationManager`; vault file operations go through `MarkdownNoteStore` and `CoordinatedFileManager`.
- Navigation state lives in `NoteListView`/`NotoSplitView`.
- Directory/tree state comes from `MarkdownNoteStore` plus `NotoVault`.
- Editor document state lives in `NoteEditorSession`.
- Text rendering and editor interaction live in `TextKit2EditorView`.
- Search indexing/querying lives in `NotoSearch`, coordinated by `SearchIndexRefreshCoordinator`.
- Same-process note sync uses `NoteSyncCenter`; external filesystem sync uses `VaultFileWatcher`.
