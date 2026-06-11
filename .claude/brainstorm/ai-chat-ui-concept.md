# AI Chat — UI Concept (iOS first)

Status: DONE — built & verified in the Claude Design webapp. Lives in its OWN file
**Noto AI Chat.html** (moved out of System.html), `components/noto-ai-chat.jsx`, 8 iOS artboards.
Not yet implemented in the app.
Date: 2026-06-06

## Revisions after first build (the current locked-in model)

- **Presentation = large-detent iOS sheet** (grabber + title + •••, swipe-down dismiss, no back
  chevron) over a dimmed presenter peeking at top — file list from the dock, editor from a note.
  Replaced the earlier full-screen-push idea.
- **Entry = tap-to-new-chat.** Dock chat icon opens a NEW empty chat sheet immediately; there is
  no Chats-history landing screen from the dock. History moved into the sheet's ••• menu
  (New chat · Chat history · Attach files · Rename · Delete); "Chat history" opens the past-chats
  list as its own sheet.
- **Citations.** AI replies cite sources: faint footnote superscripts (¹²³) after cited claims +
  a quiet "SOURCES" group at the reply end (number · doc glyph · note title, no pill/border).
- **Context files below the composer.** Attached/quoted files moved from under the top bar to a
  minimal faint line just below the input (doc glyph + comma-separated faint filenames + subtle ✕),
  not bordered tags — visually consistent with the citation references.

## Revisions round 2 (the current locked-in model — 11 artboards)

- **Trigger views added.** Two explicit entry artboards: Trigger·Home (file list + dock with the
  chat icon ringed and a "New chat" callout) and Trigger·Note (editor ••• with "Chat about this
  note" highlighted).
- **Mentions vs citations split.** USER side = mentions: selecting a note shows it as a tag ABOVE
  the text field while composing, and the mentioned notes are listed BELOW the sent user bubble.
  AI side = citations: superscripts + SOURCES group (unchanged). This replaced the round-1
  "context line below the composer."
- **Empty state simplified** to just a "Chat about notes" heading + composer (no suggested
  questions, no attach subtitle).
- **Add context: search + nested paths.** A search field sits atop the picker; every note row
  shows its vault path as a faint breadcrumb subtitle; search returns a flat list across all levels
  with paths, so a deeply-nested note (e.g. Projects › Alpha › Q2) is identifiable and selectable.

## Revisions round 3

- **Editor trigger via the dock, not the ••• menu.** The editor view now carries the floating
  bottom dock too (`daily · search · chat · new`); chat is triggered from the dock's chat icon
  (note pre-attached). The editor ••• menu is back to Share · Pin · Find · Delete. This also
  applied to the renamed **Noto v2.html** (was Noto System.html) editor reading/scrolled states,
  via a shared `FloatingDock`. (Reverses the old "editor is chrome-free / no dock" rule.)
- **Tool use in the AI response (interleaved).** The chat engine (NotoChat: grep/read/list agent
  loop + streaming) surfaces its tools inside the AI turn as note-native, collapsible **tool steps**
  (collapsed = call; expanded = result — grep snippets / read excerpt / file list). The turn is an
  ordered sequence of blocks — text and tool steps **interleaved**, so steps appear at the top AND
  between paragraphs mid-response (not one block at the top). WORKING streams text with inline steps
  appearing between paragraphs (checks + spinner + dots); DONE shows steps inline where they
  occurred (one expanded), answer text flowing around them, "Worked across N notes ›" as an optional
  collapse-all.

## Canvas organization (round 4)

The 13 artboards are grouped into 6 purpose-driven DCSections (each with a rich subtitle +
a margin sticky-note for its key microinteraction): **Triggers** (Home, Note) · **New chat &
mentions** (New chat, Composing) · **Adding context** (Browse, Search) · **The conversation**
(Single-file, Multi-file) · **Generating & tool use** (Thinking, Tool working, Tool done) ·
**Managing the chat** (••• menu, Chat history).

## Artboard set (current, 13)
01 Trigger·Home · 02 Trigger·Note (editor + dock) · 03 New chat (empty) · 04 Composing (mention
tag above field) · 05 Conversation single-file · 06 Conversation multi-file · 07 ••• menu ·
08 Chat history · 09 AI thinking · 10 Conversation tool use — WORKING · 11 Conversation tool use —
DONE · 12 Add context browse (search + folder subtitles) · 13 Add context search (nested breadcrumbs).

## Feature

Chat with your notes. Attach one or many vault files as context, ask questions, and the
conversation is itself saved into the vault as a markdown file — so chats are notes too.

Requirements (from Eugene):
1. Chat with a single file, or multiple files in the vault.
2. See previous chats.
3. Chats are saved in the vault.

## Decisions

- **Entry model — Global list + contextual launch.**
  - New 4th icon in the floating bottom dock (browse surfaces): `daily · search · chat · new`.
    Tapping it opens the **Chats history** list.
  - From the editor `•••` menu: **"Chat about this note"** — opens a new conversation with the
    current note pre-attached as context.
- **Message rendering — Note-native markdown.**
  - AI replies render as clean flowing markdown on the dark surface (headings, bold, bullets,
    inline code) — exactly like the Noto editor, no bubble.
  - User messages are a subtle right-aligned/indented treatment (light pill), de-emphasized.
- **Storage — chats are markdown files in the vault.**
  - A `Chats/` folder. Each chat = one `.md` file with frontmatter holding the attached file
    paths (context) + timestamps. The Chats history list is effectively that folder.
  - Consequence: chats appear in the file browser too; they're first-class notes.

## Design language (inherited — do not reinvent)

- Dark only: bg `#0E1116`, ink `#ECECEE`, head `#FFFFFF`, faint `rgba(236,236,238,0.34)`,
  accent orange `#FF6A2E`.
- Minimal outline icons (1.5–1.8 stroke), SF Pro sans.
- Browse surfaces carry the floating bottom dock; the editor is chrome-free (back + ••• top bar).
- Bottom sheets: grabber + paired circular ✕ (leading) / ✓ orange (trailing) header, inset-grouped lists.
- File-system rows: single line, directories first with a muted trailing `›`.

## iOS screen set (new "AI Chat" section, 402×874 artboards)

1. **Chats — history.** Large title "Chats". Single-line rows: chat title + muted snippet/relative
   date. "+ New chat" affordance. Updated floating dock (with the new chat icon) visible.
2. **New chat — empty.** Fresh conversation: short prompt / a few suggested starters, empty
   context, input bar at bottom (+ attach · "Ask anything…" · orange send), keyboard up.
3. **Conversation — single-file context.** Back/••• top bar. One context chip under it
   (doc icon + filename + ✕). A user message (right pill) then an AI reply rendered as markdown
   (## heading, paragraph, bullets, inline code). Pinned input bar.
4. **Conversation — multi-file context.** Same, with 2–3 context chips (chat across files) and an
   answer that references them. Demonstrates multi-file chat.
5. **Attach files — vault picker (bottom sheet).** HIG sheet (grabber + ✕/✓). Browses the vault
   file system; multi-select with orange checkmarks to add files as context.
6. **Conversation — AI thinking/streaming.** Shimmer/typing indicator while the reply generates;
   keyboard dismissed.
7. **Editor → "Chat about this note".** The editor ••• menu open over the dimmed note, with the
   "Chat about this note" item highlighted (the contextual entry point).
