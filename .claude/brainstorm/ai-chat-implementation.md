# AI Chat — Implementation Architecture

Status: architecture decision (pre-build). Date: 2026-06-07.
Companion to the UI concept: `ai-chat-ui-concept.md`.

## The core reframe

"Chat with my notes" is not *prompt → answer*. It's an **agentic tool-use loop**: the model
decides when to `grep` and `read` the vault, gathers just the relevant files, then answers and
cites them. This is exactly what Claude Code does over a codebase — we're doing it over a vault of
markdown.

The three asks map directly to **tools the model can call**:
1. grep any file  → `grep(query)` tool
2. read any file  → `read(path)` tool
3. generate response → the model, run in a loop around those tools

## Decision: where does the model run? → Cloud via **OpenRouter** (cheaper models), not on-device

| Option | Verdict |
|---|---|
| **Apple Foundation Models** (on-device, iOS/macOS 26) | ✗ as primary. Gated to Apple-Intelligence hardware — your exact blocker. Also weaker at multi-step tool use. |
| **Local open model** (MLX / llama.cpp, e.g. Llama 3.2 3B) | ✗ as primary. GB-sized download, slow on older devices, and small models are unreliable at agentic grep→read→synthesize. |
| **Cloud via OpenRouter** (chosen) | ✓ Works on *every* device regardless of chip (kills your blocker). One OpenAI-compatible endpoint, swap any model, chase the cheapest that's good enough, per-key spend caps + automatic fallbacks. |

Why cloud wins for *this* feature specifically:
- **Hardware-independent** — runs identically on your old iPad and your Mac. The whole point given no universal Apple Intelligence.
- **The task is agentic.** The quality gap between a capable hosted model and a 3B local model on "search my vault across several files and synthesize with sources" is enormous. This feature lives or dies on that.
- **Tool use + SSE streaming** map 1:1 onto the UI (mentions, citations, the "thinking"→streaming states).
- **Scales to a big vault** — the grep→read loop only pulls in relevant files; we never stuff the whole vault into the prompt, and there's no index to keep fresh.

On-device stays an *optional later enhancement* (Apple FoundationModels for offline/private quick asks on capable devices), never the foundation.

### Cheap models: the one real caveat + mitigations
OpenRouter lets you pick cheap models — but **tool-use reliability drops as models get smaller/cheaper** (the agentic loop is the hard part). Pick a cheap model that's *good at function calling*, and add guardrails:
- **Default model = `google/gemini-3.1-flash-lite`** (verified on OpenRouter 2026-06-07; tools ✓, ~1M context, cheapest Gemini tier — ~6× cheaper than `gemini-3.5-flash`). Note: `gemini-3.5-flash-lite` does **not** exist on OpenRouter (page says "not available"); 3.1 is the current flash-lite. **Step-up if the loop gets sloppy:** `google/gemini-3.5-flash`. Make the model **config-swappable** (OpenRouter's whole point) so cost-vs-quality A/B is a one-liner (DeepSeek V3 / GPT-4o-mini / Claude Haiku are other cheap-tier candidates).
- **Cap the loop** at ~5–6 tool rounds (prevents runaway cost when a weak model flails).
- **Validate tool args** (path exists, query non-empty) and return clear error strings so the model self-corrects instead of spiraling.
- **Citations stay accurate regardless** — they come from actual `read()` calls, not the model's claims, so even a weak model cites correctly.
- Optional later: **route** — cheap model for the grep/read rounds, a slightly stronger one for the final synthesis. Over-engineering for v1; keep one model first.

## The agentic loop (pseudocode)

OpenRouter speaks the **OpenAI Chat Completions** format (`/api/v1/chat/completions`): tools as
`functions`, model replies with `tool_calls`, results go back as `role:"tool"` messages.

```
function chat(userMessage, mentionedFiles, history):
    messages = history + [user: userMessage, with mentionedFiles pre-attached as context]
    tools    = [grep, read, list]                 # OpenAI function schemas
    for round in 1..MAX_ROUNDS:                    # hard cap (~5–6) — cheap-model guardrail
        resp = OpenRouter.chat(model, messages, tools, stream=true)
        if resp.tool_calls:                        # may be several in one turn
            messages += assistant(resp.tool_calls)
            for call in resp.tool_calls:
                result = runLocally(call)          # executes against the vault filesystem
                messages += tool(call.id, result)  # role:"tool"; clear error string if invalid
            continue                               # let the model see results, decide next step
        else:
            stream resp.text → UI                  # final answer, token by token
            break
    sources = distinct files touched by read()     # → the SOURCES list in the UI
    saveTranscript(Chats/<chat>.md)                # chat persisted as a vault note
```

### Tool schemas (sent to the model)
- `grep(query: string, path?: string)` → returns `[{file, line, snippet}]`. Lexical search across
  `.md` files. The model issues several queries to triangulate (it's good at this).
- `read(path: string, range?: [start,end])` → returns file (or slice) contents. Ranges keep token
  cost down on long notes.
- `list(dir?: string)` → vault tree / folder listing, so the model can orient itself.

### grep implementation
- **MVP:** direct filesystem scan — walk the vault, substring/regex match in each `.md`, return
  hits + line numbers. For hundreds–low-thousands of notes this is fast and always fresh (no index).
- **Later, if needed:** SQLite **FTS5** index for instant search at scale (the archived
  `NotoFTS5` package is a reference). Optional **semantic/embedding** search (archived `NotoHNSW`)
  is a future *recall* lever for fuzzy queries — you asked for grep, so grep-first; embeddings add
  complexity (an embedding model + index + staleness) for diminishing return early on.

## Maps cleanly onto the UI we built
- **Mentions** (notes tagged above the composer) → pre-attached to the first user message as
  guaranteed context (the model can still grep/read beyond them).
- **AI citations / SOURCES** → exactly the set of files the `read` tool returned. Free, accurate
  citations — no guessing.
- **"AI thinking" → streaming reply** → tool-call rounds = thinking; SSE text = the streamed answer.
- **Chat saved to `Chats/`** → write the transcript as a `.md` note with frontmatter (model,
  mentioned files, sources, timestamps). Chats become first-class vault notes, per the design.

## Where it lives in the codebase (respects the package rule)
- New Swift package **`NotoChat`** (pure logic, no UIKit/SwiftUI → unit-testable via `swift test`,
  shared across iOS/iPadOS/macOS):
  - `LLMClient` — OpenRouter (OpenAI-compatible) chat completions + SSE streaming, **hand-rolled on
    `URLSession`** (honors the project's *zero external dependencies* rule; it's just JSON over
    HTTPS). Model name is config, so swapping cheap models is a one-liner.
  - `ChatAgent` — the tool-use loop (with the round cap + arg validation) + transcript assembly.
  - `VaultTools` — `grep` / `read` / `list`, built on **`NotoVault`** (which already does file
    read/list/CRUD).
- App target stays a thin shell: the chat sheet view binds to a `ChatSession` view-model that
  drives `ChatAgent` and renders the stream.

## API key + privacy (the one real product fork)
The agent loop is identical either way; only key delivery differs.
- **A — BYO OpenRouter key (MVP):** user pastes their OpenRouter key, stored in **Keychain**; calls
  go direct to OpenRouter. Ship today, no backend, user pays OpenRouter directly. OpenRouter
  supports scoped keys + per-key spend limits, which makes BYO safer than raw provider keys. Good
  for you + early users.
- **B — Backend proxy (product):** a thin server holds one OpenRouter key, forwards requests,
  meters/bills per user. Required for a real B2C launch (users won't bring keys). More to build/run.
- **Recommended path:** A now (unblocks building + your own use), B before public launch.
- **Privacy:** only grep snippets + explicitly-`read` files leave the device — never the whole
  vault. Note OpenRouter is an extra hop (your data passes through OpenRouter to the chosen
  provider); disclose it, and you can restrict to providers with no-logging/ZDR policies via
  OpenRouter settings. (On-device FM remains a future fully-private option on capable hardware.)

## Suggested build order
1. `NotoChat` package: `ClaudeClient` (non-stream) + `VaultTools.grep/read` + a single-shot
   `ChatAgent` loop. Unit-test the loop with a fake client + a temp vault. **No UI yet.**
2. Add SSE streaming + wire to the chat sheet `ChatSession` (mentions → context, stream → reply).
3. Citations from `read` → SOURCES; save transcript to `Chats/`.
4. Polish: cancellation/stop, errors/offline, token-budget guards on `read`.
5. (Later) FTS5 index, optional embeddings, optional on-device fallback, backend proxy.

## Open decisions for Eugene
- Provider: **OpenRouter** (chosen). Default model = **`google/gemini-3.1-flash-lite`**, config-swappable (step-up: `google/gemini-3.5-flash`).
- Key delivery: **A (BYO OpenRouter key) now → B (proxy) for launch** (recommended).
- Search: **grep-first** now; FTS5/embeddings later.
