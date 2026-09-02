# Noto × gbrain — three capabilities

**Date:** 2026-08-23
**Inputs:** `~/dev/inbox/.claude/gbrain-noto/{interfaces,noto-as-brain-repo,gbrain-mechanics}.md`, treehole's gbrain integration (`proxy-vercel/api/proxy.js`, `gb.sh`), Noto packages `NotoChat`, `NotoSearch`, `NotoAgentCLI`.
**Status of the brain:** `~/Library/Mobile Documents/com~apple~CloudDocs/Brain/` exists with `gbrain.yml` → migration (Phase 0) done. gbrain host (the Pro) is **unreachable today** — `https://gbrain.eugenechantk.me/{mcp,token}` → 530, Tailscale stopped on the Air — so nothing below was verified live.

---

## 0. The one shape that fits all three

```
iPhone/iPad/Mac Noto ──(files via iCloud)──► Brain/ vault ──► gbrain sync (autopilot, ~5 min) ──► Postgres index
        │                                                                                          ▲
        └──(HTTPS, scoped OAuth client)──► gbrain.eugenechantk.me/mcp  ◄──── query / think / graph ─┘
```

Two channels, used deliberately:

| Channel | Use for | Why |
|---|---|---|
| **Files in the vault** | anything that should *exist as a note* — capture, edits from chat | offline-capable, instant, Noto is already built on it, gbrain picks it up on the next autopilot tick, provenance = your edit |
| **gbrain HTTP MCP** | anything that needs the *index* — hybrid search, think, backlinks, graph walk, recall, chronicle | that's the only place the intelligence lives; reads only (plus `think`) |

Rule: **Noto never writes to the brain over the API.** It writes files; gbrain indexes them. That avoids the two-writers-on-one-file problem (`noto-as-brain-repo.md` §3.3) entirely.

---

## 1. Quick capture → gbrain consolidates

**What you want:** one tap, type, done. Later, gbrain folds it into the brain.

**Design — zero API dependency:**
- Capture writes a small markdown file into the vault. **Where depends on what "consolidate" means** (see "How diary is processed" below):
  - **Ideas/thoughts to fold into the brain (default):** `inbox/<YYYY-MM-DD>-<hash8>.md` with explicit frontmatter `type: note` + `status: inbox` — the exact shape `gbrain capture` produces (verified in source v0.46.28: `capture-content.ts` defaults `type: 'note'`, slug `inbox/<date>-<sha8>`). **There is no `inbox` page type** in any pack; `inbox/` is a slug convention and the cycle has no triage phase for it, so the frontmatter type is what earns processing: `note` is `extractable: true` and facts-eligible → atoms → concepts. A file dropped there *without* `type:` falls back to `concept` (`inferTypeFromPack` default) — so Noto must always stamp it. Caveat: the atom prompt is transcript-shaped with a notability gate — short thoughts often yield 0–1 atoms; the filing job is what gives them context. Check `inbox/` is git-tracked (not declared in `gbrain.yml` tiers).
  - **Journal/feelings (toggle):** `life/diary/<YYYY-MM-DD>-<hash8>.md`, typed `diary` — indexed, on the time axis, event-extracted (PATCH-001), private (redacted for remote callers), but **never** mined into atoms/facts/concepts.
- iCloud moves it to the Pro; autopilot's next tick (~300 s) runs `sync` → indexed, embedded, then the per-source phases (extract, facts/atoms if eligible, chronicle, salience) and the global ones (embed, synthesize_concepts).

**How diary is processed in the cycle (for the record):** lint/backlinks may write to the file → sync → deterministic extract of `[[links]]` + dated timeline lines → `extract_facts` skipped (type not eligible) → `extract_atoms` skipped (`extractable: false`) → chronicle events extracted only with `chronicle.include_diary=true` (PATCH-001, live-verified 2026-08-09) → salience scored → takes may be proposed → embedded, with a 1.0–1.25× boost on temporal queries. `synthesize_concepts` never sees it. Thematic self-knowledge from diary is a gap (needs a separate pass, not stock).
- Noto shows it immediately in a **Captures / Thoughts** list (it's just a folder), and because gbrain's derived pages are also files, you see the consolidated result in Noto too.

**gbrain does NOT write thoughts into your existing pages.** Its consolidation is distil-and-cluster into *its own* pages (`atoms/`, `concepts/`); existing pages only get reciprocal `[[links]]` (if you wrote the link), entity fact-fence rows, and queued takes. `enrich` is the one page-rewriter and it's off/CLI-only. If "my thought about X ends up in `X.md`" is the goal, that is an **agent filing step**, which already exists as the `noto-notes` skill ("route ideas to relevant notes" via `noto-agent`):

1. Capture → `inbox/<date>-<hash8>.md` (`type: note`, `status: inbox`) instantly, offline.
2. **Filing job on the Pro** (Hermes or a Claude Code cron running `noto-notes`): per inbox item, gbrain `query` + `get_backlinks` to find the related note, append the thought as a dated line with a link back to the capture, flip `status: inbox` → `filed_to: <slug>` (or move it). Hourly or nightly.
3. gbrain's next tick indexes the edited note; atoms/concepts on top for free.

This gives both: gbrain's cross-corpus distillation *and* your notes accumulating your thoughts.

**UI surface (ordered by value):**
1. Capture button on the sidebar/toolbar → sheet with a single text field; Return saves, no title needed (first line = title).
2. Share extension (text/URL from any app).
3. Lock-screen / Control Center widget → opens the capture sheet.
4. Siri/Shortcuts intent ("Jot in Noto").

**Needs on the Pro (not Noto work):** autopilot installed and `dream` scheduled (plan steps 17). Unverifiable today — host down. **Gate: confirm `gbrain autopilot` is running before declaring capture "consolidates".**

**Deliberately not:** `POST /ingest`. That creates a brain page without a vault file — right for Hermes side-channel stuff, wrong for a thought you typed into your notes app and expect to see there.

---

## 2. Search — title + body, accurate

**What exists:** `NotoSearch` — FTS5 (`MarkdownSearchEngine`, `SearchIndexStore`) + semantic (`Semantic/`, CoreML embeddings, RRF plan in `project_semantic_search_plan`). On-device, offline, instant. Open bug: 024 (search result opens blank editor).

**What gbrain adds:** `query` = hybrid BM25 + vector + multi-query expansion + reranker (`qwen3-rerank`); `search` = BM25 only; both over the indexed corpus with a ~5 min lag and network dependency.

**Design — local-first, gbrain as a deeper tier:**
- **Tier 1 (default, always):** NotoSearch. Do the accuracy work here, because it's what answers in <50 ms on a phone with no network: title-field boost, prefix/typo tolerance on titles, recency boost, exact-phrase first, then RRF with semantic.
- **Tier 2 (when reachable):** after local results render, call gbrain `query` in the background and merge via RRF; results that only gbrain found (semantic neighbours, derived atoms/wiki pages) slot in below. Slug ↔ vault path is deterministic in the brain repo, so a gbrain hit opens the real file.
- Indicator in the results header: "local" vs "local + brain", never a spinner blocking the list.

**"Make it accurate" needs a yardstick:** a 20–30 query eval set (`query → expected note`) in `NotoSearch/Tests`, scored by MRR/top-3 hit. Tune against it; regress nothing. This is the first concrete task — without it "accurate" is vibes.

---

## 3. Chat with my brain — context, relationships, edit while chatting

**What exists:** `NotoChat` — OpenRouter streaming agent loop, tools `grep` / `read` / `list` over the vault, `propose_edits` → edit-suggestion cards the user accepts (writes the file). iOS UI live.

**Design — keep the loop, swap in smarter tools:**

| Capability | Tool(s) the agent gets | Source |
|---|---|---|
| Pull pages for context | `query` (ranked, reranked), `get_page`, `get_chunks`, `resolve_slugs` | gbrain |
| Understand relationships | `get_backlinks`, `get_links`, `traverse_graph` (N hops), `find_contradictions`, `find_trajectory` | gbrain |
| Time | `chronicle_day` / `on_this_day` / `since` / `last_seen`, `get_timeline` | gbrain |
| Working memory | `recall` (this week's facts) | gbrain |
| Deep synthesis | `think` (multi-hop; persists a page — the one write-scope tool worth granting) | gbrain |
| Raw vault access | `grep`, `read`, `list` — keep as fallback when gbrain is unreachable | local (exists) |
| **Edit while chatting** | `propose_edits` → cards → write file → autopilot re-indexes | local (exists) |

So "edit while chatting" is already solved in the file channel; the new work is the read side. The agent gets told: *prefer `query`/graph tools; fall back to grep/read if the brain tool errors.* Today's outage (530) is exactly the case to design for — chat must degrade to local tools, not die.

**The one real fork — where does the chat LLM run?**

| Option | How | Pro | Con |
|---|---|---|---|
| **A. On-device loop (current NotoChat) calling gbrain tools** — *recommended* | OpenRouter model, Noto orchestrates tool calls to gbrain MCP | streaming UI already built; works on every device; offline fallback to local tools is natural | pays OpenRouter per token; N round-trips phone→Pro per answer |
| B. Server-side agent on the Pro | `submit_agent` / `think` via gbrain, using the Claude subscription (`claude-cli` provider) | near-zero marginal cost; one round trip | no streaming; Noto becomes a poll-and-render shell; no offline; `claude-cli` provider flakiness noted in treehole report |

Recommend **A now**, with `think` available as a single heavyweight tool — that gives you B's cheap deep-synthesis inside A's UI. Revisit if OpenRouter cost bites.

---

## 4. Shared plumbing — `Packages/NotoBrain`

One new package, UI-free, `swift test`-able:
- `BrainClient`: Streamable-HTTP MCP over `URLSession` — `POST /mcp` JSON-RPC, parses `application/json` *and* `text/event-stream` replies (treehole's `gb.sh` is the whole protocol in 8 lines). `tools/list`, `tools/call`.
- `BrainAuth`: mints/caches a bearer via `POST /token` (client-credentials), refreshes before the 1 h expiry, **always** sends `Bearer ` prefix (gbrain rejects bare tokens — measured in treehole).
- Typed wrappers for the ~12 tools above + `BrainReachability` (health probe, short timeout, cached "down" state so the UI doesn't stall).
- Consumers: `NotoChat` (tool adapters), `NotoSearch` (tier 2), Settings (connect/disconnect).

**Auth / credentials:** register a dedicated client on the Pro:
`gbrain auth register-client noto-app --scopes "read write" --bound-tools "query,search,get_page,get_chunks,list_pages,resolve_slugs,get_backlinks,get_links,traverse_graph,find_contradictions,find_trajectory,chronicle_day,chronicle_on_this_day,chronicle_since,chronicle_last_seen,get_timeline,recall,think" --budget-usd-per-day 2`
— `write` scope only because `think` persists; `put_page`/`delete_page` are *not* in the bound tools, so the app physically cannot write pages even if compromised. Client id+secret stored in **Keychain** (pasted once in Settings; single-user app, no proxy needed — unlike treehole, which can't ship secrets to the OpenAI/xAI side). Endpoint: `https://gbrain.eugenechantk.me` (CF tunnel; works off-Tailscale).

---

## 5. Build order

| # | What | Depends on | Size |
|---|---|---|---|
| 1 | **Capture** — sheet + folder + frontmatter type; verify it lands in `life/diary/` and shows in Noto | nothing (file channel) | S |
| 2 | **Search eval set + local accuracy pass** (title boost, prefix, recency, RRF) | nothing | M |
| 3 | **`NotoBrain` package** — client, auth, reachability, typed tools, tests against a recorded fixture + live smoke when host is up | Pro reachable to smoke-test | M |
| 4 | **Chat tools** — gbrain adapters in `NotoChat`, prompt guidance, graceful fallback | 3 | M |
| 5 | **Search tier 2** — background `query` + RRF merge + source indicator | 2, 3 | S |
| 6 | **Filing job** on the Pro — inbox → related notes via `noto-notes` + gbrain `query` | 1, Pro up | M |
| 7 | Capture extras — share extension, widget, Shortcut | 1 | S each |

Host-side prerequisites (not Noto code, blocked until the Pro is back): autopilot + dream running; `gbrain serve --http` up; `noto-app` client registered; confirm the CF tunnel is alive.

## 6. Open questions (need Eugene or the Pro)

1. Is the Noto app already repointed to `Brain/` on all devices (plan step 14)? The `noto-notes` skill still hardcodes `…/CloudDocs/Noto`, and the newest file in `Brain/life/diary/` is 2026-08-06 — 17 days of nothing suggests entries may still be landing in the old vault.
2. Is autopilot + nightly dream actually scheduled on the Pro (step 17)? Determines whether capture "consolidates" today or only after that's set up.
3. Why is the Pro/tunnel down right now — transient, or did `gbrain serve --http` never get started detached (plan step 18 warns about this)?
