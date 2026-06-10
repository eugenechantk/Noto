# Multimodal Embedding Research — Text + Image in One Space?

**Date:** 2026-06-10 (research current as of this week's WWDC26 announcements)
**Question:** Is there a multimodal embedding model that can serve both text and image search on-device — ideally replacing granite so one index holds notes AND images?
**Method:** 4 parallel research surveys → shortlist → one adversarial fact-checker per candidate verifying license/size/benchmark/conversion claims against primary sources only. Raw reports + verification verdicts: `.claude/research/multimodal/`.

---

## 1. Verdict

**A unified model that fits Noto's constraints does not exist as of June 2026.** Every candidate fails at least one hard requirement (license / size / multilingual text quality):

| Candidate | Params | License | Multilingual text-text | Fatal flaw |
|---|---|---|---|---|
| jina-clip-v2 / v5-omni / v4 | 865M–3.8B | **CC-BY-NC / Qwen Research** | strong | non-commercial license |
| **Qwen3-VL-Embedding-2B** (Jan 2026) | 2.13B (verified) | Apache 2.0 ✓ | MMTEB retrieval 67.1 (verified — the survey's 78.5 was a misread column) | **~1.06 GB at int4** — 3.5× the bundle budget; viable only as optional download |
| Nomic aligned towers (text+vision) | ~230M | Apache 2.0 ✓ | **English-only** | EN↔ZH would collapse vs granite |
| GME (Qwen2-VL-2B) | 2.2B | Apache + attribution clauses | strong EN+ZH | size + ANE-hostile |
| VLM2Vec / E5-V / mmE5 / LLaVE | 0.9B–11B | mixed | mostly EN | size |

Notable: **jina-embeddings-v5-omni** (May 2026) proves the exact architecture we'd want — a **frozen** text tower (zero text-search regression by construction) with a vision encoder aligned onto its space via a small projector (0.35% trained weights). Architecture is the dream; license is NC. Watch for permissive reproductions of this "locked aligned towers" pattern, or a sub-1B Apache distillation of Qwen3-VL-Embedding.

## 2. The image-leg alternative (separate CLIP-style space, third RRF leg)

Best verified candidate: **FG-CLIP2-Base** (Qihoo 360, Oct 2025) — Apache 2.0 (license chain verified clean incl. the Gemma tokenizer question), 384M params, SigLIP2-B towers, **the only base-size model that is strong in BOTH English and Chinese** (COCO-CN T→I 62.9 vs SigLIP2-B's 46.2 — verified in paper Table 5; also beats the Chinese-CLIP specialist). Realistic quantized size **~285 MB** (int8 + 4-bit on the 197M-param 256k-vocab embedding table); image tower alone ~93 MB.

Costs and risks (verified): DIY Core ML conversion (no official artifacts; 1,400 lines of `trust_remote_code` with a custom dual position-embedding text tower — **silent space-misalignment risk**; a Python↔Swift parity harness like granite's golden-vector gate is mandatory); Qihoo 360 is a US Entity List company (doesn't restrict our use of Apache weights, but optics). Fallbacks: SigLIP2-B (Apache, official, but ZH drops ~17 pts), UForm3-multilingual (Apache, **ready-made CoreML pair ~198 MB + Swift SDK** — verified — but tiny-tier quality, 256-d, dormant project), mSigLIP. Apple's MobileCLIP would be ideal engineering-wise but is **disqualified twice**: research-only license (apple-amlr; the v1 CoreML repo's permissive tag now points to a deleted license file) and English-only tokenizer.

## 3. The evidence favors the caption/OCR architecture for Noto's content

Three independent findings line up:

1. **Noto's images are mostly text-bearing** (screenshots, receipts, whiteboards, slides). MIEB (130-task multimodal embedding benchmark) shows CLIP-family models are systematically **weakest exactly on visual-text and multilingual tasks** — Noto's two stress points.
2. **Caption-then-text-embed beats phone-scale CLIP on personal images**: CIVIL (2025, lifelog retrieval) measured P@10 **0.73 for captions+text-embedding vs 0.58** for the strongest CLIP/SigLIP image embeddings (caveat: 7B captioners; verified).
3. **Apple is about to make the describer free**: WWDC26 (this week) announced **image input for Foundation Models in iOS 27** (fall 2026, iPhone 15 Pro+) plus a built-in Vision-backed OCRTool — a zero-bundle-MB on-device captioner. Today, Vision already gives us zh-Hans/zh-Hant OCR, the new iOS 26 `RecognizeDocumentsRequest` (paragraphs/tables/lists — ideal for receipts and whiteboards), and 1,303-label image classification, all 0 MB.

And critically: granite's cross-lingual space means **English OCR text / labels / captions are searchable by Chinese queries** — the EN↔ZH bar survives without a multilingual vision model.

Bundled small VLM captioners were checked and rejected for now: SmolVLM2-500M is the best-licensed option but its image-capable int4 builds measure **356–412 MB** (the "fits 300 MB" claim was refuted), conversion is a custom project, and its strategic window closes when iOS 27 ships.

## 4. Recommendation — staged, no new model today

**Stage 1 (build now): image → text fields → the existing granite index.**
Extract per image: Vision OCR (+ document structure on iOS 26) + top classification labels + markdown alt text + the note's contextual header → embed as an image-kind chunk in `semantic.sqlite` (new `kind` + image path on the chunk record). Works for vault images and downloaded+cached remote images. Zero new models, zero bundle growth, full reuse of indexing/fusion/UI/chat tool.

**Stage 2 (fall 2026): swap the describer, not the architecture.**
On iOS 27 / Apple-Intelligence devices, upgrade photo descriptions with Foundation Models image captioning (zero MB). The image-chunk record keeps a `describer_version` so re-description is incremental, exactly like `model_version` for embeddings.

**Stage 3 (only if pure-visual queries still disappoint): FG-CLIP2-Base third leg.**
Gate it the same way granite was gated: conversion spike + parity harness + an EN/ZH retrieval eval on Eugene's actual images, fused as a third RRF leg (~285 MB, image tower ~93 MB does the indexing).

**Revisit-unified trigger:** a ≤400M permissive model with frozen-tower alignment (jina-v5-omni pattern) or an Apache distillation of Qwen3-VL-Embedding would collapse Stage 3 and the text index into one space — re-run this research when one appears.

## 5. Key verified claims (adversarial fact-check results)

- Qwen3-VL-Embedding-2B: Apache clean ✓; 2.13B params / 4.26 GB bf16 ✓; "retrieval 78.5" **refuted** (real: 67.1 — pair-classification column misread); "Core ML impractical" **refuted** (fixed-shape CoreML port of the same base VLM runs on A18 ANE) — the blocker is purely the ~1 GB footprint.
- FG-CLIP2-Base: license chain ✓; ZH benchmark wins ✓ (Table 5 primary source); size claim corrected to ~285+ MB; biggest risk = text-tower conversion fidelity (custom dual position embeddings).
- UForm3: everything checked out (incl. exact .mlpackage byte sizes) except maintenance — project dormant since Oct 2025, pinned to a personal swift-transformers fork; and its COCO numbers are train-contaminated (admitted on the card).
- SmolVLM2-500M: "fits ≤300 MB" **refuted** (356–412 MB image-capable); iPhone deployment proof ✓ (via MLX, not Core ML); iOS 27 FM image input ✓ (fall 2026, iPhone 15 Pro+).

Full verdicts with primary-source URLs: `.claude/research/multimodal/mm-verifications.md`.
