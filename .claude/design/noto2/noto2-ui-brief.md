# Noto 2 — UI brief: Capture & Search (minimal, native)

**Date:** 2026-08-23 · **For:** the session implementing `Noto2/` · **References:** `refs/*.jpg` (Mobbin captures, 720w where available) · **Source of refs:** Mobbin MCP `search_screens` + Mobbin screen library.

**Design stance, in one line:** *iOS 26 system chrome, no custom chrome.* Everything below uses stock SwiftUI/UIKit — `NavigationStack` + toolbar (Liquid Glass comes free), `.searchable`, plain `List`, `ContentUnavailableView`, system materials, SF Symbols, Dynamic Type. The only "design" is what we remove.

---

## 0. What Mobbin says minimal capture + search look like

| Ref | App | What to steal | What to skip |
|---|---|---|---|
| `capture-01-apple-journal` | Apple Journal (new entry) | Full-bleed text, **no nav title**, back chevron left, filled **✓ circle** right, body starts under the bar at the first line. Toolbar is the whole UI. | The 6-icon bottom strip (media/voice/location) |
| `capture-02-slopes-add-note` | Slopes "Add a Note" | Paired **✕ / ✓ circles** in the header (matches our own sheet HIG: circular ✕/✓, orange confirm). Placeholder-only body. | Title + "private" sublabel |
| `capture-06-raycast-blank-note` | Raycast Notes | The near-empty sheet: chevron, a couple of glyphs, *"Heading 1"* as the only thing on screen. Character count as a quiet footer. | Undo/redo icons |
| `capture-07-stoic-fullbleed` | stoic. journal | Large readable body font on a warm blank page; ✕ top-right; nothing else until you scroll. | Formatting bar |
| `capture-03/04/05` | Starling · Beli · Calm | The pure system pattern: `Cancel · Title · Save`, one placeholder line ("Tips, tricks, things to remember"). Shows how little is needed. | — |
| `search-01-apple-notes-top-hits` | Apple Notes | Search field **pinned at the bottom** above the keyboard; "Top Hits · 2 Found" section header; rows = title + time + snippet, **matched term tinted** (not highlighted-boxed). | Attachments section |
| `search-02-google-gemini-results` | Gemini | Result row = `Title · date` on one line, **one snippet line with the match in bold** under it; "6 results matching 'to do'" header. Zero chrome. | — |
| `search-03-apple-books-snippets` | Apple Books in-book find | Body-match rows: location header + serif snippet with **bold match**; search field pinned bottom. The best "title + body" result density. | — |
| `search-05-otter-highlighted` | Otter | "1 result" count, per-note group with multiple snippet lines, yellow `mark`-style highlight | Avatars |
| `search-04-evernote-ai-answer` | Evernote AI search | The exact composition we want — **answer card → "3 RESULTS" → rows** — but too heavy (borders, feedback row, thumbnails). Use the order, not the styling. | Everything decorative |
| `search-06-instacart-ai-summary` | Instacart | The lightest AI summary: **plain text paragraph under the query, "Powered by AI" caption, "Go to regular results" link**. No card at all. | Product grid |
| `search-07-craft-find`, `search-08-raycast-notes-list` | Craft · Raycast | Sectioned-by-day plain lists; grey rounded search field at the bottom. | — |

**Convergence:** minimal capture = *a bar and a page*; minimal search = *a field, a count, and rows with the match emphasized* — the summary is a paragraph, not a widget.

---

## 1. Capture screen — target

Current draft (`Noto2/Capture/CaptureScreen.swift`) is close. Changes, in priority order:

### 1.1 Remove the title; make the bar disappear into the page
- `.navigationTitle("")` + `.toolbarTitleDisplayMode(.inline)` — no "Capture" word. The tab label already says it. (Journal, Raycast, stoic. all do this.)
- Keep `TextKit2EditorView` full-bleed, `autoFocus: true`. Body text should start ~16pt below the bar, same leading inset as the note editor (so Capture and Note feel like one surface).
- Background: `AppTheme.background` edge-to-edge; no separators, no card.

### 1.2 Toolbar = exactly two controls
- **Leading:** `Button("Discard", systemImage: "xmark")` — only when draft non-empty (as now), role `.destructive` not needed; confirm with a `confirmationDialog` only if draft > 200 chars.
- **Trailing:** **filled circular ✓** — `Button { send() } label: { Image(systemName: "checkmark") }` with `.buttonStyle(.borderedProminent)` + `.buttonBorderShape(.circle)` + `.tint(AppTheme.accent)` (orange, per our sheet convention; Journal uses the same shape in purple). Disabled (`.disabled(!canSend)`) renders as a hollow/grey circle — that *is* the empty-state affordance; no placeholder button text. Keep `paperplane` out — the check reads "filed", which is the mental model.
- While sending: swap the glyph for `ProgressView().controlSize(.small)` inside the same circle; no layout shift.

### 1.3 Empty placeholder, one line
- When `draft` is empty, overlay a single placeholder in the editor's first-line position: **"What's on your mind?"** in `AppTheme.mutedText`, `.body` — Liven/Beli pattern. Fade out on first keystroke. (If `TextKit2EditorView` has no placeholder API, a `Text` overlay aligned to the editor's text inset, `allowsHitTesting(false)`, is fine.)

### 1.4 Confirmation: quieter, native
- Replace the material banner with a **toolbar-bottom status line** that appears for 1.5 s: `Text("Filed · inbox/2026-08-23-a1b2c3d4.md")` in `.footnote` `mutedText`, `.transition(.opacity)`, placed in `.safeAreaInset(edge: .bottom)` so it sits above the keyboard. Haptic stays. (Raycast shows "0 characters" in exactly this slot — same register.)
- "Already filed today" → same line, `doc.on.doc` glyph, no colour change.

### 1.5 Footer count (optional, cheap)
- Same bottom slot when idle: `"\(wordCount) words"` in `mutedText`, only once draft ≥ 20 words. Gives the page a floor without adding chrome.

### 1.6 Keep
- Draft persistence in `@AppStorage`, document-id bump on clear, `scrollDismissesKeyboard` not needed (editor owns the keyboard), the error `alert`.

**Identifiers:** keep `captureEditor`, `captureSendButton`, `captureDiscardButton`; rename `captureConfirmationBanner` → `captureStatusLine`; add `capturePlaceholder`.

---

## 2. Search screen — target

Current draft (`Noto2/Search/SearchScreen.swift`) has the right order (summary → count → rows). Changes:

### 2.1 Field placement & chrome
- Keep `.searchable(placement: .navigationBarDrawer(displayMode: .always))` — on iOS 26 this renders the Liquid Glass search field; it's the system answer to Notes' bottom field, and the keyboard already sits under it. `.navigationTitle("")` here too; drop "Search" — the field's prompt carries it.
- Prompt: **"Search notes"** (shorter than "Search titles and notes").
- Toolbar trailing `gearshape` → move to a **`Menu` under an `ellipsis.circle`** with "OpenRouter key…" and "Rebuild index". One glyph, fewer words; settings are a rare action.

### 2.2 Result row = Gemini/Notes density
```
Title (body, semibold, 1 line)                         Aug 12   ← date right-aligned, footnote, muted
…snippet with the **matched term** emphasized… (subheadline, 2 lines, secondaryText)
Folder › Subfolder (caption, mutedText, 1 line)        ← only if not root
```
- **Emphasize the match:** split `result.snippet` on the query tokens and render matches in `AppTheme.primaryText` + `.semibold` (Notes/Gemini). Apple Books' serif is lovely but our body is sans; weight + colour is enough. No yellow `mark` (Otter) — too loud.
- Section glyph for `kind == .section`: keep, but put it *before* the title at `.caption2` so the row's left edge tells you it's a heading hit.
- Row insets: `listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))`, `listRowSeparator(.visible)` with `.listRowSeparatorTint(AppTheme.separator)`. Plain list, no cards.

### 2.3 Count header
- `"\(n) results"` → **`"\(n) results for “\(query)”"`** in `.footnote` uppercase-less, `mutedText` (Gemini: "6 results matching 'to do'"). Use `Section(header:)` with `.textCase(nil)`.

### 2.4 Summary: paragraph, not widget (Instacart)
- Drop the rounded card background. Render the summary as a **plain paragraph at the top of the list**, `.body`, `primaryText`, with a one-line caption above it: `sparkles` + **"Summary"** in `.footnote` `mutedText`, and while streaming append a `ProgressView().controlSize(.mini)` to that caption. Below the paragraph, a `.caption` `mutedText` line: **"From the top \(k) notes · AI-generated"**.
- States:
  - `needsKey`: caption only — **"Add an OpenRouter key to summarize"** as a `Button` styled `.plain` in the accent colour (a link, not a bordered button).
  - `failed`: caption line in `mutedText` — "Summary unavailable · Retry" (Retry as inline link). Never red body text.
  - `idle`/no results: render nothing (as now).
- Streaming text: append deltas into the same `Text`; no typing cursor, no skeleton.

### 2.5 Empty states via `ContentUnavailableView`
- No query: `ContentUnavailableView("Search your notes", systemImage: "magnifyingglass", description: Text("\(notes) notes indexed"))` — use `.search` variant when query non-empty & zero results: `ContentUnavailableView.search(text: query)`. Replace the hand-rolled rows.
- Indexing in progress: keep the footnote under the description ("building semantic index…").

### 2.6 Keep
- `scrollDismissesKeyboard(.interactively)`, `autocorrectionDisabled`, re-run on `notoSearchIndexDidChange`, navigation into `NoteScreen`.

**Identifiers:** keep all; add `searchSummaryCaption`, `searchResultTitle`, `searchResultSnippet`, `searchMenuButton` (replaces `searchSettingsButton`).

---

## 3. Shared tokens (so both screens read as one app)
- Text: `.body` for content, `.subheadline` for snippets, `.footnote`/`.caption` for meta. No custom sizes.
- Colour: `AppTheme.primaryText / secondaryText / mutedText / separator / background`, accent orange for the one confirming control per screen. Nothing else coloured.
- Corner radii: none on the page (no cards). The only rounded things are system: the search field and the ✓ circle.
- Motion: `.opacity` transitions only; no springs on status lines.

## 4. Acceptance (for the auditor)
- Capture: no nav title; ✓ circle disabled when empty, enabled on first non-whitespace char; send clears and shows the status line ≤ 1.5 s above keyboard; placeholder visible only when empty.
- Search: field is the system `.searchable`; rows show title/date/snippet with the query term bolded; count line reads "N results for “q”"; summary is a plain paragraph with a "Summary" caption and no card; `ContentUnavailableView` for both empty states.

---

## 5. Implementation record (2026-08-24, from the implementing session)
- Folded into `Noto2/Capture/CaptureScreen.swift` and `Noto2/Search/SearchScreen.swift`; auditor run against §4.
- **Confirmed decision (Eugene):** the ✓ stays in the top-right toolbar — never at the bottom, where the keyboard covers it. Only the transient status line uses the bottom safe-area inset.
- **Addition beyond the brief:** semantic results are gated (`semanticMinScore 0.76`, relative gap `0.12` on `HybridNoteSearch.Request`; granite cosine floor for unrelated text ≈ 0.70) and rows dedupe to one per note (`SearchModel.dedupedByNote`). Tests: `Noto2Tests/SearchIntegrationTests.swift`.
