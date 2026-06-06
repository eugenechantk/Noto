# Feature: NotoChat package

## User Story

As a Noto user, I can chat with an AI that can search (`grep`) and read any file in my vault and
answer with sources, using a cheap cloud model via OpenRouter — working on every device regardless
of Apple Intelligence support.

## User Flow

(UI is designed separately — `Noto AI Chat.html`.) This package is the engine:
1. User sends a message (optionally with mentioned files pre-attached).
2. `ChatAgent` runs an agentic loop: model may call `grep`/`read`/`list` tools, which execute
   locally against the vault; results feed back until the model produces a final answer.
3. The final answer streams token-by-token; files the model `read` become the cited sources.
4. The transcript can be saved to the vault as a markdown note (`Chats/`).

## Success Criteria

- SC1 `grep(query, path?)` finds matching lines across `.md` files (recursive), case-insensitive,
  returning relative path + 1-based line number + snippet; respects an optional subfolder scope and
  a result cap.
- SC2 `read(path, start?, end?)` returns a vault file's content (or a 1-based inclusive line range);
  rejects paths that escape the vault root.
- SC3 `list(path?)` lists a directory's immediate children, directories first then `.md` notes.
- SC4 `OpenRouterClient` builds a correct OpenAI-compatible `/chat/completions` request (model,
  messages, tools, auth header) against the OpenRouter base URL; zero external dependencies.
- SC5 `OpenRouterClient.stream` parses SSE, emitting incremental text deltas and, when the model
  finishes with tool calls, the assembled `tool_calls` (arguments correctly concatenated across
  chunks) then a finish event. **Streaming is required.**
- SC6 `ChatAgent` runs the loop: executes tool calls against `VaultTools`, feeds results back,
  produces a final streamed answer, collects `read` files as sources, and caps at `maxRounds`.
- SC7 `grep` and `read` work against Eugene's real vault
  (`~/Library/Mobile Documents/com~apple~CloudDocs/Noto`, 881 `.md` files).
- SC8 Default model is `google/gemini-3.1-flash-lite`, swappable via config.
- SC9 Transcript can be serialized to markdown with frontmatter (id, model, mentioned, sources) and
  saved into a `Chats/` directory.

## Test Strategy

- SC1–SC3: package unit tests over a temp vault with nested folders (`VaultToolsTests`).
- SC4–SC5: `OpenRouterClient` tests using a `MockURLProtocol` that returns canned JSON / SSE bytes;
  plus pure-function tests of the SSE decoder (`SSEStreamDecoderTests`) for tool-call delta merge.
- SC6: `ChatAgentTests` with a scripted fake `LLMClienting` (tool round → final answer); asserts
  tool execution, source collection, round cap.
- SC7: env-gated integration test (`RealVaultTests`, runs only when `NOTO_VAULT` is set) — grep a
  known term + read a known file from the real vault; also run manually via CLI.
- SC8–SC9: unit tests on config default + transcript markdown serialization.

## Tests

### Package Unit
- `NotoChatTests/VaultToolsTests.swift` — grep/read/list (SC1–SC3), path-escape rejection.
- `NotoChatTests/SSEStreamDecoderTests.swift` — SSE parsing + tool-call delta accumulation (SC5).
- `NotoChatTests/OpenRouterClientTests.swift` — request building + complete()/stream() via
  MockURLProtocol (SC4–SC5).
- `NotoChatTests/ChatAgentTests.swift` — agentic loop with fake client (SC6).
- `NotoChatTests/TranscriptTests.swift` — markdown serialization (SC9).
- `NotoChatTests/RealVaultTests.swift` — env-gated real-vault grep+read (SC7).

## Implementation Details

- Package `Packages/NotoChat`, platforms iOS 17 / macOS 14, swift-tools 5.10.
- Dependency: local `NotoVault` only (internal package — **no external dependencies**).
- `read` uses `VaultFileSystem.readString` (NSFileCoordinator — correct for iCloud) + iCloud
  download handling; `grep` does a fast direct scan for throughput.
- Client hand-rolled on `URLSession` (`data(for:)` for complete, `bytes(for:).lines` for stream).
- Path safety: resolve under root, reject `..` escapes.
- Token guards: grep result cap; read char/line cap with truncation note.

## Residual Risks

- Pure-logic package: no UI/simulator proof (none needed). UI wiring (chat sheet view-model) is a
  later task.
- Live LLM calls aren't hit in CI (no key); the loop is proven with a fake client + the SSE decoder
  is proven against canned OpenRouter chunk formats. A real end-to-end call needs an OpenRouter key.
- grep over **undownloaded** iCloud files won't see content (needs download/index) — fine on the
  Mac where files are present; flagged for the on-device case.

## Results (2026-06-07)

All success criteria met. `swift build` clean; **26 unit tests pass** across 5 suites
(`VaultToolsTests`, `SSEStreamDecoderTests`, `OpenRouterClientTests`, `ChatAgentTests`,
`TranscriptTests`). SC1–SC3, SC5, SC6, SC9 proven by unit tests; SC4/SC5 client behavior proven via
`MockURLProtocol` (complete + stream) and direct `makeURLRequest` assertions.

**SC7 (real vault) validated** against `~/Library/Mobile Documents/com~apple~CloudDocs/Noto`
(881 notes): `grep "pricing"` returned real hits with paths + line numbers + snippets; `grep "the"`
hit the cap; `read` pulled a real 6,796-char note. Run:
`NOTO_VAULT="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Noto" swift test --filter RealVault`.

**Live end-to-end smoke test (real OpenRouter key + real vault) ✓** — `google/gemini-3.1-flash-lite`
answered "what have I written about pricing" by `grep`-ing then citing, in 2 rounds (~4s), streaming.
(Key supplied via `OPENROUTER_API_KEY` env var — never committed. Test: `LiveChatTests`, gated.)

**Citations design (SC10, from live findings):** answers must cite their sources whether the info
came from a grep snippet OR a full read — forcing a `read` just to cite is wasteful. Solution: a
`cite(paths)` tool the model calls (in the same turn as its final answer) listing the notes it used;
the agent **validates each cited path against the files the tools actually surfaced** (grep hit files
+ reads) so citations are always real files — never hallucinated, never the whole 50-file grep dump.
A cite-only turn is terminal (its text is the answer), with a last-non-empty-text fallback. Verified
live: `grep("price")` → answer + `cite` of 5 grep-surfaced files, all validated, `sources` populated.

**Date filtering folded into `grep` (SC11):** `grep` gained optional `created_after/before` +
`updated_after/before` (ISO `YYYY-MM-DD`). With a `query` it returns date-filtered line matches;
**without a query it lists the notes matching the filters** (most-recent-first) — the "diaries in
the last 5 days" case. Dates come from frontmatter `created` + **`updated`** (Noto v2's canonical
field — confirmed `VaultMarkdown.swift`/Readwise/daily notes all write `updated:`; the v1
`Frontmatter.swift` `modified:` path is unused), with filesystem fallback. The
agent injects today's date into the system prompt so the model resolves relative ranges itself.
**Live ✓:** "diaries in the last 5 days" → model computed `modified_after=2026-06-02`, grep filter
listed 33 recent notes, cited the 5 Daily Notes (06-03…06-07). Unit-tested in `DateFilterTests`.

**Performance (date filter is not indexed — measured on the real 881-note vault):** filtering reads
note **headers only** (first 4 KB) for dates/title, never full bodies; a date-filtered keyword grep
checks the header first and skips full reads of out-of-range files. Measured: filter-only listing
across the whole vault ≈ **257 ms**; keyword grep + date filter ≈ **116 ms** (faster than unfiltered
grep ~500 ms, because it skips ~847 full-body reads). Cost is file I/O, not frontmatter parsing, and
is trivial vs the ~4 s LLM call. A metadata index is only warranted at much larger scale (→ FTS5).

Not done (future): UI wiring (chat sheet view-model); FTS5/embeddings; backend key proxy;
swap-up to `google/gemini-3.5-flash` if loop quality needs it.

## Bugs

_None yet._
</content>
