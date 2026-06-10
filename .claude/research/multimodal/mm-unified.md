# unified

## Summary
No unified multimodal embedding model ≤~400M params exists (as of June 2026) that matches granite-embedding-97m-multilingual-r2's 60.3 MTEB multilingual retrieval while adding an aligned image tower under a permissive license. Every candidate fails on at least one hard constraint: jina-clip-v2 (865M) and the new jina-embeddings-v5-omni (May 2026, 0.95B/1.57B — architecturally the exact "locked aligned towers" dream) are CC-BY-NC; jina-embeddings-v4 and nomic-embed-multimodal-3b are Qwen Research License (non-commercial); Qwen3-VL-Embedding-2B (Jan 2026) is Apache 2.0 and likely beats granite on multilingual text-text while adding images/video, but is 2B params (~2 GB int8, ~6x the 300 MB budget) with no Core ML path; the only permissive small option (Nomic aligned towers, ~230M, Apache) is English-only and would regress EN→ZH. Recommendation: keep granite text-only today; the most interesting forward path is the GELATO/locked-tower pattern from jina-v5-omni — a small vision encoder projector-aligned onto granite's frozen space (only ~0.35% trainable weights in Jina's version), or wait for a sub-1B Apache distillation of Qwen3-VL-Embedding.

## Findings
# Unified Multimodal Embedding Models for On-Device Noto Search — June 2026

**The bar:** ibm-granite/granite-embedding-97m-multilingual-r2 — ~97M params, int8 Core ML ~94 MB, MTEB Multilingual Retrieval **60.3**, EN+ZH cross-lingual works today. Constraints: Core ML only, ≤~300 MB added bundle, permissive commercial license, multilingual text-text must not regress.

**Bottom line: no qualifying unified model exists at ≤~400M params.** Three distinct failure modes cover the entire field: (1) good + small enough but non-commercial license (Jina), (2) good + permissive but 2B+ params (Qwen, GME), (3) small + permissive but English-only or no real text-text capability (Nomic aligned towers, all CLIP-family).

## Candidate-by-candidate

### 1. jina-clip-v2 (Dec 2024) — quality fits, license and size kill it
- **Params:** 865M total = 561M text (Jina-XLM-RoBERTa, 24 layers) + 304M vision (EVA02-L/14). Int8 ≈ **~870 MB** — ~3x over budget; even the text tower alone (~565 MB int8) exceeds it.
- **Dims:** 1024, Matryoshka 64–1024; paper reports <1% degradation at 256-d.
- **Text-text:** MTEB English retrieval 49.32 nDCG@10; on the paper's multilingual MTEB task set, retrieval 69.85 / STS 67.77; Jina states the text tower is "on par with jina-embeddings-v3." Caveat: 69.85 is on Jina's selected multilingual task mix, not the same MTEB(Multilingual) retrieval set behind granite's 60.3 — not strictly comparable, but the text tower is plausibly at/above granite quality.
- **Text-image:** CLIP-benchmark EN t2i R@5 79.09; Crossmodal-3600 multilingual t2i R@5 81.43. 89 languages incl. Chinese; 8,192 max tokens; 512×512 images.
- **License: CC-BY-NC-4.0** (verified HF tag). Commercial use requires paying Jina (API/AWS/Azure/GCP). **Disqualified for a shipped App Store app.**
- **Core ML:** dual-tower encoder architecture would convert cleanly in principle; no official or community port found.

### 2. jina-embeddings-v4 (June 2025) — non-commercial and far too big
- 3.8B params, Qwen2.5-VL-3B-Instruct based; 2048-d single-vector (truncatable to 128) + multi-vector mode; 30+ languages.
- **License: Qwen Research License** (initially mislabeled CC-BY-NC) — **non-commercial**. Int8 ≈ 3.8 GB. Doubly disqualified.

### 3. jina-embeddings-v5-omni (May 2026) — architecturally the exact dream, still NC
- **GELATO** ("Geometry-preserving Embeddings via Locked Aligned Towers"): a **frozen** v5 text tower (text-text geometry preserved exactly — zero regression by construction) + pre-trained vision/audio encoders attached via small trained projectors; only **0.35% of weights trained**.
- Variants: omni-small **1.57B** total (0.67B Qwen3-0.6B-based text backbone, 1024-d); omni-nano **0.95B** total (0.24B EuroBERT-210m-based text backbone, 768-d). Safetensors confirm 1.63B / 0.99B params → int8 ≈ 1.6 GB / ~1.0 GB. Both over budget.
- **Benchmarks:** MMTEB mean-task 67.0 (small) / 65.52 (nano); MIEB aggregate 56.05 (small). Matryoshka down to tiny dims.
- **License: CC-BY-NC-4.0** (verified HF tags on both checkpoints). **Disqualified.**
- **Strategic significance:** this paper proves the pattern Noto actually wants — lock the existing multilingual text model, align a vision tower to its space with a cheap projector. See "Forward paths" below.
- (jina-embeddings-v5-text-nano, 212M EuroBERT-based, Feb 2026, would otherwise be a granite-class text candidate — also CC-BY-NC.)

### 4. Nomic "aligned towers" — perfect license/size, fails multilingual
- **nomic-embed-vision-v1.5** (92.9M, Apache 2.0) shares embedding space with **nomic-embed-text-v1.5** (137M, Apache 2.0). Combined ~230M → int8 ~230 MB — fits the budget. ImageNet 0-shot 71.0, MTEB 62.28 (English).
- **Fatal flaw:** v1.5 text is **English-only**. EN→ZH cross-lingual would collapse vs granite. **Disqualified on the multilingual requirement.**
- **nomic-embed-text-v2-moe** (475M total / 305M active, Apache 2.0, ~100 languages, Matryoshka) has **no aligned vision tower** — Nomic never shipped one. Their multimodal line moved to Qwen2.5-VL-based nomic/colnomic-embed-multimodal 3B/7B (ColPali-style visual-document retrieval, Vidore-v2 58.8–62.7 NDCG@5).
- **nomic-embed-multimodal-3b license verified from the repo LICENSE file: Qwen Research License — "FOR NON-COMMERCIAL PURPOSES ONLY."** The 7B is Apache 2.0 but ~7 GB int8. Both disqualified.

### 5. Alibaba GME (gme-Qwen2-VL-2B-Instruct, Dec 2024) — strong EN+ZH text, too big
- 2.21B params, 1536-d, 32k tokens, dynamic-resolution images (≤1024 visual tokens, single image per input).
- **MTEB-en 65.27, MTEB-zh 66.92, UMRB 64.45** — the text side genuinely beats granite in both EN and ZH. But model card warns it was trained exclusively on English pairs; multilingual beyond EN/ZH not guaranteed.
- License: Apache 2.0 **plus mandatory "Built with GME" attribution** and naming clauses.
- Int8 ≈ **2.2 GB** — too big; decoder VLM with dynamic resolution has no Core ML evidence and is ANE-hostile. **Disqualified on size/runtime.**

### 6. Qwen3-VL-Embedding-2B (Jan 2026) — the best unified model, still phone-impossible
- **Apache 2.0 (clean, no attribution clauses)**, 2B params, MRL dims 64–2048, 32k context, 30+ languages incl. Chinese; text, images, screenshots, video, mixed inputs. Sister 8B ranks **#1 on MMEB-V2 (77.8)**; the 2B scores **73.2**.
- Text-only: HF card reports **MMTEB mean-task 63.87 / mean-type 55.84, with retrieval-type subscore 78.50** (task mix differs from the MTEB Multilingual Retrieval set behind granite's 60.3 — treat as directional). Directionally its text side sits at the level of dedicated ~0.6B text embedders, i.e., comfortably at or above the granite bar, while adding images.
- **This is the first unified model that plausibly beats granite on multilingual text-text under a permissive license.** But: 2B params → **~2 GB int8, ~1.1 GB int4** (3.5–7x the budget), iPhone-class RAM/latency for per-note embedding with a decoder VLM is impractical, and no Core ML/GGUF on-device port exists (dynamic vision token counts are hard to express in Core ML). **Disqualified on size; the one to watch for distillations.**

### 7. VLM2Vec / E5-V / mmE5 — research-scale, all too big
- VLM2Vec: Phi-3.5-V (4.2B) and Qwen2-VL-2B/7B variants (Apache 2.0), MMEB-focused, English-centric. Smallest is still ~2.2B.
- E5-V: LLaVA-NeXT-8B (~8.4B). mmE5: Llama-3.2-11B-Vision (11B, MIT). LLaVE-0.5B (Apache) is ~0.9B with English MMEB focus. **All disqualified on size and/or multilingual text-text.**

### 8. Marqo — wrong domain
- marqo-fashionCLIP (150M) / marqo-ecommerce-embeddings-B (~200M), Apache 2.0 — e-commerce/product CLIPs, English, CLIP-style text towers with no real text-text retrieval. **Disqualified.**

### 9. Small CLIP family (SigLIP2, MobileCLIP2, BGE-VL, Chinese-CLIP) — no text-text
- SigLIP2-base (~375M, Apache 2.0, multilingual t2i); Apple MobileCLIP2 (official Core ML support, superb ANE latency, English); BGE-VL base/large (149M/428M, MIT, composed-image-retrieval specialists). None has a text tower usable for note text-text retrieval — swapping granite for any of these would gut notes search. Useful only as a **second image-side model**, not as a replacement.

### 10. API-only (fails on-device): Gemini Embedding 2 (multimodal, 3072-d, MTEB Multilingual ~69.9, preview), Cohere Embed v4, Voyage multimodal-3. Not relevant.

### 11. IBM granite-vision-3.3-2b-embedding (Aug 2025): Apache 2.0 but ColPali-style **multi-vector** (729×128-d vectors per page, MaxSim late interaction) — incompatible with Noto's single dense index — and 2B. Not a CLIP-space image embedder.

## Comparison table (hard constraints)

| Model | Params / int8 size | Multilingual text-text vs granite 60.3 | Images | License | Fits ≤300 MB? | Verdict |
|---|---|---|---|---|---|---|
| granite-97m-r2 (today) | 97M / 94 MB | = (baseline) | no | Apache 2.0 | yes | keep |
| jina-clip-v2 | 865M / ~870 MB | likely ≥ (jina-v3-level tower) | yes, 89 langs | **CC-BY-NC-4.0** | no (3x) | fail: license+size |
| jina-v5-omni-nano / -small | 0.95B / ~1 GB; 1.57B / ~1.6 GB | ≥ (MMTEB 65.5 / 67.0 mean-task) | yes (+audio/video) | **CC-BY-NC-4.0** | no | fail: license+size |
| jina-embeddings-v4 | 3.8B / ~3.8 GB | ≥ | yes | **Qwen Research (NC)** | no | fail: all |
| nomic vision-v1.5 + text-v1.5 | 230M / ~230 MB | **far below (English-only)** | yes | Apache 2.0 | **yes** | fail: multilingual |
| nomic-embed-text-v2-moe | 475M | ≥ | **no vision tower exists** | Apache 2.0 | borderline | not unified |
| nomic-embed-multimodal-3b | 3B / ~3 GB | ≥ | yes (doc-style) | **Qwen Research (NC)** | no | fail: license+size |
| GME-Qwen2-VL-2B | 2.21B / ~2.2 GB | ≥ (MTEB-en 65.3 / -zh 66.9) | yes | Apache 2.0 + attribution | no (7x) | fail: size |
| **Qwen3-VL-Embedding-2B** | 2B / ~2 GB (int4 ~1.1 GB) | ≥ (MMTEB 63.9 mean-task) | yes (+video) | **Apache 2.0** | no (6x) | fail: size only |
| VLM2Vec / E5-V / mmE5 | 2.2–11B | mixed/English | yes | Apache/MIT | no | fail: size |
| Marqo, SigLIP2, MobileCLIP2, BGE-VL | 55–428M | no usable text-text | yes | Apache/MIT | yes | fail: text quality |

## Conclusion and forward paths

**Direct answer: no unified option ≤~400M params beats or matches granite on multilingual text-text while adding images.** The quality+license winner (Qwen3-VL-Embedding-2B) is 6x over budget and Core ML-hostile; everything phone-sized is either non-commercial (Jina) or English-only/text-blind (Nomic towers, CLIP family). Keep granite as the text model today.

Three paths worth tracking, in order of attractiveness:
1. **Build the aligned tower onto granite.** The jina-v5-omni/GELATO paper demonstrates that freezing the text tower and training only small projectors (~0.35% of weights) on a pre-trained vision encoder (they used SigLIP2-derived encoders) yields a shared space with zero text-text regression by construction. Granite (frozen, 384-d) + SigLIP2-base vision encoder (~92M ViT, Apache 2.0) + a trained projector would be ~190M added params (~190 MB int8, within budget) and both halves are Apache. This is a training project (needs multilingual image-caption pairs and contrastive alignment), not an integration, but it is the only route to the dream that satisfies every constraint today.
2. **Watch for sub-1B distillations of Qwen3-VL-Embedding** (Apache lineage, MRL, 30+ languages) — given the 2B/8B release cadence, a 0.6B-class variant or community distillation is plausible in 2026.
3. **Watch Jina licensing** — if v5-omni-nano (0.95B) ever ships under Apache or a paid app-embed license at sane cost, it is the best off-the-shelf fit architecturally, though still ~1 GB int8 (would need ~int4 and a raised budget).

Interim pragmatic option if image search is wanted sooner: keep granite for notes and add a separate small image-text model (dual index) — e.g., SigLIP2-base (multilingual t2i, Apache) or MobileCLIP2 (official Apple Core ML support, English queries only). This abandons the one-index goal but is shippable within ~100–200 MB.

**Key caveats:** (a) Benchmark task mixes differ — granite's 60.3 is MTEB Multilingual Retrieval; Jina's 69.85 and Qwen's 63.87/78.50 come from different task sets (paper-selected multilingual mix, MMTEB mean-task/retrieval-type respectively), so all cross-model text-text comparisons here are directional, not exact. (b) Int8-size estimates assume ~1 byte/param plus small overhead. (c) No Core ML conversion of any Qwen-VL-based embedding model was found; decoder VLMs with dynamic visual token counts are a poor fit for Core ML/ANE today, so even the int4 math understates the practical difficulty.

## Sources
https://huggingface.co/jinaai/jina-clip-v2
https://arxiv.org/html/2412.08802v1
https://jina.ai/news/jina-clip-v2-multilingual-multimodal-embeddings-for-text-and-images/
https://huggingface.co/jinaai/jina-embeddings-v4
https://arxiv.org/abs/2506.18902
https://arxiv.org/html/2605.08384v2
https://huggingface.co/jinaai/jina-embeddings-v5-omni-small
https://huggingface.co/jinaai/jina-embeddings-v5-omni-nano
https://huggingface.co/jinaai/jina-embeddings-v5-text-nano
https://www.elastic.co/search-labs/blog/jina-embeddings-v5-omni-all-media-one-index
https://huggingface.co/nomic-ai/nomic-embed-vision-v1.5
https://huggingface.co/nomic-ai/nomic-embed-text-v2-moe
https://huggingface.co/nomic-ai/nomic-embed-multimodal-3b
https://huggingface.co/nomic-ai/nomic-embed-multimodal-3b/blob/main/LICENSE
https://huggingface.co/nomic-ai/colnomic-embed-multimodal-7b
https://www.nomic.ai/news/nomic-embed-multimodal
https://huggingface.co/Alibaba-NLP/gme-Qwen2-VL-2B-Instruct
https://arxiv.org/abs/2412.16855
https://huggingface.co/Qwen/Qwen3-VL-Embedding-2B
https://arxiv.org/abs/2601.04720
https://www.alibabacloud.com/blog/qwen3-vl-embedding-and-qwen3-vl-reranker-for-the-next-generation-of-multimodal-retrieval_602796
https://arxiv.org/html/2410.05160v3
https://arxiv.org/pdf/2407.12580
https://huggingface.co/intfloat/mmE5-mllama-11b-instruct
https://tiger-ai-lab.github.io/VLM2Vec/
https://www.marqo.ai/blog/search-model-for-fashion
https://huggingface.co/Marqo/marqo-ecommerce-embeddings-B
https://huggingface.co/ibm-granite/granite-vision-3.3-2b-embedding
https://arxiv.org/abs/2504.10471
https://github.com/apple/ml-mobileclip
https://huggingface.co/google/siglip2-base-patch16-256
https://huggingface.co/BAAI/BGE-VL-large
https://huggingface.co/papers/2605.27295