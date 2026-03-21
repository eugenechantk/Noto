# Obsidian Web Clipper -- Deep Architecture Research

**Source:** https://github.com/obsidianmd/obsidian-clipper
**Version:** 1.2.1 (as of Mar 17, 2026)
**Pages explored:** 19
**Tech stack:** TypeScript 82.6%, SCSS, Webpack, Vitest

---

## 1. What It Is

A **cross-browser extension** (Chrome, Firefox, Safari/iOS/iPadOS, Edge) plus a **Node.js CLI** and a **programmatic API**. NOT a bookmarklet or native app -- it's a standard WebExtension (Manifest V3 for Chrome, V2-compat for Firefox, Safari App Extension wrapper via Xcode).

**Three distribution surfaces:**
- Browser extension (popup, side panel, embedded iframe, context menu)
- CLI (`obsidian-clipper <url> --template <path>`) -- uses `linkedom` for server-side DOM parsing
- Programmatic API (`import { clip } from 'obsidian-clipper/api'`) -- environment-agnostic

---

## 2. End-to-End Architecture

### Extension Components

```
┌─────────────────────┐   ┌──────────────────┐   ┌───────────────────┐
│   Content Script     │   │  Background Script│   │  Popup / Side     │
│   (content.ts)       │◄──│  (background.ts)  │──►│  Panel / Settings │
│                      │   │                   │   │  (popup.ts, etc.) │
│ - Injects into page  │   │ - Service worker  │   │                   │
│ - Runs Defuddle      │   │ - Message routing  │   │ - Template UI     │
│ - Extracts content   │   │ - Context menus   │   │ - Save to Obsidian│
│ - Manages highlights │   │ - Tab management  │   │ - Interpreter UI  │
│ - Flattens shadow DOM│   │ - Script injection│   │                   │
└─────────────────────┘   └──────────────────┘   └───────────────────┘
```

### Data Flow (clip a page):

1. User clicks extension icon or presses `Cmd+Shift+O`
2. Background script ensures content script is injected
3. Content script runs **Defuddle** (their own library) on the page DOM
   - Defuddle extracts: title, author, content HTML, description, published date, site, language, word count, favicon, image, schema.org data, meta tags
   - Also calls `parseAsync()` for async variables like `{{transcript}}` (YouTube)
4. Content script also captures: `window.getSelection()` for selected HTML, stored highlights, full cleaned HTML
5. All data sent back to popup via `browser.runtime.sendMessage`
6. Popup runs **template compilation** -- variables + filters produce final markdown
7. Content HTML is converted to markdown via `createMarkdownContent()` from `defuddle/full`
8. Result sent to Obsidian via URI scheme

---

## 3. HTML-to-Markdown Conversion

**Library: [Defuddle](https://github.com/nicholasgasior/defuddle)** -- Obsidian's own content extraction library (similar to Readability/Mercury but their own).

Two main functions:
- `new Defuddle(document, { url }).parse()` -- extracts article content, metadata, schema.org data
- `createMarkdownContent(html, url)` -- converts extracted HTML to markdown (from `defuddle/full`)

The content script also flattens Shadow DOM elements before extraction (`flatten-shadow-dom.ts`), handles relative-to-absolute URL conversion, strips scripts/styles, and removes style attributes.

---

## 4. What Formats It Can Clip

- **Full page article** -- via Defuddle content extraction (`{{content}}`)
- **Selection** -- captures `window.getSelection()` range as HTML, converts to markdown (`{{selection}}`)
- **Highlights** -- multiple highlighted passages on a page (`{{highlights}}`)
- **Full raw HTML** -- the entire page HTML, cleaned of scripts/styles (`{{fullHtml}}`)
- **CSS selector extraction** -- arbitrary content via `{{selector:CSS_SELECTOR}}` or `{{selectorHtml:CSS_SELECTOR}}`
- **Schema.org data** -- structured data from JSON-LD/microdata (`{{schema:@Article.author}}`)
- **Meta tags** -- any meta tag value (`{{meta:name:description}}`, `{{meta:property:og:image}}`)
- **YouTube transcripts** -- via Defuddle's async `parseAsync()` which populates `{{transcript}}`
- **Any site-specific data** -- via Defuddle's `variables` system (extracted content keyed by name)

---

## 5. Highlights System

### How It Works

**highlighter.ts** (1078 lines) is a full in-page highlighting system:

1. **Activation:** Toggle via keyboard shortcut (`Alt+Shift+H`), context menu, or button
2. **Modes:**
   - **Text selection highlight** -- select text, it gets highlighted
   - **Element highlight** -- right-click images/video/audio to add to highlights
   - **Click-based highlighting** in highlighter mode
3. **Storage:** Highlights are stored per-URL in `browser.storage.local` as an array of `AnyHighlightData`
4. **Data structure:**
   ```typescript
   interface TextHighlightData {
     type: 'text';
     id: string;        // timestamp-based
     xpath: string;     // XPath to the element
     content: string;   // HTML content of highlight
     startOffset: number;
     endOffset: number;
     notes?: string[];  // User annotations
   }
   ```
5. **Persistence:** Highlights survive page reloads -- they're stored by URL and re-applied on page load via XPath matching
6. **Rendering in clipped note:**
   - `highlight-inline` -- wraps highlighted text in `<mark>` tags within the article content, which Defuddle converts to `==highlighted==` markdown
   - `replace-content` -- replaces the entire article content with just the highlights
   - `no-highlights` -- ignore highlights

### Highlight Behaviors (in content-extractor.ts):
- **highlight-inline**: Injects `<mark>` wrappers into the extracted HTML before markdown conversion
- **replace-content**: Concatenates all highlight HTML fragments, replacing article body
- **no-highlights**: Returns original content unmodified

---

## 6. Communication with Obsidian

### Primary Method: URI Scheme

```typescript
// obsidian-note-creator.ts
obsidianUrl = `obsidian://new?file=${encodeURIComponent(path + formattedNoteName)}`;
```

**URI parameters:**
- `obsidian://new?file=...` -- create new note
- `obsidian://daily?` -- append/prepend to daily note
- `&append=true` / `&prepend=true` / `&overwrite=true`
- `&vault=VaultName`
- `&silent=true` -- don't focus Obsidian
- `&clipboard` -- tells Obsidian to read content from clipboard (preferred)
- `&content=...` -- fallback: content in URL (legacy mode, limited by URL length)

**Two transmission modes:**
1. **Clipboard mode (default):** Copy markdown to clipboard, then open URI with `&clipboard` flag. Obsidian reads from clipboard.
2. **Legacy mode:** Encode full content in the URI itself. Falls back to this if clipboard write fails.

**CLI also supports:**
- Direct file write (`--output path.md`)
- Obsidian CLI integration (`openInObsidian()` in cli-utils.ts)
- URI scheme (`--uri` flag)
- stdout (default)

---

## 7. Template System

### Template Structure

```typescript
interface Template {
  id: string;
  name: string;
  behavior: 'create' | 'append-specific' | 'append-daily' | 'prepend-specific' | 'prepend-daily' | 'overwrite';
  noteNameFormat: string;        // e.g. "{{title}}"
  path: string;                  // vault path, e.g. "Clippings/"
  noteContentFormat: string;     // the body template with {{variables}}
  properties: Property[];        // YAML frontmatter properties
  triggers?: string[];           // URL patterns for auto-matching
  vault?: string;                // target vault
  context?: string;              // LLM prompt context
}
```

### Variable Types

1. **Simple variables:** `{{title}}`, `{{author}}`, `{{content}}`, `{{url}}`, `{{date}}`, `{{published}}`, `{{description}}`, `{{domain}}`, `{{favicon}}`, `{{image}}`, `{{site}}`, `{{language}}`, `{{words}}`, `{{selection}}`, `{{highlights}}`, `{{fullHtml}}`, `{{noteName}}`
2. **CSS selectors:** `{{selector:h1.title}}`, `{{selectorHtml:div.content}}`, `{{selector:img.hero?src}}`
3. **Schema.org:** `{{schema:@Article.author}}`, `{{schema:@VideoObject.duration}}`
4. **Meta tags:** `{{meta:name:description}}`, `{{meta:property:og:image}}`
5. **Prompt variables (LLM):** `{{prompt:"Summarize this article in 3 bullets"}}` or `{{"Generate tags for this content"}}`
6. **Defuddle async variables:** `{{transcript}}` for YouTube

### Filter System (50+ filters)

Variables support pipe-delimited filters: `{{title|lower|trim|safe_name}}`

Available filters include:
- **String:** `lower`, `upper`, `capitalize`, `title`, `trim`, `camel`, `kebab`, `snake`, `pascal`, `uncamel`
- **Date:** `date:"YYYY-MM-DD"`, `date_modify:"+1 day"`
- **HTML/Markdown:** `markdown`, `strip_md`, `strip_tags`, `strip_attr`, `remove_html`, `remove_tags`, `remove_attr`, `replace_tags`, `unescape`
- **Arrays:** `split`, `join`, `first`, `last`, `nth`, `slice`, `reverse`, `unique`, `merge`, `map`, `length`
- **Formatting:** `blockquote`, `callout`, `footnote`, `fragment_link`, `image`, `link`, `list`, `table`, `wikilink`, `template`
- **Math:** `calc`, `round`, `number_format`
- **Other:** `replace`, `safe_name`, `decode_uri`, `html_to_json`, `object`, `duration`

### Template Compilation Pipeline

1. **AST-based renderer** (`renderer.ts`) parses template into AST, resolves variables
2. **Async resolver** handles `selector:` and `selectorHtml:` variables (requires DOM queries)
3. **Post-processing** handles remaining `selector:`, `schema:`, and `prompt:` variables
4. **Filter application** -- each filter is a pure function that transforms the value

### Template Triggers (Auto-Matching)

Templates can be auto-selected based on:
- **URL prefix:** `https://twitter.com/` matches any Twitter URL
- **Regex:** `/youtube\.com\/watch/` matches YouTube video pages
- **Schema.org type:** `schema:@Article`, `schema:@VideoObject.duration`, `schema:@Recipe.recipeCategory=Dessert`

Implementation uses a **Trie** for URL prefix matching (fast), regex array for patterns, and lazy schema.org evaluation (only fetched if schema triggers exist).

---

## 8. Interpreter (AI/LLM Integration)

Templates can include `{{prompt:"..."}}` variables. When present:

1. The "Interpreter" UI appears in the popup with a model selector
2. All prompt variables are collected from the template
3. Page content is sent as context to the selected LLM
4. Response JSON is parsed and prompt variables are replaced with LLM responses

**Supported providers** (from providers.json):
- Anthropic (Claude models)
- OpenAI (GPT models)
- Google Gemini
- DeepSeek
- Ollama (local)
- OpenRouter
- Perplexity
- xAI (Grok)
- Azure OpenAI
- Hugging Face
- Meta (Llama)

Each provider has different API formatting in `interpreter.ts`. API keys stored in browser sync storage.

---

## 9. Metadata Extraction

All powered by **Defuddle** which extracts:
- `title` -- from `<title>`, `og:title`, schema.org, etc.
- `author` -- from meta tags, schema.org, byline detection
- `description` -- from meta description, `og:description`
- `published` -- from `article:published_time`, schema.org dates
- `site` -- from `og:site_name`, schema.org
- `image` -- from `og:image`, schema.org
- `favicon` -- from link[rel=icon]
- `language` -- from `<html lang>`
- `wordCount` -- computed from extracted content
- `schemaOrgData` -- full JSON-LD and microdata extraction
- `metaTags` -- all meta name/property/content triples
- `variables` -- async variables like transcript

---

## 10. Special Site Handling

### YouTube
- **Defuddle** has async variable support: `parseAsync()` extracts `{{transcript}}` variable
- Background script rewrites `Referer` header on YouTube embeds to `https://obsidian.md/` so embedded players work in the reader mode
- Chrome uses `declarativeNetRequest`, Firefox uses `webRequest.onBeforeSendHeaders`
- Safari shows thumbnail fallback instead (can't modify headers)

### Reader Mode
- Full reader mode implementation (`reader.ts`, `reader-script.ts`, `reader.scss`)
- Configurable: font size, line height, max width, theme (default/flexoki), theme mode (auto/light/dark)
- Can be toggled via `Alt+Shift+R` or context menu

### General
- Template triggers support URL-prefix matching, so users can create custom templates for any site (Twitter, Reddit, etc.)
- Schema.org trigger matching enables content-type-based templates (e.g., match all Recipe pages regardless of domain)
- **No hardcoded site-specific extractors** -- all customization is via the template + trigger system

---

## 11. Image and Media Handling

- **Images:** Preserved as markdown `![alt](url)` during HTML-to-markdown conversion
- **Image highlights:** Can highlight images on page via right-click context menu, stored with XPath
- **Image URLs:** Relative URLs converted to absolute during content extraction
- **Local image saving:** Added in Obsidian 1.8.0 (Obsidian-side feature, not clipper-side)
- **srcset handling:** Properly converts relative srcset URLs to absolute
- **Video/Audio:** Can be highlighted as elements; YouTube embeds get special Referer handling

---

## 12. Configuration / Settings System

**Storage:** `browser.storage.sync` for settings (synced across devices), `browser.storage.local` for highlights and history.

### Settings Structure

```typescript
interface Settings {
  vaults: string[];                    // Obsidian vault names
  legacyMode: boolean;                 // URI content vs clipboard mode
  silentOpen: boolean;                 // Don't focus Obsidian
  openBehavior: 'popup' | 'embedded'; // How clipper opens
  highlighterEnabled: boolean;
  alwaysShowHighlights: boolean;
  highlightBehavior: 'highlight-inline' | 'replace-content' | 'no-highlights';
  interpreterEnabled: boolean;
  interpreterAutoRun: boolean;
  interpreterModel: string;
  models: ModelConfig[];               // LLM model configurations
  providers: Provider[];               // LLM provider configs + API keys
  defaultPromptContext: string;        // Default LLM context
  propertyTypes: PropertyType[];       // YAML property type definitions
  readerSettings: ReaderSettings;      // Reader mode config
  saveBehavior: 'addToObsidian' | 'saveFile' | 'copyToClipboard';
  stats: { addToObsidian, saveFile, copyToClipboard, share };
  history: HistoryEntry[];
}
```

### Templates stored separately in browser storage, managed by `template-manager.ts`

- Import/export as JSON
- Auto-save with 1s debounce
- Property type enforcement (text, multitext, number, checkbox, date, datetime)
- Template validation and reordering via drag-and-drop

---

## 13. Tech Stack

- **Language:** TypeScript (82.6%)
- **Build:** Webpack with separate configs for Chrome/Firefox/Safari
- **Testing:** Vitest
- **Key dependencies:**
  - `defuddle` -- content extraction and HTML-to-markdown
  - `dompurify` -- HTML sanitization
  - `dayjs` -- date formatting
  - `highlight.js` -- syntax highlighting
  - `linkedom` -- server-side DOM (for CLI)
  - `lucide` -- icons
  - `lz-string` -- compression
  - `webextension-polyfill` -- cross-browser API compatibility
- **Browser APIs:** `chrome.sidePanel`, `chrome.declarativeNetRequest`, `browser.scripting`, `browser.contextMenus`, `browser.storage.sync/local`, `browser.commands`
- **Safari:** Xcode project wrapper in `xcode/Obsidian Web Clipper/`

---

## 14. Keyboard Shortcuts

- `Cmd+Shift+O` -- Open clipper
- `Alt+Shift+O` -- Quick clip (opens popup and auto-saves)
- `Alt+Shift+H` -- Toggle highlighter
- `Alt+Shift+R` -- Toggle reader mode

---

## 15. Limitations and Known Issues

From the README roadmap (not yet implemented):
- Annotate highlights (highlights exist, but annotation is TODO)
- Template directory (community template sharing)
- Template validation
- Template logic (if/for control flow)
- More language translations

From the code:
- **URL length limits** in legacy mode (content encoded in URI)
- **Safari can't modify request headers** -- YouTube embed Referer workaround doesn't work, falls back to thumbnail
- **Content script re-injection** needed after extension updates (handled with runtime check guard)
- **1-minute rate limit** between LLM interpreter requests
- **Clipboard mode** can fail on some browsers/contexts, falls back to URI mode
- **Shadow DOM** requires explicit flattening before content extraction
- **No offline page saving** -- only saves the markdown, not the original page assets
- **193 open issues** on GitHub as of exploration date
