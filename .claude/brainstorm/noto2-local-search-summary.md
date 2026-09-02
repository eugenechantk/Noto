# Noto 2 — Local model for the search-results summary

**Date:** 2026-08-25
**Question:** Can the Noto 2 search screen summarize results with a local model, on an iPhone 13 Pro?
**Short answer:** Not Apple's. A bundled one is technically possible but a poor fit for *this* feature. There's a better third option.

---

## Where the feature stands today

Already built and shipping:

- `Noto2/Search/SummaryPromptBuilder.swift` — pure prompt construction: top 8 distinct notes,
  1,800 chars each, frontmatter stripped, system prompt forbidding invention.
- `Noto2/Search/SearchModel.swift` — `startSummary()` streams the completion through
  `NotoChat` (OpenRouter, remote), with `.needsKey` / `.streaming` / `.done` / `.failed` states.

So the ask is a **runtime swap behind an existing, well-factored seam** — not new plumbing.
`SummaryPromptBuilder` stays as-is for any option below.

Relevant existing on-device precedent: `Packages/NotoEmbedding` already loads a **94 MB int8
Core ML** Granite embedder (`computeUnits = .cpuAndNeuralEngine`) in-process for semantic search.

---

## Option 1 — Apple Foundation Models (`SystemLanguageModel`)

**Verdict on an iPhone 13 Pro: hard no.**

The framework gates on Apple Intelligence, which requires **A17 Pro or later** (iPhone 15 Pro /
15 Pro Max and the 16/17 lines). The stated reason is the 8 GB memory floor needed to keep the
model resident. iPhone 13 Pro is **A15 Bionic, 6 GB** → `availability` returns
`.unavailable(.deviceNotEligible)`. No software workaround exists.

Worth noting the project already targets iOS 26, so the *API* is available to compile against —
it's purely the device that's ineligible.

## Option 2 — Bundle a small LLM (MLX Swift or llama.cpp)

Technically runs on an A15. Three problems specific to this feature:

1. **The prompt is long, and prefill is the expensive half.** `SummaryPromptBuilder` produces
   8 × 1,800 chars ≈ **3.5–4k tokens** of input for a 400-token output. Published ~58–70 tok/s
   figures for Qwen3-1.7B on iPhone are *short-prompt decode on much newer silicon*. On an A15
   with a 4k prefill, expect first token in the seconds-to-low-tens-of-seconds range and the
   full summary well past 20s — against ~1s to first token today. **These are estimates; the
   only honest number comes from measuring.**
2. **Quality is the wrong risk to take.** A 1–2B model doing grounded multi-document
   summarization over the user's own notes will confabulate. The system prompt's one real
   promise — *"Do not invent facts that are not in the notes"* — is exactly what a model that
   size cannot hold.
3. **Cost of carriage.** ~700 MB–1 GB of weights (on-demand download, not in the bundle) plus a
   non-Apple SPM dependency. Directly contradicts the repo principle: *"No external
   dependencies. Pure Apple frameworks only."*

Not worth it here. Revisit if the goal becomes fully-offline *chat*, where a long fixed prefill
doesn't dominate every interaction.

## Option 3 — Extractive summary using the embedder already in the app ← recommended

No LLM. Reuse `GraniteTextEmbedding` / `SemanticSearchService`, which is already warm in-process:

1. Split the top-N hit bodies into sentences.
2. Embed sentences + the query in one `embed([String])` batch.
3. Rank by cosine to the query vector; apply an MMR-style penalty so the picks aren't three
   restatements of the same line.
4. Render the top 3–5 as bullets, each attributed to its note title — reusing
   `SummaryPromptBuilder.rendered()` and the existing provenance line.

Why this wins for "what do my notes say about X":

- **Zero hallucination by construction** — every line is verbatim from his own notes.
- **Instant, offline, free**, no API key, no `.needsKey` state.
- **No new dependency**, no bundle growth, nothing new to keep loaded in memory.
- Works on the 13 Pro *today*, and on every device.

The tradeoff is honest: it's a highlight reel, not prose. For search-result triage that is
arguably the more useful artifact.

## Option 4 — Foundation Models behind an availability check (cheap future-proofing)

Independent of the above, and small (~50 lines): branch on
`SystemLanguageModel.default.availability`. On a 15 Pro / 16 / 17 the summary becomes free,
private, and offline; on the 13 Pro it falls through to whatever the fallback tier is. Costs
almost nothing now and is the thing that pays off on the next phone.

---

## Recommendation

Ship **Option 3** as the local/offline summary tier, keep OpenRouter as the opt-in "better
prose" tier, and add **Option 4** as a middle tier when convenient. Skip Option 2.

Suggested tier resolution in `SearchModel.startSummary()`:

```
Foundation Models available?  → on-device abstractive   (15 Pro+)
else OpenRouter key present?  → remote abstractive      (today's path)
else                          → extractive, embeddings  (always works)
```

This also removes the current `.needsKey` dead end — there is always *a* summary.
