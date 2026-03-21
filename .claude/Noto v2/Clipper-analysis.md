# Web Clipper for Noto v2 — Feasibility Analysis

Based on deep exploration of [obsidian-clipper](https://github.com/obsidianmd/obsidian-clipper) and [defuddle](https://github.com/kepano/defuddle).

---

## How Obsidian's Clipper Works

### Architecture: Three Components

```
Browser Extension (WebExtension)
  ├── Content Script (injected into pages)
  │   └── Handles highlights, element selection, page extraction
  ├── Background Service Worker
  │   └── Message routing, context menus, URI scheme dispatch
  └── Popup/Side Panel UI
      └── Template selection, preview, clip settings
          │
          ▼
      Defuddle (extraction library)
          │ HTML → clean Markdown
          ▼
      obsidian://new?file=...&clipboard
          │ URI scheme + clipboard
          ▼
      Obsidian App (receives and saves the note)
```

### Defuddle: The Content Extraction Engine

Defuddle is the real workhorse — a TypeScript library (MIT license, 5.5k stars) that does both readability parsing AND HTML-to-markdown conversion.

**Pipeline (10 steps):**
1. Extract schema.org JSON-LD before stripping scripts
2. Collect meta tags, extract metadata (title, author, date, description)
3. Check 13 site-specific extractors (Twitter, YouTube, Reddit, GitHub, ChatGPT, Claude, etc.)
4. Clone document, flatten shadow DOM, resolve React SSR boundaries
5. Apply mobile CSS (detect elements hidden on mobile)
6. Find main content via priority selectors + content scoring algorithm
7. Standardize footnotes and callouts
8. Remove clutter in 4 passes (hidden elements, ~500 CSS patterns, link density scoring)
9. Standardize HTML (heading normalization, code blocks, math, attribute stripping)
10. Resolve relative URLs to absolute

**Output:** Clean markdown + metadata (title, author, published date, description, site name, word count, language).

**Site-specific extractors (13):** Twitter/X (3 variants), Reddit (new + old), YouTube (with transcript + chapters), GitHub (issues + PRs with comments), Hacker News, ChatGPT, Claude, Grok, Gemini, BBCode.

### Highlights System

Full in-page highlighting:
- Select text → stored as XPath ranges per URL in `browser.storage.local`
- Three modes: inline (`==highlighted==` in markdown), replace content with highlights only, or ignore
- Can highlight elements too (images, video, audio), not just text
- Highlights persist across page reloads

### Template System

`{{variable|filter1|filter2}}` syntax with 50+ filters. Templates auto-trigger by URL pattern, regex, or schema.org type. Properties generate YAML frontmatter. Even supports LLM prompt variables (`{{prompt:"Summarize this"}}`) with 12+ AI provider integrations.

### Communication with Obsidian

Uses the `obsidian://` URI scheme:
- Default: copy markdown to clipboard → open `obsidian://new?file=...&clipboard` → Obsidian reads from clipboard
- Legacy: encode content in URI (limited by URL length)
- Supports: append, prepend, overwrite, vault selection, daily note targeting

---

## What It Would Take for Noto v2

### Option 1: Use Defuddle Directly (Recommended)

**Defuddle is MIT-licensed and designed to be used standalone.** It works in the browser, Node.js, and Cloudflare Workers. The core browser bundle has zero dependencies.

For Noto v2, the approach:

1. **Build a Safari Web Extension** (Xcode wrapper) that includes Defuddle for content extraction
2. **Register a `noto://` URI scheme** in the iOS app to receive clipped content
3. **The extension clips → converts to markdown via Defuddle → sends to Noto via URI scheme or Share Sheet**
4. **Noto writes the `.md` file** to the vault folder, file watcher picks it up

**What we get for free from Defuddle:**
- Readability parsing (main content extraction from any web page)
- HTML-to-markdown conversion with good table, code block, math, and footnote handling
- 13 site-specific extractors (Twitter, YouTube, Reddit, GitHub, etc.)
- Metadata extraction (title, author, date, description)
- Schema.org and meta tag parsing

**What we'd need to build:**
- Safari Web Extension shell (Xcode project, manifest, popup UI)
- Highlight system (XPath-based text selection persistence) — could port from Obsidian Clipper (also MIT)
- `noto://` URI scheme handler in the iOS app
- Template system (or start with a single default template)
- Frontmatter generation matching our `id`, `created`, `modified` format

### Option 2: Fork Obsidian Clipper

The entire Obsidian Clipper is MIT-licensed. We could fork it and replace:
- `obsidian://` URI calls → `noto://` URI calls
- Obsidian-specific template variables → Noto-specific ones
- Obsidian vault selection → Noto vault (single vault for now)

**Pros:** Full feature set immediately — highlights, templates, AI prompts, all 50+ filters.
**Cons:** It's a WebExtension (Chrome/Firefox/Safari), so the Chrome/Firefox parts are irrelevant for an iOS-only app. The Safari extension wrapper is already in the repo though.

### Option 3: iOS Share Sheet Only (Simplest)

Skip the browser extension entirely. Use iOS Share Sheet:

1. User taps Share in Safari → picks Noto
2. Noto's Share Extension receives the URL
3. Share Extension fetches the page, runs Defuddle (compiled to a framework), converts to markdown
4. Writes `.md` file to the vault folder
5. Done

**Pros:** No browser extension to maintain. Works from any app (Safari, Chrome, social media apps). Native iOS experience.
**Cons:** No in-page highlighting. No template selection before clipping. Limited UI in the Share Extension (Apple restricts Share Extension UI).

### Option 4: Hybrid (Share Sheet + Safari Extension)

- **Share Sheet** for quick clips from any app (URL → markdown → save)
- **Safari Web Extension** for rich clips with highlights and template selection

Build Share Sheet first (simpler, works everywhere), add the Safari extension later for power users.

---

## Effort Estimate

| Component | Using Defuddle | Building from scratch |
|-----------|---------------|----------------------|
| Content extraction (readability + HTML→MD) | **Free** — import Defuddle | 3-6 months (Defuddle is 5k+ lines with years of edge-case handling) |
| Metadata extraction | **Free** — Defuddle does this | 2-4 weeks |
| Site-specific extractors (13 sites) | **Free** — Defuddle includes them | 1-2 months |
| Safari Web Extension shell | 1-2 weeks | Same |
| Highlight system | 2-3 weeks (port from Clipper) | 4-6 weeks |
| Share Sheet extension | 1 week | Same |
| `noto://` URI scheme | 1 day | Same |
| Template system (basic) | 1-2 weeks | Same |
| Frontmatter generation | 1 day | Same |

**Total with Defuddle: ~4-6 weeks** for a functional clipper with highlights.
**Total from scratch: ~6-10 months** just for content extraction parity.

---

## Key Technical Consideration: Defuddle on iOS

Defuddle is TypeScript/JavaScript. On iOS, we have two options for running it:

1. **JavaScriptCore framework** — Apple's built-in JS engine. Can run Defuddle's Node.js bundle directly from Swift. No WebView needed. Fast.

2. **WKWebView** — Load Defuddle's browser bundle in a hidden WebView, pass it the page HTML, get markdown back.

3. **Rewrite in Swift** — Use Defuddle as a reference implementation and rewrite in Swift using `SwiftSoup` for HTML parsing + custom markdown conversion. Most work, but no JS dependency.

**Recommendation:** JavaScriptCore for the MVP. It's the fastest path to a working clipper. Rewrite in Swift later if JS performance or maintenance becomes an issue.

---

## Integration with Noto v2's Architecture

A clipped article becomes a note in the vault:

```markdown
---
id: 550e8400-e29b-41d4-a716-446655440000
created: 2026-03-17T10:30:00Z
modified: 2026-03-17T10:30:00Z
source: https://example.com/article
author: Jane Doe
clipped: true
---

# Article Title

Article content in markdown...

Paragraph one of the article.

Paragraph two with ==highlighted text== that the user selected.
```

Once saved as a `.md` file in the vault:
- The file watcher detects the new file
- The sidecar index adds it (note metadata, paragraph IDs)
- FTS5 and HNSW index it for search
- Paragraphs are immediately moveable and mentionable — a clipped article paragraph can be moved to a project note or mentioned from a daily note
- Semantic search can find conceptually related content across clipped articles and hand-written notes

**This is where Noto v2's architecture pays off.** A clipped article isn't a second-class citizen in a "web clips" silo — it's a full note with the same paragraph mobility, mentions, and search as everything else.

---

## Recommendation

1. **Use Defuddle** (MIT license) — don't rebuild content extraction from scratch
2. **Start with iOS Share Sheet** — simplest integration, works from any app
3. **Add Safari Web Extension later** — for highlights and template selection
4. **Run Defuddle via JavaScriptCore** — no WebView overhead, native JS engine
5. **Clipped articles are regular notes** — same vault, same index, same features
