# Noto AI Chat — Native Component Breakdown (iOS)

Native spec for implementing the **Noto AI Chat** design (claude.ai/design → `Noto AI Chat.html`,
13 artboards in 6 sections) on top of the **NotoChat** Swift package. Design concept doc:
`.claude/brainstorm/ai-chat-ui-concept.md`. This is the manifest the `claude-design-verifier`
checks against — judged per component, not per whole screen.

> Ground truth for visual verification: render `Noto AI Chat.html` (UI-download the project to
> `Design/aichat/` then `python3 -m http.server`, or use the live claude.ai/design preview). The
> shared primitives (tokens, ios-frame, dock) match the existing `Design/v2/` download.

## Scope

- **Phase 1 (this milestone):** the real floating dock (file list + editor) as the entry; the chat
  sheet core — `ChatSession` view-model wired to `ChatAgent.sendStreaming`; streaming ✶ NOTO
  markdown reply, interleaved collapsible tool trace (working/done), SOURCES; composer + mention
  tags; Keychain OpenRouter key entry (Settings).
- **Phase 2 (later):** Add-context picker (search + nested paths), chat history list, save-to-Chats,
  ••• menu actions (rename/delete), iPad/macOS.

## Design tokens (from `Design/v2` noto-platforms / noto-minimal-editor)

| Token | Value | Use |
|---|---|---|
| `bg` | `#0E1116` | sheet / surface background |
| `ink` | `#ECECEE` | body text |
| `head` | `#FFFFFF` | headings, strong |
| `faint` | `rgba(236,236,238,0.34)` | captions, tool-step labels, breadcrumbs, citations |
| `muted` | `rgba(236,236,238,0.10)` | hairline dividers |
| `accent` | `#FF6A2E` | send button, checks, active states, caret |
| `pill` | `#2C2C2E` | dock capsule, user-message pill fill |
| `userPill` | `rgba(255,255,255,0.06–0.08)` | right-aligned user message |
| `codeBg` | faint orange-tinted chip | inline `code` spans |
| font | `-apple-system / SF Pro Text` | everything (SwiftUI default) |

Type ramp (approx, from artboards): note H2 18pt/700 head; body 16pt/1.55 ink; secondary 13–14pt
faint; tool-step label ~14pt faint; eyebrow "✶ NOTO" ~11pt tracked, accent ✶.

Icon → SF Symbol map: search→`magnifyingglass`, doc→`doc`/`doc.text`, folder→`folder`,
chat→`bubble.left` (or `bubble.left.and.text`), new note→`square.and.pencil`, daily→`calendar`,
send→`arrow.up`, attach `+`→`plus`, check→`checkmark`, chevron→`chevron.right`, close→`xmark`,
ellipsis→`ellipsis`, sparkle (✶ NOTO)→`sparkle`.

## Components (atoms → controls → content → screens)

Each: **native target** · (source = `noto-ai-chat.jsx`/`ios-frame.jsx` in the design) · HIG ref.

### Atoms
- **NOTOColor / NOTOFont** — token enum + Font helpers. Foundation; build first. (— · —)
- **Eyebrow "✶ NOTO"** — sparkle + tracked caps label above an AI reply. (custom · —)
- **InlineCodeChip** — orange-tinted rounded `code` span. (custom · —)
- **CitationSuperscript** — faint ¹²³ after a claim; tap scrolls to SOURCES. (custom · —)
- **DocChip / NoteRef** — small doc glyph + note title (+ optional ✕). Used by mention tags,
  SOURCES rows, tool-step targets, context-file line. ONE component, variants. (custom · HIG: Token)

### Controls
- **FloatingDock** — glass capsule, `daily · search · chat · new`; chat icon gets accent ring when
  it's the active/entry affordance. Shared by file list + editor. Theme the real iOS 26
  `.glassEffect(.regular.interactive(), in: .capsule)` in a `GlassEffectContainer`, `#available`
  gated, material fallback. (ios-frame `NFloatingCapsule` · HIG: Toolbar / Liquid Glass)
- **SheetHeader** — grabber + title (chat name / "New chat") + ••• (and ✕ on picker sheets / ✓ on
  confirm). Use native `.presentationDetents([.large])` sheet; build the header row. NO back chevron
  (swipe-down dismiss). (custom · HIG: Sheets)
- **Composer** — `+` (attach) · "Ask anything…/Reply…" text field · accent circular ↑ send;
  mention tags row ABOVE the field when notes are pending. (custom · HIG: Keyboard accessory / Text field)
- **MoreMenu (•••)** — pull-down: New chat · Chat history · Attach files · Rename · Delete(red).
  Native `Menu`. (custom · HIG: Pull-down menu) [Phase 2 for actions]
- **ToolStep** — collapsible row: glyph + action + target (collapsed = call); expand → faint
  indented result block (grep snippets / read excerpt / list). Left-rule grouping. WORKING variant:
  check (done) / spinner (active). (custom · HIG: Disclosure) **Core P1.**

### Content
- **UserMessage** — right-aligned light pill; mentioned notes (DocChip list) listed BELOW it.
- **AIReply** — note-native markdown render (H2/para/bullets/bold/inline code) under the Eyebrow.
  Ordered block sequence: text blocks + ToolStep blocks **interleaved**; SOURCES group at the end.
  Markdown: render with `AttributedString(markdown:)` or a lightweight renderer matching the editor.
- **SourcesGroup** — "SOURCES" caption + numbered NoteRef rows (no pill/border), tappable.
- **ContextFileLine / MentionTag** — pending mentions as tags above composer; mentions-below-bubble
  as a faint DocChip list. (replaces the old below-composer line)
- **ChatHistoryRow** — title · snippet · relative date (reuse file-browser row). [Phase 2]
- **AddContextPickerRow** — DocChip + vault-path breadcrumb subtitle + multi-select check. [Phase 2]

### Screens (artboards → SwiftUI views)
1. **Triggers** → `FloatingDock` on `NoteListView` + `NoteEditorScreen` (chat icon presents the sheet).
2. **New chat (empty)** → `ChatSheet` empty state: bare "Chat about notes" + Composer + keyboard.
3. **Composing** → `ChatSheet` with pending MentionTags above the field.
4/5/6/10/11. **Conversation / tool use** → `ChatSheet` message list (UserMessage + AIReply +
   interleaved ToolStep) driven by `ChatSession`.
7. **••• menu** → `MoreMenu`. 8. **Chat history** → `ChatHistorySheet` [P2].
9. **AI thinking** → `ChatSession.phase == .thinking` shimmer.
12/13. **Add context** → `AddContextSheet` (browse + search + nested breadcrumbs) [P2].

## Package mapping (NotoChat — confirmed signatures)

```
ChatAgent(client: OpenRouterClient, tools: VaultTools(root: vaultURL), model: defaultModel="google/gemini-3.1-flash-lite")
agent.sendStreaming(_ userText, mentioned: [String] /*vault-rel paths*/, history: [ChatMessage])
  -> AsyncThrowingStream<AgentEvent, Error>
AgentEvent: .toolCallStarted(name,arguments) | .toolCallFinished(name,summary) | .textDelta(String) | .finished(AgentResult)
AgentResult { answer; sources:[String]; messages:[ChatMessage]; rounds:Int; hitRoundLimit:Bool }
OpenRouterClient(.init(apiKey:<Keychain>, referer:"https://noto.app", title:"Noto"))
ChatTranscript{...}.markdown(); saveTranscript(_, toChatsDirectory: vaultURL/Chats)  // P2
```

| Design element | Package |
|---|---|
| Mention tags above composer | `mentioned: [String]` paths → `sendStreaming` |
| Tool trace (working→done) | `.toolCallStarted` / `.toolCallFinished` (name, arguments, summary) |
| Streaming ✶ NOTO markdown | `.textDelta` chunks appended |
| SOURCES citations | `AgentResult.sources` (validated vault paths) |
| hit round limit | `AgentResult.hitRoundLimit` → gentle inline error |
| Save chat to Chats/ | `ChatTranscript().markdown()` + `saveTranscript` [P2] |

## ChatSession view-model (the wiring — `@MainActor ObservableObject`)

Owns a `ChatAgent`; `send(text, mentioned:)` spawns a `Task` consuming `sendStreaming` and publishes:
- `messages: [ChatTurn]` — each turn an ordered `[Block]` where `Block = .text(String) | .tool(ToolStepVM)`,
  so tool steps interleave with streamed text in arrival order.
- on `.toolCallStarted` → append `.tool(active)`; `.toolCallFinished` → mark that step done + summary;
  `.textDelta` → append/extend the trailing `.text` block; `.finished` → set `sources`, persist `messages`
  as `history` for the next turn, handle `hitRoundLimit`.
- `phase: idle | thinking | streaming | error`. Key from Keychain (`OpenRouterKeyStore`); if absent →
  prompt the Settings key-entry flow before sending.

## Navigation model

File list / editor → tap dock chat icon → **`ChatSheet`** rises (`.presentationDetents([.large])`,
`.presentationBackground`, grabber) over the dimmed presenter. From a note, the note is pre-attached
(`mentioned`). Swipe down dismisses. ••• → New chat / History / Attach / Rename / Delete.

## a11y identifiers (verifier contract — add during implementation)

`dock`, `dock.chat`, `dock.daily`, `dock.search`, `dock.new`; `chatSheet`, `chatSheet.grabber`,
`chatSheet.more`, `chatSheet.title`; `composer`, `composer.field`, `composer.send`, `composer.attach`,
`composer.mentionTag.<path>`; `chat.userMessage`, `chat.aiReply`, `chat.eyebrow`; `toolStep.<name>`,
`toolStep.<name>.disclosure`, `toolStep.result`; `sources`, `sources.row.<path>`;
`addContext.sheet`, `addContext.search`, `addContext.row.<path>`; `chatHistory.sheet`, `settings.openRouterKey`.

## Build order

1. Foundation: `NOTOColor`/`NOTOFont` tokens.
2. `OpenRouterKeyStore` (Keychain) + Settings key-entry row.
3. `ChatSession` view-model (wire `sendStreaming`; unit-test the event→blocks reduction with a mock client).
4. Atoms (Eyebrow, DocChip/NoteRef, InlineCodeChip, CitationSuperscript).
5. `ToolStep` (collapsible) → `AIReply` (interleaved blocks + SOURCES) → `UserMessage`.
6. `Composer` (+ mention tags) → `ChatSheet` (header + message list + composer) → empty/thinking states.
7. `FloatingDock` (Liquid Glass) on `NoteListView` + `NoteEditorScreen`; present `ChatSheet`.
8. Verify each screen with `claude-design-verifier`; fix; repeat.
