# Defuddle Research Summary

**Repository:** https://github.com/kepano/defuddle
**Version:** 0.14.0 (as of Mar 17, 2026)
**License:** MIT
**Stars:** 5.5k | **Used by:** 107 projects
**Author:** kepano (creator of Obsidian Web Clipper)

---

## 1. What Is Defuddle?

Defuddle is **both** a readability parser and an HTML-to-Markdown converter. Its primary purpose is to extract the main content from web pages -- removing clutter like ads, navigation, sidebars, comments, headers, footers -- and return either clean HTML or Markdown.

It was created for the **Obsidian Web Clipper** browser extension but is designed to run in any environment (browser, Node.js, Cloudflare Workers, CLI).

**Self-description from the README:**
> "de-fud-dle /di'fAdl/ transitive verb -- to remove unnecessary elements from a web page, and make it easily readable."

---

## 2. Full Architecture -- The Processing Pipeline

The pipeline runs in `src/defuddle.ts` via `parseInternal()`. Here is the exact order:

### Phase 0: Pre-processing (on original document)
1. **Extract schema.org data** -- Cached. Must happen before script tags are removed.
2. **Collect meta tags** -- Cached across retries.
3. **Extract metadata** (via `MetadataExtractor`) -- title, author, date, description, domain, etc.
4. **Check for site-specific extractor** -- If found (e.g., Twitter, YouTube, Reddit), uses that instead of the generic pipeline and returns early.

### Phase 1: Document Preparation (on clone)
5. **Clone the document** -- All subsequent DOM mutations happen on the clone.
6. **Normalize text nodes** -- `clone.body.normalize()` merges adjacent text nodes.
7. **Flatten shadow DOM** -- `flattenShadowRoots()` -- copies shadow DOM content into the light DOM.
8. **Resolve React streaming SSR** -- `resolveStreamedContent()` -- handles Suspense boundary fallbacks.
9. **Evaluate mobile CSS media queries** -- Finds `max-width` media queries and applies mobile styles to the clone. Uses a 600px mobile width threshold to detect elements hidden on mobile (likely non-content).
10. **Find small images** -- Cached. Identifies icons, tracking pixels, etc.

### Phase 2: Content Identification
11. **Find main content element** -- Either via `contentSelector` option or auto-detection using `ENTRY_POINT_ELEMENTS` priority list + `ContentScorer.scoreElement()`.
12. **Schema.org fallback** -- If main content resolved to `<body>`, tries to find a more specific element matching schema.org `articleBody`/`text`.

### Phase 3: Content Standardization (before removals)
13. **Standardize footnotes** (`standardizeFootnotes`) -- Runs BEFORE hidden element removal because CSS sidenotes use `display:none`.
14. **Standardize callouts** (`standardizeCallouts`) -- Converts GitHub alerts, Bootstrap alerts, callout asides to `blockquote[data-callout]` BEFORE selector removal strips `.alert` etc.

### Phase 4: Clutter Removal (the core of defuddling)
15. **Remove small images** -- Icons, tracking pixels.
16. **Remove hidden elements** -- `display:none`, `visibility:hidden`, `[hidden]`, `aria-hidden="true"`, `.hidden`, `.invisible`.
17. **Remove by selector** -- Two stages:
    - **Exact selectors** (~150 CSS selectors): `header`, `footer`, `nav`, `.sidebar`, `.ad`, `.comments`, etc.
    - **Partial selectors** (~350 patterns): substring matches against `class`, `id`, `data-test`, `data-testid`, etc. Patterns like `'breadcrumb'`, `'newsletter'`, `'related'`, `'trending'`, etc.
    - Elements inside `<pre>` or `<code>` are **protected** from selector removal.
18. **Remove by content scoring** (`ContentScorer.scoreAndRemove`) -- Heuristic scoring based on:
    - Navigation indicator keywords (advertisement, follow us, newsletter, etc.)
    - Link density (high = navigation)
    - Link text ratio
    - Social media profile links
    - Byline + date patterns
    - Article card grid detection (3+ headings + 2+ images with low prose)
    - Non-content class patterns
19. **Remove by content patterns** -- Read time strings, boilerplate text, article card listings.

### Phase 5: Post-Processing
20. **Standardize HTML** (`standardizeContent`) -- heading normalization, code block cleanup, math element standardization, attribute cleanup, empty element removal, div flattening.
21. **Resolve relative URLs** to absolute.
22. **Return result** with content + metadata.

### Phase 6: Retry Logic
The `parse()` method wraps `parseInternal()` with up to 4 retry strategies:
- **Retry 1:** If `wordCount < 200`, retry without partial selectors (they may have been too aggressive).
- **Retry 2:** If `wordCount < 50`, retry without hidden element removal (content may be in hidden wrappers).
- **Retry 3:** Try targeting the largest hidden subtree directly.
- **Retry 4:** Retry without scoring, partial selectors, AND content patterns (for index/listing pages).
- **Schema.org fallback:** If schema.org has longer text than extracted content, finds the matching DOM element.

---

## 3. Main Content Extraction

### Entry Point Elements (priority order)
```typescript
const ENTRY_POINT_ELEMENTS = [
    '#post', '.post-content', '.post-body',
    '.article-content', '#article-content', '.article_post',
    '.article-wrapper', '.entry-content', '.content-article',
    '.instapaper_body', '.post', '.markdown-body',
    'article', '[role="article"]',
    'main', '[role="main"]',
    '#content',
    'body'  // fallback -- always matches
];
```

### Scoring Algorithm (`ContentScorer.scoreElement`)
Each candidate gets a score based on:
- **Word count** (direct addition)
- **Paragraph count** (x10 bonus per `<p>`)
- **Comma count** (prose indicator)
- **Image density** (penalized)
- **Content classes** (bonus for `content`, `article`, `post`)
- **Footnotes presence** (bonus)
- **Link density** (multiplier: `score *= (1 - linkDensity)`, capped at 0.5)
- **Nested tables** (penalized)
- **Table cell position** (center cells in layout tables get bonus)

The best-scoring element wins. There is also logic to prefer the most specific (deepest) child element when a parent and child both match entry point selectors.

### Table-Based Layout Detection
For old-style websites using `<table>` for layout, it detects layout tables (width > 400, centered, content-class) and scores `<td>` cells to find the main content cell.

---

## 4. Element Handling

### Code Blocks (`src/elements/code.ts`, `src/standardize.ts`)
- Line numbers and syntax highlighting spans are stripped
- Language is preserved as `data-lang` attribute and `class="language-{lang}"`
- GitHub's highlighted code blocks (`div.highlight pre` with spans) are converted to standard `<pre><code>`

### Footnotes (`src/elements/footnotes.ts`)
- Extensive selectors for inline references and footnote lists from many formats
- Standardized to: `<sup id="fnref:N"><a href="#fn:N">N</a></sup>` for references
- Footnote lists standardized to: `<li class="footnote" id="fn:N">` with backlink

### Math (`src/elements/math.base.ts`, `math.core.ts`, `math.full.ts`)
- MathJax, KaTeX, and MathML all converted to standard `<math>` elements
- Core bundle: handles existing MathML, reads `data-latex`/`alttext` attributes
- Full bundle: adds `mathml-to-latex` and `temml` libraries for cross-format conversion
- In Markdown: inline `$latex$` and block `$$\nlatex\n$$`

### Callouts (`src/elements/callouts.ts`)
- GitHub markdown alerts (`div.markdown-alert`)
- Obsidian Publish callouts (`div.callout[data-callout]`)
- Callout asides (`aside.callout-*`)
- Bootstrap alerts (`div.alert.alert-*`)
- All standardized to `div[data-callout]` format
- In Markdown: `> [!type] Title\n> content`

### Headings (`src/elements/headings.ts`)
- First H1/H2 removed if it matches the extracted title
- All H1s converted to H2s
- Anchor links in headings removed (become plain headings)

### Images (`src/elements/images.ts`)
- Small images removed (icons, tracking pixels)
- `srcset` parsed intelligently -- handles CDN URLs with commas (e.g., Substack)
- Best/largest image selected from srcset
- `<figure>` with `<figcaption>` handled as a unit

### Tables (in `src/markdown.ts`)
- Simple tables: converted to Markdown pipe tables
- Complex tables (colspan/rowspan): kept as HTML
- Layout tables (single column, nested): extracted as content, not table markup
- ArXiv equation tables: handled specially

### Lists (in `src/markdown.ts`)
- Tab-based indentation for nested lists
- Ordered list start numbers preserved
- Task list items (`[x]` / `[ ]`) supported

### Embeds (in `src/markdown.ts`)
- YouTube iframes converted to `![](https://www.youtube.com/watch?v=ID)` (Obsidian embed format)
- Twitter/X iframes converted to `![](https://x.com/user/status/ID)`
- Other iframes, video, audio, SVG, math elements kept as-is

---

## 5. Site-Specific Extractors

Registered in `src/extractor-registry.ts`. Each extends `BaseExtractor` with `canExtract()` and `extract()` methods.

| Extractor | URL Patterns | Key Behavior |
|-----------|-------------|--------------|
| **XArticleExtractor** | x.com, twitter.com | X/Twitter long-form articles (not tweets) |
| **TwitterExtractor** | twitter.com, x.com | Tweet threads. Extracts main tweet + thread. Handles emoji images, quoted tweets, media. |
| **XOembedExtractor** | x.com, twitter.com | oEmbed fallback for X/Twitter |
| **RedditExtractor** | reddit.com (all variants) | Shreddit (new) + old.reddit.com. Falls back to fetching old.reddit.com for comment pages. Extracts post + comment trees with depth. |
| **YoutubeExtractor** | youtube.com, youtu.be | 992 lines. Extracts video description, chapters, transcript (from inline data or YouTube API). `prefersAsync()` = true (transcripts are better async). Supports language selection. |
| **HackerNewsExtractor** | news.ycombinator.com | Extracts post + comment tree |
| **ChatGPTExtractor** | chatgpt.com | Conversation extraction |
| **ClaudeExtractor** | claude.ai | Conversation extraction |
| **GrokExtractor** | grok.com | Conversation extraction |
| **GeminiExtractor** | gemini.google.com | Conversation extraction |
| **GitHubExtractor** | github.com | Issues and PRs. Extracts body, author, comments with threading. Handles both new and old UI. |
| **BbcodeDataExtractor** | `/.*/` (catch-all) | Extracts BBCode data from any page |

### Extractor Architecture
- `BaseExtractor`: abstract class with `canExtract()`, `extract()`, `canExtractAsync()`, `extractAsync()`, `prefersAsync()`
- `_conversation.ts`: base class for AI chat extractors (ChatGPT, Claude, Grok, Gemini)
- Extractors return `ExtractorResult` with `content`, `contentHtml`, `extractedContent`, and `variables` that override metadata

### Async Extractors
- Used when sync extraction yields no content (e.g., client-side rendered SPAs)
- **FxTwitter API**: fetches X/Twitter content not available in server-rendered HTML
- **YouTube transcripts**: fetched async for better results
- **Reddit**: falls back to fetching `old.reddit.com` when shreddit comments aren't in server HTML
- Can be disabled with `useAsync: false`

---

## 6. API

### Browser (Core Bundle)
```typescript
import Defuddle from 'defuddle';
const result = new Defuddle(document, options).parse();
// result.content -- cleaned HTML string
// result.title, result.author, result.published, etc.
```

### Browser (Full Bundle)
```typescript
import Defuddle from 'defuddle/full';
// Same API, adds math (mathml-to-latex, temml) and Markdown (turndown)
```

### Node.js
```typescript
import { Defuddle } from 'defuddle/node';
const result = await Defuddle(document, 'https://example.com', { markdown: true });
// Accepts any DOM Document (linkedom, JSDOM, happy-dom)
// Always async
```

### CLI
```bash
npx defuddle parse <url-or-file> [--markdown] [--json] [--property <name>] [--output <file>] [--debug] [--lang <code>]
```

### Cloudflare Worker (defuddle.md)
```bash
curl https://defuddle.md/https://example.com/article
```

### Options
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `debug` | boolean | false | Debug logging + debug info in response |
| `url` | string | - | Page URL |
| `markdown` | boolean | false | Convert content to Markdown |
| `separateMarkdown` | boolean | false | Keep HTML content + add `contentMarkdown` |
| `removeExactSelectors` | boolean | true | Remove ads, social buttons, etc. |
| `removePartialSelectors` | boolean | true | Remove by partial class/id match |
| `removeHiddenElements` | boolean | true | Remove display:none, etc. |
| `removeLowScoring` | boolean | true | Remove by content scoring |
| `removeSmallImages` | boolean | true | Remove icons, tracking pixels |
| `removeImages` | boolean | false | Remove ALL images |
| `standardize` | boolean | true | Normalize HTML (footnotes, headings, code) |
| `contentSelector` | string | - | CSS selector to bypass auto-detection |
| `useAsync` | boolean | true | Allow async API fallbacks |
| `language` | string | - | BCP 47 language preference |
| `includeReplies` | boolean/'extractors' | 'extractors' | Include replies/comments |

### Response Object
| Property | Type | Description |
|----------|------|-------------|
| `content` | string | Cleaned HTML (or Markdown if `markdown: true`) |
| `contentMarkdown` | string | Markdown version (if `separateMarkdown: true`) |
| `title` | string | Article title |
| `author` | string | Author name(s) |
| `description` | string | Summary/description |
| `domain` | string | Domain name |
| `favicon` | string | Favicon URL |
| `image` | string | Main image URL |
| `language` | string | BCP 47 language code |
| `published` | string | Publication date |
| `site` | string | Website name |
| `schemaOrgData` | object | Raw schema.org JSON-LD data |
| `metaTags` | object | All meta tags |
| `parseTime` | number | Milliseconds to parse |
| `wordCount` | number | Words in extracted content |
| `debug` | object | Debug info (when debug: true) |
| `variables` | object | Extractor-specific variables |

---

## 7. Comparison to Mozilla Readability.js

From the README and code analysis:

| Aspect | Defuddle | Readability.js |
|--------|----------|----------------|
| **Approach** | More forgiving, removes fewer uncertain elements | More aggressive removal |
| **Mobile CSS** | Uses mobile styles to guess non-content elements | No mobile CSS analysis |
| **Metadata** | Extensive: schema.org, meta tags, DOM heuristics, byline detection near headings | Basic metadata |
| **Footnotes** | Standardized to consistent format | Not standardized |
| **Math** | MathJax/KaTeX/MathML all standardized | Not handled |
| **Code blocks** | Cleaned, language preserved | Not standardized |
| **Callouts** | GitHub alerts, Bootstrap, Obsidian -> standardized | Not handled |
| **Site-specific** | 13 extractors (Twitter, YouTube, Reddit, GitHub, ChatGPT, Claude, etc.) | None |
| **Markdown** | Built-in conversion via Turndown with custom rules | Not included |
| **Retry logic** | 4 retry strategies with different settings | Single pass |
| **Shadow DOM** | Flattened | Not handled |
| **React SSR** | Streaming boundaries resolved | Not handled |
| **Async** | API fallbacks for SPAs (FxTwitter, old.reddit) | Sync only |
| **Output** | HTML or Markdown + full metadata | HTML + basic metadata |

---

## 8. Tech Stack

- **Language:** TypeScript
- **Build:** Webpack (browser bundles) + tsc (Node.js bundle, type declarations)
- **Testing:** Vitest with fixtures in `tests/fixtures/` + expected output in `tests/expected/`
- **DOM:** Native DOM in browser; linkedom/JSDOM/happy-dom in Node.js
- **Markdown:** Turndown.js (optional dependency)
- **Math:** mathml-to-latex + temml (optional, full bundle only)
- **CLI:** Commander.js
- **Only hard dependency:** `commander` (for CLI)
- **Optional dependencies:** `linkedom`, `mathml-to-latex`, `temml`, `turndown`
- **Browser-compatible:** Yes, core bundle has zero dependencies
- **Node.js-compatible:** Yes, via `defuddle/node` with DOM implementation
- **Cloudflare Worker:** Yes, via linkedom (most constrained DOM)

---

## 9. Metadata Extraction (`src/metadata.ts`)

Metadata is extracted with a cascading priority system:

### Title
1. `og:title` meta tag
2. `twitter:title` meta tag
3. Schema.org `headline`
4. `title` meta tag
5. `sailthru.title` meta tag
6. `<title>` element
7. **Cleaning:** strips site name from title (e.g., "Article | Site Name" -> "Article"), handles fuzzy matching and breadcrumb stripping

### Author
1. Meta tags: `sailthru.author`, `property:author`, `name:author`, `name:byl`, `name:authorList`
2. Research paper meta: `citation_author`, `dc.creator` (handles "Last, First" -> "First Last")
3. Schema.org: `author.name`, `author.[].name`
4. DOM elements: `[itemprop="author"]`, `.author`, `[href*="/author/"]`, `.authors a` (with max match limits to avoid false positives)
5. **Byline near H1:** checks siblings for "By Name" patterns and date-adjacent author names

### Published Date
1. Schema.org `datePublished`
2. Meta tags: `publishDate`, `article:published_time`, `sailthru.date`
3. `<abbr itemprop="datePublished">`
4. `<time>` elements
5. **Date text near H1:** parses "February 26, 2025" etc. from siblings

### Other Metadata
- **Description:** meta description, og:description, schema.org description, twitter:description
- **Image:** og:image, twitter:image, schema.org image.url
- **Language:** html lang, Content-Language meta, og:locale, schema.org inLanguage (normalized to BCP 47)
- **Favicon:** og:image:favicon, `link[rel="icon"]`, `link[rel="shortcut icon"]`, fallback to `/favicon.ico`
- **Site name:** schema.org publisher.name, og:site_name, WebSite.name, application-name (rejected if > 6 words)
- **Schema.org data:** full JSON-LD extraction with `@graph` traversal

---

## 10. Obsidian-Specific Features

Defuddle was built for Obsidian Web Clipper. Obsidian-specific features:

- **Callout format:** standardized to Obsidian's `> [!type] Title` syntax
- **YouTube embeds:** `![](https://www.youtube.com/watch?v=ID)` -- Obsidian's media embed format
- **Twitter embeds:** `![](https://x.com/user/status/ID)` -- Obsidian's embed format
- **Highlight marks:** `<mark>` -> `==highlighted==`
- **Strikethrough:** `<del>/<s>/<strike>` -> `~~strikethrough~~`
- **Task lists:** `[x]` and `[ ]` checkbox syntax
- **Footnotes:** `[^N]` and `[^N]: content` format
- **The `variables` field** in extractor results allows Obsidian Web Clipper to populate templates

---

## 11. Output Format Options

### HTML (default)
Clean, standardized HTML with:
- Non-allowed attributes stripped (only keeps href, src, alt, data-lang, data-callout, etc.)
- Dangerous URLs sanitized (javascript:, data:text/html)
- Event handlers removed
- Empty divs flattened
- Relative URLs resolved to absolute

### Markdown (`markdown: true`)
Uses Turndown.js with extensive custom rules:
- ATX headings (`##`)
- Fenced code blocks with language
- Tables (pipe format for simple, HTML for complex)
- Lists with tab indentation
- Math: `$inline$` and `$$\nblock\n$$`
- Callouts: `> [!type] Title`
- Footnotes: `[^N]` / `[^N]: content`
- Highlights: `==text==`
- Strikethrough: `~~text~~`
- Figures: `![alt](src)\n\ncaption`
- Images: best resolution from srcset

### Separate Markdown (`separateMarkdown: true`)
Returns both `content` (HTML) and `contentMarkdown` (Markdown).

### No frontmatter
Defuddle does not generate YAML frontmatter. The metadata is returned as separate fields in the response object. The consuming application (e.g., Obsidian Web Clipper) is responsible for formatting frontmatter if needed.

---

## 12. Performance Characteristics

- **parseTime** is returned in the response (milliseconds)
- **Caching:** schema.org data, meta tags, metadata, mobile styles, and small images are all cached across retries
- **Single DOM clone** per parseInternal call
- **Pre-compiled regexes** for partial selectors (`PARTIAL_SELECTORS_REGEX`), navigation indicators, date patterns
- **Pre-joined selector strings** for exact selectors
- **Batch removal** in scoring -- collects all elements to remove, then removes in single pass
- **Static arrays from live collections** -- `Array.from(getElementsByTagName())` before DOM mutation
- **No external HTTP requests** during sync parse (only async extractors make requests)

---

## 13. Edge Cases

### Paywalled Content
- No special paywall bypassing
- FT.com barrier page explicitly removed via `#barrier-page` selector
- Paywall message selectors: `paywall_message`, `mod-paywall`, `gated-`
- Access wall patterns removed

### SPAs / Dynamic Content
- **React streaming SSR:** Suspense boundaries resolved (`resolveStreamedContent`)
- **Shadow DOM:** flattened into light DOM
- **Async fallback:** if sync parse yields no content, async extractors try external APIs
- **Twitter/X:** server-rendered HTML has no content; FxTwitter API used as fallback
- **Reddit:** shreddit comments not in server HTML; falls back to fetching old.reddit.com

### Iframes
- YouTube, Vimeo, Twitter, Datawrapper iframes preserved
- All other iframes removed
- `srcdoc` attribute always stripped (security)
- `javascript:` URLs in iframe src stripped

### Security
- `parseHTML()` uses `<template>` elements (no script execution, no resource loading)
- `javascript:` and `data:text/html` stripped from href/src
- `on*` event handlers removed
- `srcdoc` stripped from iframes
- Scripts removed (except `type="math/"`)

### Hidden Content
- Retry logic specifically handles pages that hide content in wrappers
- `findLargestHiddenContentSelector()` finds the biggest hidden subtree
- CSS sidenote footnotes (using `display:none`) are standardized BEFORE hidden element removal

### Old-Style Table Layouts
- Detected via table width, centering, or content classes
- Content cell found by scoring all `<td>` elements

---

## Source Files Map

| File | Lines | Purpose |
|------|-------|---------|
| `src/defuddle.ts` | 1292 | Core parsing pipeline, retry logic, content finding |
| `src/standardize.ts` | 1268 | HTML normalization (headings, code, attributes, divs) |
| `src/constants.ts` | 1005 | Selectors, patterns, element lists |
| `src/markdown.ts` | 782 | Turndown rules for HTML-to-Markdown |
| `src/metadata.ts` | 566 | Metadata extraction (title, author, date, etc.) |
| `src/removals/scoring.ts` | 542 | Content scoring algorithm |
| `src/extractors/youtube.ts` | 992 | YouTube extractor (transcripts, chapters) |
| `src/extractors/twitter.ts` | 238 | Twitter/X thread extractor |
| `src/extractors/github.ts` | 293 | GitHub issues/PRs extractor |
| `src/extractors/reddit.ts` | 232 | Reddit post + comment extractor |
| `src/extractor-registry.ts` | 175 | Extractor URL matching |
| `src/extractors/_base.ts` | 40 | Base extractor class |
| `src/node.ts` | 48 | Node.js entry point |
| `src/index.full.ts` | 40 | Full bundle entry point |
| `src/types.ts` | 155 | TypeScript type definitions |
