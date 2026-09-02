# Personal Notetaking Universal Apple App

This is a universal apple application for my markdown based note taking app

## Current Architecture

Noto is now organized around explicit ownership boundaries. The app target owns Apple-platform lifecycle, presentation, and side effects. Swift packages own platform-neutral vault, search, and Readwise mechanics.

```text
NotoApp
  MainAppView
    owns launch/scene lifecycle, root store compatibility, file watcher,
    daily-note prewarming, automatic Readwise sync, and search-index refresh

    VaultWorkspaceView
      owns workspace navigation and presentation
      handles VaultWorkspaceIntent from lists, sidebar, search, and editor
      owns compact iPhone NavigationStack routes
      owns iPad/macOS split selection and note history
      owns Today, search, settings, document-link routing, and restore-last-note

      NotoSplitView
        layout shell for NavigationSplitView, sidebar visibility, and search presentation

      NotoSidebarView / FolderContentView
        render vault rows and emit workspace intents

      NoteEditorScreen
        composes NoteEditorSession, editor chrome, sheets, find, move, and delete UI

        NoteEditorSession
          owns one open note's load/edit/autosave/rename/move/delete/conflict lifecycle

        TextKit2EditorView
          active native markdown editing surface

VaultController
  app-facing facade for vault operations
  wraps current MarkdownNoteStore compatibility behavior

SearchIndexController
  app-facing search-index lifecycle side effects
  wraps NotoSearch.SearchIndexCoordinator and posts app notifications

Packages
  NotoVault: UI-free filesystem, note, folder, daily-note, attachment, path,
             title, sidebar tree, and word-count mechanics
  NotoSearch: UI-free markdown indexing, search, and refresh coordination
  NotoDigest: UI-free inbox triage — reading inbox/, snooze filtering, and the
              four filing actions (snooze, add-to, create, discard)
  NotoReadwiseSync: Readwise/Reader API client, sync engine, note rendering,
                    sync state, tests, and CLI
```

### Two app targets, one shared layer (`NotoShared/`)

Since 2026-08-23 the project builds two apps from the same code:

| Target | Scheme | Bundle id | What it is |
| --- | --- | --- | --- |
| `Noto` | `Noto-iOS`, `Noto-macOS`, `Noto` | `com.eugenechan.Noto` | the full iOS/iPadOS/macOS app |
| `Noto2` | `Noto2` | `com.eugenechan.Noto2` | a separate, iOS-only four-screen app — Capture (editor + send to `inbox/`), Digest (process `inbox/` to zero), Search (hybrid hits + streamed summary), Browse — over the same vault |
| `Noto2QuickCaptureControl` | embedded by `Noto2` | `com.eugenechan.Noto2.QuickCaptureControl` | WidgetKit accessory widget for opening Noto 2 Quick Capture from the Lock Screen widget area; the existing target name is retained for bundle/signing stability |

Both targets compile the `NotoShared/` synced folder, which holds everything that is
app-level Swift but not specific to either app's chrome:

```text
NotoShared/
  Editor/    TextKit2EditorView, NoteEditorSession, BlockEditingCommands, TodoMarkdown,
             EditableFrontmatter, EditorFind, FrontmatterBlockLayout, NoteContentCache, Block
  Storage/   VaultLocationManager, MarkdownNoteStore, VaultController, VaultFileWatcher,
             CoordinatedFileManager, NoteTemplate, CaptureFilingService
  Search/    SearchIndexController, SearchIndexStatusModel, SemanticSearchService
  Support/   DebugTrace, AppTheme, NotoTheme, NoteSyncCenter
  Chat/      OpenRouterKeyStore, OpenRouterBaseURLStore, ReadwiseSecretStore
  Views/     EditorContentView, EditorFindBar, EditorBreadcrumbBar, EditorChromeMode,
             EditorStatusOverlay, SheetCircleButton, VaultSetupView
Noto2ControlShared/
  Noto2QuickCaptureIntent     Strict capture URL route and launch router shared with the widget
Noto2QuickCaptureControl/
  Noto2QuickCaptureControl    WidgetKit accessory widget extension embedded by Noto 2
```

Rules that follow: a file in `NotoShared/` must compile for both targets (iOS-only Noto 2
and multiplatform Noto), so platform code stays behind `#if os(...)`; anything under
`Noto/` (NotoApp, NoteListView, NotoSidebarView, Settings, Chat UI, deep links, Readwise
sync) is Noto-only and must not be referenced from `NotoShared/` or `Noto2/`; `Noto2/`
holds only Noto 2's screens. `NotoTests` still `@testable import Noto` (the shared files
compile into the Noto module); `Noto2Tests` imports `Noto2`. Simulator seeding for Noto 2:
`.maestro/seed-vault.sh <udid> --bundle-id com.eugenechan.Noto2`. The long-term direction
is to promote `NotoShared/Storage` (no UI) and `NotoShared/Editor` into packages
(`NotoStorage`, `NotoEditorKit`); see `.claude/brainstorm/noto2-app-plan.md`.
The launch-route file in `Noto2ControlShared/` is intentionally compiled into both
Noto 2 and its widget extension; extension-only UI stays in `Noto2QuickCaptureControl/`.

### Ownership Rules

- `MainAppView` owns app runtime lifecycle, not workspace routing.
- `VaultWorkspaceView` owns navigation and presentation, not low-level filesystem logic.
- UI surfaces emit `VaultWorkspaceIntent`; they do not mutate selection, `NavigationPath`, or vault files directly.
- `NotoSplitView` is a layout shell. It does not construct editors, create notes, or resolve document links.
- `VaultController` is the app-facing vault interface. It currently delegates through `MarkdownNoteStore` while package services continue to absorb non-UI behavior.
- `SearchIndexController` owns app-side search-index notifications and lifecycle triggers. `NotoSearch.SearchIndexCoordinator` owns package-level refresh mechanics.
- `NoteEditorSession` owns editor-local state and persistence timing for a single open note.
- `TextKit2EditorView` owns text input, selection, native rendering, and keyboard/input behavior.

### Remaining Compatibility Layers

- `MarkdownNoteStore` remains the main app-facing compatibility adapter for existing list and editor call sites.
- `CoordinatedFileManager` remains a small app compatibility wrapper over `NotoVault.CoordinatedVaultFileSystem`.
- Some package services are already in `NotoVault`, but the app still uses compatibility store methods in places while the migration continues incrementally.

## macOS runtime notes

### External vault / iCloud write access

On macOS, an external vault can appear to load correctly while still being non-writable. The real failure mode is not a TextKit bug; it is sandbox permission failure on the user-picked folder.

Key rules:

- The app must use `com.apple.security.files.user-selected.read-write`, not read-only.
- The saved security-scoped bookmark is the real permission token. A remembered raw path is not enough to regain write access after relaunch.
- The app should validate writability when resolving or setting an external vault.
- If the vault is not writable, the app should clear the broken saved state and force the user to re-pick the folder instead of silently opening a read-only vault.

The symptom for this bug class is: notes load, typing works visually, but saves/deletes fail with `NSCocoaErrorDomain Code=513`.

### iOS iCloud note loading

On iOS, the main iCloud failure mode is different. The app can misclassify a note as "needs download" even when the file is already present and readable.

Rules:

- do not gate note opening purely on `ubiquitousItemDownloadingStatus`
- try a real coordinated read first
- if the file is readable, open it immediately
- only enter the iCloud download loop if the file is genuinely unreadable

This matters because iCloud metadata can lag or be misleading for already-available files, especially at the root of the vault. The app should trust real readability over metadata.

### Multi-window note sync

The macOS app has two different sync paths:

- `NoteSyncCenter`: same-process, window-to-window sync inside the running app
- `VaultFileWatcher`: external filesystem/iCloud/Finder changes

This split is intentional. Same-app windows should not wait on the debounced file watcher to notice changes made by another window.

Current behavior:

- after a successful save, the editor publishes a note snapshot through `NoteSyncCenter`
- another window showing the same note applies that snapshot immediately if it has no local edits
- if the other window is dirty, it keeps local edits and shows a small conflict state instead of overwriting the editor

That means multi-window sync is immediate for clean windows, while still protecting unsaved local edits.

## iCloud read/write policy

Across both platforms, the app treats filesystem reality as more important than inferred cloud state.

- On macOS, the critical question is: `can this vault actually be written?`
- On iOS, the critical question is: `can this note actually be read right now?`

So the rule is:

- trust actual write success on macOS
- trust actual read success on iOS
- use iCloud metadata as a hint, not as the primary source of truth

## Runtime Lifecycles

### App Lifecycle

The launch path is:

1. `NotoApp` resolves the active vault through `VaultLocationManager`.
2. `MainAppView` creates the root `MarkdownNoteStore`, `VaultFileWatcher`, `DailyNotePrewarmer`, and `ReadwiseSyncController`.
3. On first task, `MainAppView` loads root items, prewarms today's note, refreshes saved Readwise token state, starts automatic Readwise sync, and refreshes the search index.
4. On foreground activation, `MainAppView` refreshes root state, restarts daily-note prewarming and Readwise sync, and refreshes search.
5. On external file changes, `VaultFileWatcher` triggers root reload and search-index refresh.

### Workspace and Navigation Lifecycle

`VaultWorkspaceView` is the single owner of workspace routing.

- Compact iPhone uses a root `NavigationStack` with `NoteRoute`.
- iPad and macOS use `NotoSplitView` as a shell around `NavigationSplitView`.
- The split detail selection, note history, search sheet, settings sheet, Today routing, last-opened-note restore, and document-link routing all live in `VaultWorkspaceView`.
- `FolderContentView`, `NotoSidebarView`, search results, and editor callbacks all report `VaultWorkspaceIntent`.
- `VaultWorkspaceView` translates each intent into either route changes or vault operations.

Opening a note is now:

1. A list row, sidebar row, search result, Today button, or document link emits an intent.
2. `VaultWorkspaceView` resolves the target note/store and updates compact or split navigation state.
3. `NoteEditorScreen` is created only by the workspace route/detail mapping.
4. `NoteEditorScreen` creates `NoteEditorSession` for that note.

### Editor Lifecycle

The live editor is `TextKit2EditorView`, composed by `NoteEditorScreen`.

The open path is:

1. `NoteEditorScreen` initializes `NoteEditorSession(store:note:isNew:)`.
2. `NoteEditorSession.loadNoteContent()` tries a real coordinated read first.
3. If the note is readable, the session applies the markdown immediately.
4. If the note is genuinely unavailable, the session starts the iCloud download loop.
5. `TextKit2EditorView` receives the session content and owns native editing, selection, rendering, and input behavior.

The edit/save path is:

1. `TextKit2EditorView` reports text changes to `NoteEditorSession.handleEditorChange(_:)`.
2. The session tracks latest editor text, pending local edits, title metadata, autosave debounce, and rename debounce.
3. Autosave calls `VaultController.save(_:for:in:)`, which currently delegates through `MarkdownNoteStore`.
4. Successful writes publish `NoteSyncCenter` snapshots for same-process multi-window sync.
5. On disappear, the session performs a final persist if local edits are still pending.

The remote-change path is:

- `VaultFileWatcher` handles external filesystem/iCloud changes.
- `NoteSyncCenter` handles same-process window-to-window snapshots.
- A clean editor applies same-process snapshots immediately.
- A dirty editor keeps local edits and records a pending remote snapshot instead of overwriting in-progress work.

### Search Lifecycle

Search is split between app lifecycle and package mechanics.

- `SearchIndexController` is the app-facing actor.
- It decides when app-visible refresh side effects happen and posts `.notoSearchIndexDidChange`.
- `NotoSearch.SearchIndexCoordinator` owns package-level single-flight full refreshes, debounced file refreshes, remove/replace behavior, and follow-up work after overlapping refreshes.
- `NoteSearchSheet` asks the search index for results and emits selected results back to `VaultWorkspaceView` as workspace navigation.

### Inbox / Digest Lifecycle

Noto 2's Capture tab writes `inbox/<YYYY-MM-DD>-<sha8>.md` (`CaptureFilingService`); the
Digest tab is the other half of that loop — it works the folder down to zero.

- `NotoDigest.DigestInbox` enumerates top-level `.md` files in `inbox/` and parses each into
  a `DigestEntry`. It does not recurse — the inbox is flat by construction.
- **`snoozed_until:` is the only key the digest adds.** `status:` stays `inbox` so gbrain's
  cycle keeps typing the file as a note; only the digest honours the snooze. A missing or
  unparseable stamp means *due*, never hidden — a typo in the vault must not be able to make
  a capture invisible with no way to reach it from the app.
- `NotoDigest.DigestFiling` owns the four actions. Add-to and Create write the destination
  **first** and delete the inbox file only on success, so a failed write costs a retry and
  never the thought. Both re-read the capture from disk at filing time rather than trusting
  the loaded entry — the digest can sit on screen while iCloud syncs an edit from another
  device.
- Filed and discarded captures are **deleted**, not archived: the text now lives in the
  destination note, and a second copy would double every search hit.
- A capture whose body is an evicted iCloud stub is surfaced as `isAvailable == false` and
  shown as downloading, rather than dropped from the queue (see the iCloud policy above).
- `Noto2/Digest/DigestModel` is the app-side queue: it pops the card only when the action
  succeeded, and tells `SearchIndexController` about both the written note and the removed
  capture so Noto 2's own index stays in step.
- **Discard is undoable, not confirmed.** `discard` returns the file's exact bytes and
  `restore` writes them back; the model holds them for as long as the outcome banner is on
  screen. A swipe that has already flown the card off should not then raise a modal.
- Gesture geometry lives in `Noto2/Digest/DigestSwipe.swift`, not the view: `DigestSwipe`
  (the four directions ↔ four actions) and `DigestSwipeResolver` (thresholds, dominant-axis
  resolution, per-direction signal strength). Put new gesture rules there so they stay
  testable — a threshold change that makes one action occasionally fire another is invisible
  in a screenshot.

### Mention Menu Lifecycle

The mention menu stays editor-scoped:

- `NoteEditorScreen` provides page mention candidates from the current store.
- `NoteEditorSession` and `TextKit2EditorView` keep the active note's text/editing state local.
- The provider excludes the currently open note and uses vault title/path resolution through the store/controller compatibility layer.
- Selecting a mention updates editor text; opening a document link flows back through `VaultWorkspaceView` as `openDocumentLink`.

### Readwise Lifecycle

Readwise is split across the app target and package:

- `ReadwiseSyncController` lives in the app target and owns token UI state, keychain access, automatic sync state, and Settings integration.
- `Packages/NotoReadwiseSync/Sources/NotoReadwiseSyncCore` owns API models, the Readwise client, Reader/Readwise sync engines, source-note rendering, and sync state.
- `Packages/NotoReadwiseSync/Sources/noto-readwise-sync` contains the CLI wrapper around the same core package.

### Deep Link Lifecycle

Noto notes are addressable by URL. There are two wire forms and both decode to the same
vault-relative path:

- `https://noto.eugenechantk.me/open#path=<encoded>` — **the canonical form.** A Universal Link:
  `https`, so messengers autolink it, and it opens the app directly with no browser hop. This is
  what everything should generate.
- `noto://open?path=<encoded>` — the original custom scheme. Still parsed so old links keep working,
  but nothing generates it any more. Most messengers refuse to autolink a non-`http` scheme, which
  is why the https form exists.

Ownership:

- `Packages/NotoVault/Sources/NotoVault/NotoDeepLink.swift` owns the whole codec — building both
  forms, parsing either, and validating the path. It is the single source of truth; do not hand-roll
  or re-encode a Noto URL anywhere else.
- Paths are rejected unless they are safe vault-relative markdown: no absolute paths, no `..`
  traversal, no empty components, `.md` only. Parsing also pins scheme, host, and path, so a
  look-alike host (`noto.eugenechantk.me.evil.com`) does not route.
- `NotoDeepLinkRouter` (`Noto/Support/NotoDeepLink.swift`) is the single entry point in the app.
  Both `.onOpenURL` and `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` in `NotoApp` feed
  it; it publishes `pendingDocumentPath`, which `VaultWorkspaceView` (defined in
  `Noto/Views/NoteListView.swift`) consumes via `openPendingDocumentLinkIfNeeded()`. Add new URL
  entry points by calling `router.open(_:)`, not by parsing.

The payload rides in the **fragment**, not the query, because fragments are never sent to the
origin — note titles stay out of edge access logs and out of the link-preview fetches messengers
make. Parsing accepts the query form too, only as a fallback for clients that strip fragments.

Supporting infrastructure:

- `com.apple.developer.associated-domains` = `applinks:noto.eugenechantk.me` in `Noto/Noto.entitlements`.
  It must stay in lockstep with `NotoDeepLink.webHost`; a test pins the constant.
- `web/noto-links/` is the site behind that host — the `apple-app-site-association` file authorising
  appID `39GJBP8V5A.com.eugenechan.Noto`, plus an "Open in Noto" fallback page. The fallback exists
  because WhatsApp's in-app WKWebView does not honour Universal Links; a tap there fires `noto://`
  from a user gesture. Deploy with
  `npx wrangler pages deploy public --project-name noto-links --branch main` from that directory.
- Producers of links outside this repo: `noto-agent` (`Packages/NotoAgentCLI`) returns `deepLink` on
  mutation/search/read results, and the Readwise digest agent
  (`~/dev/inbox/readwise-auto-digest-agent`, `src/notoLink.ts`) mirrors the codec in TypeScript. Any
  consumer must treat a returned link as authoritative and never rebuild it.

**Known gap:** simulator builds do not enforce capability entitlements, so Universal Links are
verified on simulator but **not yet on physical devices**. The App ID needs the Associated Domains
capability enabled in the developer portal and the match AppStore profile regenerated before the
next device or TestFlight build; that build may otherwise fail to sign. See
`.codex/feature/noto-universal-links.md`.

## Feature set (running)

- semantic + keyword search on any snippet of text
- a way to dump ideas in, and process later (e.g. Today notes/Inbox)
  - between today notes and inbox, today notes is better for me, because i associate random thoughts with the day i thought of it + i can keep my journal there as well
- template, or auto-fill a node based on a template
  - e.g. for each day's journal, have a few questions as template, so that I don't have to find the questions and paste them in again every day
  - the template is determined by a higher level of categorization (e.g. tags)
- mention any snippet of text inline + view where each snippet of text is mentioned + linked editing
- markdown editor + image + url
- pull highlights and full text from readwise
- ai chat with all my notes
- quick time-to-first-keystroke and load time
- offline edit
- offline search
- sync across devices
- metadata & metadata templates
  - the metadata fields should also be a template, based on a higher level of categorization (e.g. tags)
- tags
  - i am not sure about tags; because my belief is that, if search is so great, there is no need for tagging or any form of categorization
  - but tags might be a good categorization tool for applying different templates or presets
- the editor should feel good for both writing small thoughts, and a large body of text
  - small thoughts: 1 sentence, maybe with some bullet points
  - large body of text: podcast scripts
  - i don't need to think about how to format either, it just looks good for both

## Feature brainstorm

### Markdown editor + image + URL

### 3. Semantic + keyword search

Sometimes I know exactly the words in the block to search for it.
Sometimes I know the synonyms or similar words in the block to seach for it
Sometimes I only know the meaning around that block to search for the block

An intelligent search should be able to surface blocks for the three situations above and rank them intelligent that matches the most to the search query.

An intelligent search should be able to understand semantics so it can "search by meaning", but also have flexibilty for hard filters, like exact word matching.

An intelligent search does not need me to switch between semantic and keyword search. It should intelligently rerank blocks that is semantically similar and/or keyword matched so that the ranking reflects how closely the blocks answer/match with my search query.

This search should work offline as well.

This also serves as the backbone for AI chat, which requires some grounding from the blocks I wrote.

### Today notes / Inbox / An easy way to dump ideas

### Templates & auto-fill

### Bidirectional linking and editing

### Readwise integration

### AI chat with notes

### Quick load time & time-to-first-keystroke

### Offline edit

### Offline search

### Metadata & metadata templates

### Tags

### Flexible editor for small thoughts and large text
