# Feature: wiki-links

## User Story

Eugene's notes contain wiki-style links in the form `[[vault-relative-path]]` (e.g. `[[media/page-name]]`). Today they render as plain text. They should render as hyperlinks that open the referenced note inside Noto, on iOS/iPadOS and macOS.

## User Flow

1. A note contains `[[media/page-name]]`.
2. In the editor, the text renders like an existing markdown link: `media/page-name` shown in link color with underline, the `[[` `]]` brackets concealed.
3. Tapping (iOS) or clicking (macOS) the link opens the note at `media/page-name.md` via the existing document-link routing (`onOpenDocumentLink`).
4. Placing the caret in / deleting into the link reveals the raw `[[media/page-name]]` markdown for editing, same as `[title](url)` links do today.
5. Cmd+K (toggle hyperlink) with the caret inside a wiki link unwraps it to plain `media/page-name`.

## Design Decisions

- **Reuse `HyperlinkMarkdown`** (`Noto/Editor/BlockEditingCommands.swift`). It already models `[title](url)` links with a `.vaultDocument(relativePath:)` target carried as a `noto-document://open?path=…` `.link` attribute, and both platforms already route that target through `onOpenDocumentLink`. Wiki links become a second match `Kind` in the same parser so every downstream consumer (styling, concealment, tap, click, cursor, reveal-on-delete, toggle) works without new plumbing.
- **Path resolution:** inner text is the vault-relative path; append `.md` when the suffix is missing (`[[media/page-name]]` → `media/page-name.md`; `[[media/page.md]]` stays). Validation reuses `normalizedVaultRelativePath` rules (no absolute paths, no `.`/`..` traversal, no schemes). Invalid paths simply don't link.
- **Display:** the inner path text is shown as the link label (Obsidian-style). `[[path|alias]]` aliases are out of scope — the regex excludes `|` so aliased forms stay plain text rather than mislinking.
- **Match shape:** `titleRange` = `urlRange` = inner text. Syntax concealment moves from two hardcoded `[title](url)`-shaped computations (iOS `applyHyperlinkStyles`, macOS `hyperlinkSyntaxRanges`) onto a `Match.syntaxRanges` property that switches on kind (`[[` + `]]` for wiki).
- **Non-existent targets** behave exactly like an existing `[label](path.md)` link to a missing note — same routing, same downstream handling. No new UX invented here.

## Success Criteria

- SC1: `[[path]]` parses as a hyperlink match with correct full/title ranges and a `.vaultDocument` target of `path.md` (`.md` appended only when missing).
- SC2: Invalid wiki paths (`[[]]`, `[[/abs]]`, `[[../up]]`, `[[a|b]]`, unclosed `[[a`) do not produce links.
- SC3: Wiki and markdown links coexist on one line; ranges don't collide; `![[…]]`-style image conflicts don't arise (`![…](…)` images remain untouched).
- SC4: Editor renders wiki links in link color with brackets concealed; revealed state shows the raw markdown (verified via render-attribute tests + simulator).
- SC5: Tap on iOS / click on macOS opens the referenced note (existing `onOpenDocumentLink` path; simulator/visual audit for iOS, code-path parity + macOS build for macOS).
- SC6: Cmd+K on a wiki link unwraps it to the plain path text.
- SC7: Deleting into a concealed wiki link reveals the raw markdown first (existing reveal-on-delete behavior extends to wiki matches).

## Test Strategy

All logic lives in the app target's `HyperlinkMarkdown` / render-attribute layer, so app-target Swift Testing covers SC1–SC4, SC6, SC7 deterministically. SC5's tap wiring is existing code driven by the match target; iOS visual audit provides final proof.

## Tests

### Unit — `NotoTests/BlockEditingCommandsTests.swift`
- wiki match parsing: ranges, kind, title/urlText — SC1
- `.md` suffix appending + already-suffixed passthrough — SC1
- invalid paths not matched — SC2
- mixed markdown + wiki on one line, adjacent `[[a]] [[b]]` — SC3
- `syntaxRanges` for both kinds — SC4
- `toggledHyperlink` unwraps wiki link — SC6

### Integration — `NotoTests/TextKit2MarkdownLayoutTests.swift`
- render attributes: `.link` + linkColor on inner range, concealed brackets, revealed state — SC4, SC7

## Implementation Details

- `HyperlinkMarkdown.Match` gains `kind: Kind` (`.markdown` / `.wiki`) and `syntaxRanges: [NSRange]`.
- `matches(in:)` merges markdown-regex and wiki-regex (`\[\[([^\[\]|\n]+)\]\]`) matches, sorted by location.
- `Match.target` switches on kind; wiki targets validated through `normalizedVaultRelativePath` after `.md` suffixing.
- Call sites updated: iOS `applyHyperlinkStyles` + macOS `hyperlinkSyntaxRanges` use `match.syntaxRanges`; macOS `hyperlinkMatches(in:)` line-rebasing carries `kind` through.

## Residual Risks

- macOS click/hover verified by code-path parity and build + unit tests, not a full GUI automation run.
- Pixel-exact concealment metrics assumed identical to existing hyperlink concealment (same mechanism).

## Bugs

_None yet._
