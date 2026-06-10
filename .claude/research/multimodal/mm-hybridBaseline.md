# hybridBaseline

## Summary
For a vault dominated by screenshots/whiteboards/receipts, the OCR+labels+caption-as-text baseline captures most of the retrieval value, and a true image-embedding leg adds only modest, photo-concentrated gains. Apple gives the text leg away free: VNRecognizeTextRequest/RecognizeTextRequest OCR (~18-26 languages incl. zh-Hans/zh-Hant), the new iOS 26 RecognizeDocumentsRequest (structured documents, tables, lists, 26 languages), and VNClassifyImageRequest (1,303-label taxonomy) — 0 MB of bundle, and the output flows into the already-shipped granite multilingual embedder, preserving today's EN↔ZH cross-lingual behavior. Published evidence cuts both ways but favors captions at phone scale: caption-then-text-embed beat CLIP/SigLIP image embeddings on personal lifelog retrieval (P@10 0.73 vs 0.58, CIVIL 2025), MIEB shows CLIP-style models are systematically weak exactly on visual-text (screenshots) and multilingual tasks, while ColPali-style vision-native retrieval beats OCR pipelines (nDCG@5 81.3 vs ~66) only with ~3B late-interaction models that are far beyond a 300 MB phone budget. Contextual chunk headers (note title/section + alt text prepended to OCR/caption before embedding) have strong text-RAG evidence (35-49% retrieval-failure reduction, Anthropic). Licensing is the landmine: Apple's FastVLM and MobileCLIP2 are research-only (apple-amlr) — unusable; viable captioners are SmolVLM2-256M/500M (Apache 2.0, fits ~300 MB at int4), Florence-2 (MIT, 0.23B, English-only), Moondream 2 (Apache; Moondream 3 is BSL 1.1), Granite Vision 3.3-2B and Qwen3-VL-2B (Apache but >300 MB quantized). 1-5 s/image one-time captioning is realistic (FastVLM-0.5B shows <120 ms TTFT on iPhone 16 Pro; SmolVLM2-500M runs on-iPhone), though pure-Core-ML (non-MLX) VLM deployment is real engineering work. Big new development: WWDC26 (this week) announced image input for the Foundation Models framework in iOS 27 (fall 2026, iPhone 15 Pro+, AFM "Core Advanced"), plus a built-in Vision-backed OCRTool — a zero-bundle-cost captioner that strongly argues for building the caption/OCR text pipeline now and swapping in Apple's model later.

## Findings
# Caption/OCR Baseline vs True Image Embeddings for Noto Image Search (June 2026)

## 1. Apple's free building blocks (0 MB bundle cost)

### OCR: RecognizeTextRequest / VNRecognizeTextRequest
- Language coverage as of iOS 18+: en-US, fr-FR, it-IT, de-DE, es-ES, pt-BR, **zh-Hans, zh-Hant, yue-Hans, yue-Hant**, ko-KR, ja-JP, ru-RU, uk-UA, th-TH, vi-VT, ar-SA, ars-SA — i.e., both Simplified and Traditional Chinese are first-class ([Apple docs — recognitionLanguages](https://developer.apple.com/documentation/vision/vnrecognizetextrequest/recognitionlanguages), [Apple dev forums language thread](https://developer.apple.com/forums/thread/121048)). Use `.accurate` recognition level; query `supportedRecognitionLanguages` at runtime since the list grows by OS revision.
- Quality: head-to-head on-device comparisons (Apple Vision vs Google ML Kit) find Apple Vision competitive-to-better on printed text on iOS ([bitfactory blog](https://www.bitfactory.io/de/dev-blog/comparing-on-device-ocr-frameworks-apple-vision-and-google-mlkit/)); cloud engines (GCP ~98% on clean print) remain the ceiling but are irrelevant under the on-device constraint ([aimultiple OCR benchmark](https://aimultiple.com/ocr-accuracy)). Caveat: no rigorous public 2025/2026 accuracy benchmark of Apple OCR on zh-Hans specifically was found; whiteboard handwriting is the known weak spot for every on-device OCR (Live Text handles neat handwriting, messy marker text degrades — flagged as training-knowledge, not a benchmarked claim).

### iOS 26: RecognizeDocumentsRequest — it exists and is a real upgrade
- New in iOS 26 (WWDC25 session 272, "Read documents using the Vision framework"). Produces a `DocumentObservation`: text grouped into **paragraphs, tables, lists**, detected machine-readable codes (QR), and auto-detected data (emails, phone numbers, URLs) ([Apple docs](https://developer.apple.com/documentation/vision/recognizedocumentsrequest), [WWDC25 272](https://developer.apple.com/videos/play/wwdc2025/272/)).
- Recognizes text in **26 languages**; Chinese is included for recognition, with the caveat that individual word extraction is not supported for Chinese/Japanese/Korean/Thai (line/paragraph level only) — fine for embedding purposes.
- This is precisely the right API for the receipts/whiteboards/screenshots vault profile: table structure from receipts and list structure from whiteboards become clean markdown-ish text for the existing granite embedding leg.

### Labels: VNClassifyImageRequest
- Taxonomy of **1,303 labels** (hierarchical; revision 1 list published) with per-class precision/recall filtering ([Apple docs](https://developer.apple.com/documentation/vision/vnclassifyimagerequest), [full identifier list gist](https://gist.github.com/ktustanowski/56c0d7541813868fed4aceb60ab5d149)). Quality is coarse, English-only labels ("whiteboard", "receipt", "document", "dog") — but English labels are fine because granite's cross-lingual embedding maps a ZH query onto EN label text, which is exactly the behavior Noto already relies on.

### VisionKit ImageAnalyzer + misc
- `ImageAnalyzer` (iOS 16+) provides Live-Text-grade text transcripts, subject extraction, and machine-readable codes programmatically; Visual Look Up results (landmark/pet/plant identification) are **not** exposed as data to third-party apps, only via the user-facing overlay ([Apple docs](https://developer.apple.com/documentation/visionkit/imageanalyzer) — page is JS-rendered; this characterization is from training knowledge and should be re-verified in Xcode). For an indexing pipeline, Vision's `RecognizeTextRequest`/`RecognizeDocumentsRequest` are the right APIs anyway; ImageAnalyzer is the interactive-UI wrapper.
- `VNGenerateImageFeaturePrintRequest` gives a free image→image similarity vector (no text tower, so no text queries) — zero-cost "find visually similar images," useful as a freebie but not a substitute for either leg.

### The big new thing: WWDC26 (June 8, 2026) — iOS 27 Foundation Models go multimodal
- Apple announced **image input for the Foundation Models framework**: pass `UIImage`/`CGImage`/pixel buffers/file URLs as prompt attachments to the on-device model ([MacRumors, June 8 2026](https://www.macrumors.com/2026/06/08/apple-unveils-xcode-and-models-improvements/), [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/), [byteiota write-up](https://byteiota.com/apple-foundation-models-wwdc-2026-multimodal-python-sdk/)).
- Per the byteiota analysis: image input requires the new "AFM 3 Core Advanced" (~20B sparse MoE, 1-4B active), **iPhone 15 Pro or newer**, shipping with iOS 27 in fall 2026. Also new: built-in **OCRTool** (Vision-backed), BarcodeReaderTool, and a Spotlight-backed local-RAG search tool. Caveat: byteiota is a secondary source; device floor and model details should be re-verified against Apple's session before planning on them.
- Implication: a **zero-bundle-MB on-device captioner** lands for third-party apps in ~3 months on recent hardware. This heavily favors architecting the index around "image → text fields → granite embedding" now, with the captioner as a swappable component (Vision OCR + labels today, Apple FM captions on iOS 27 devices later, vendored small VLM only if needed).

## 2. Small VLM captioners at phone scale (and the license minefield)

| Model | Size | License | Verdict for a paid App Store app |
|---|---|---|---|
| **FastVLM (Apple)** 0.5B/1.5B/7B | 0.5B int8 ≈ 600 MB; TTFT **<120 ms on iPhone 16 Pro** (0.5B) | **apple-amlr — research only**: "exclusively for Research Purposes… does not include any commercial exploitation, product development or use in any commercial product or service" ([HF LICENSE](https://huggingface.co/apple/FastVLM-0.5B/blob/main/LICENSE)) | **Disqualified.** Painful, because it's the speed/quality reference point ([Apple ML research](https://machinelearning.apple.com/research/fast-vision-language-models)) |
| **MobileCLIP2 (Apple)** | S0-L | also **apple-amlr** ([HF](https://huggingface.co/apple/MobileCLIP2-S0)) | Disqualified — and it would have been the obvious CLIP leg |
| **SmolVLM2** 256M / 500M / 2.2B | 500M ≈ 250-300 MB at int4; 256M ≈ ~150 MB | **Apache 2.0** ([HF blog](https://huggingface.co/blog/smolvlm2), [model card](https://huggingface.co/HuggingFaceTB/SmolVLM2-500M-Video-Instruct)) | **Best fit for the ≤300 MB budget.** Runs on iPhone (HF shipped an on-device iPhone app on the 500M); decode ~2-3k tok/s on M-class Macs; captions are English-centric |
| **Florence-2 (Microsoft)** 0.23B / 0.77B | base ≈ 120-230 MB quantized | **MIT** ([HF model card](https://huggingface.co/microsoft/Florence-2-base)) | License-clean and has CAPTION/DETAILED_CAPTION + OCR modes; English-only output; 2024-era quality; encoder-decoder architecture converts to Core ML more easily than chat VLMs |
| **Moondream 2** ~1.9B | ~1-1.2 GB int4 | Apache 2.0 ([GitHub](https://github.com/vikhyat/moondream/blob/main/LICENSE)) | License OK, size over budget |
| **Moondream 3 preview** 9B MoE | too big anyway | **BSL 1.1** with no-third-party-service grant ([HF LICENSE](https://huggingface.co/moondream/moondream3-preview/blob/main/LICENSE.md)) — embedding in a paid product that overlaps M87's paid offering is restricted | Avoid: both size and license ambiguity for a paid app |
| **Granite Vision 3.3-2B (IBM)** | ~1.5-2 GB int4 | **Apache 2.0**, explicitly commercial ([HF](https://huggingface.co/ibm-granite/granite-vision-3.3-2b)) | Document/chart/table-understanding specialist — thematically perfect for this vault and same vendor as the shipped embedder, but ~5-7x over the bundle budget |
| **Qwen3-VL-2B** (Oct 2025) | ≥3 GB RAM to run | Apache 2.0 ([GitHub](https://github.com/QwenLM/Qwen3-VL)) | Strong multilingual (incl. ZH) captions; over budget for bundling, plausible as an optional download |

**Is 1-5 s/image one-time captioning practical on iPhone?** Yes, with headroom. FastVLM-0.5B demonstrates the encode side at <120 ms TTFT on iPhone 16 Pro; a 500M-class decoder producing a 50-80-token caption lands roughly in the 1-3 s range on A17/A18-class silicon (decode-rate figures at phone scale are mostly published for MLX, not Core ML — treat as estimate). At index time, batched while charging, even 5 s/image clears a 2,000-image vault overnight. **The real cost is engineering, not latency:** community phone deployments of all of these run on MLX or llama.cpp, not Core ML. Pure-Core-ML VLM inference (stateful KV-cache models, iOS 18+) is proven by Apple's own demos but is a custom conversion project per model. Vision OCR + classify, by contrast, are one-line API calls.

## 3. Caption-then-text-embed vs CLIP-style direct embedding — what's published

**Pro-caption (personal photo / lifelog domain — closest to Noto's use case):**
- **CIVIL** (arXiv 2510.04010, lifelog retrieval): caption-then-text-embed achieved **P@10 0.73** (best: InternLM-XComposer2-VL-7B captions + GTE-large embeddings; LLaVA-NeXT-7B + BGE-M3 hit 0.71) vs **0.58** for the strongest direct image-embedding baselines (ViT-SO400M-SigLIP-384, DFN5B-CLIP-ViT-H-14). A 15-point P@10 gap **in favor of captions** on first-person personal images ([arXiv](https://arxiv.org/abs/2510.04010)). Caveat: captioners used were 7B-class, larger than anything Noto can ship; smaller captioners will give thinner captions.
- **SSE** (arXiv 2409.13860): caption-based semantic embeddings retrieve semantically-similar-but-visually-diverse scenes that CLIP embeddings miss (abstract queries like "slow down and drive carefully"), while CLIP confuses visually different/semantically adjacent items ([arXiv](https://arxiv.org/pdf/2409.13860)).
- **MIEB** (arXiv 2504.10471, 130 tasks, 38 languages): CLIP-style models are systematically **weak on visual-text representation and multilingual tasks** — exactly Noto's two stress points (screenshots + EN/ZH). The models that do well on OCR-heavy/multilingual embedding tasks are MLLM-based embedders (E5-V, Voyage multimodal) that are server-scale ([arXiv](https://arxiv.org/abs/2504.10471), [HF blog](https://huggingface.co/blog/isaacchung/introducing-mieb)).

**Pro-vision-embedding (visually-rich document domain):**
- **ColPali** (ICLR 2025): on ViDoRe (PDF-page retrieval: charts, infographics, tables), vision-native late-interaction retrieval scores **nDCG@5 81.3 vs ~65-66** for OCR+BM25/BGE-M3 pipelines — up to +29% on the most visual subsets; its captioning baseline helped on figures but still trailed the vision model ([arXiv](https://arxiv.org/abs/2407.01449), [Vespa analysis](https://blog.vespa.ai/the-rise-of-vision-driven-document-retrieval-for-rag/)). **Critical caveat:** ColPali is a ~3B PaliGemma derivative emitting ~1,000 multi-vectors per page — nothing in this family fits 300 MB or iPhone latency, and the gap is driven by chart/figure-heavy queries, not the receipt/screenshot text that dominates Noto's vault. Smaller single-vector CLIP models do *not* inherit this advantage (per MIEB's visual-text findings).
- Screenshots specifically: text extracted from smartphone screenshots is dense, retrieval-bearing content; OCR-based indexing of screenshots was shown viable as the primary retrieval signal back in 2018 ([arXiv 1801.01316](https://arxiv.org/abs/1801.01316)).

**Net reading:** for text-bearing images (screenshots, receipts, documents, most whiteboards), OCR-as-text beats phone-scale CLIP; for natural photos, caption-then-embed at least matches and (with good captioners) beats phone-scale CLIP; vision-native retrieval only decisively wins at model scales Noto cannot ship.

## 4. The contextual chunk header angle

- Anthropic's contextual retrieval: prepending ~50-100 tokens of document context to each chunk before embedding cut top-20 retrieval failure by **35%** (embeddings only, 5.7%→3.7%) and **49%** combined with contextual BM25 (5.7%→2.9%) ([Anthropic](https://www.anthropic.com/news/contextual-retrieval)).
- dsRAG's "Contextual Chunk Headers" (document title + section header prepended pre-embedding) reports substantial retrieval-quality gains and fewer irrelevant hits ([RAG_Techniques notebook](https://github.com/NirDiamant/RAG_Techniques/blob/main/all_rag_techniques/contextual_chunk_headers.ipynb)).
- No published study tests this *specifically* for images in note-taking apps — that's a gap, flag it as inference. But the mechanism transfers directly: an image embedded as `"[note title] > [section heading] — [user alt text/filename] — [VN labels] — [caption] — [OCR text]"` is a contextual-chunk-header construction. In a notes vault the surrounding prose usually states what the image *is for* ("受け取った領収書", "sprint 12 whiteboard"), which is higher-precision than anything a 500M captioner produces. This composite-text approach also keeps every image query inside granite's embedding space — preserving the EN↔ZH cross-lingual guarantee, which a separate CLIP leg (77-token English-biased text tower) would regress on.

## 5. Conclusion: how much does a true image-embedding leg add for THIS vault?

For a vault dominated by screenshots, whiteboards, and receipts plus some photos: **not much — the text pipeline is the main course, the CLIP leg is a garnish.**

- **Screenshots/receipts/documents (the majority):** retrieval-bearing content is the text *in* the image. Apple OCR (free, 26 languages, zh included, table/list structure on iOS 26) feeds it straight into the granite index. MIEB shows phone-scale CLIP models are at their *worst* on exactly this content; ColPali-scale vision retrieval that does win here is 10-20x over budget. Expected CLIP-leg uplift: **near zero, possibly negative** (visual matches on UI chrome instead of content).
- **Whiteboards:** OCR quality on marker handwriting is the weak link, and that hurts both legs equally (CLIP can't read either). Captions ("whiteboard with flow diagram") + note-context headers carry these; a CLIP leg adds little beyond "looks like a whiteboard."
- **Photos (the minority):** this is where a true image-embedding leg earns its keep — uncaptioned visual attributes (color, composition, "that sunset shot", a specific object a thin caption omitted) and image→image queries. But the best published personal-photo evidence (CIVIL: 0.73 vs 0.58 P@10) says even here, caption-then-embed *outperforms* CLIP/SigLIP-class embeddings when captions are decent. With a 500M captioner the gap will shrink, so a realistic estimate is the CLIP leg adds **single-digit recall points overall, concentrated in the photo minority** — versus a license-clean OCR+labels+caption pipeline that costs 0-300 MB and inherits multilingual behavior for free.
- **Recommended posture:** ship OCR (RecognizeDocumentsRequest on iOS 26, RecognizeTextRequest fallback) + VNClassifyImageRequest labels + contextual headers into the existing granite index now at 0 MB; treat captioning as a swappable enrichment (SmolVLM2-500M/Florence-2 if shipping a captioner this year; Apple Foundation Models image input on iOS 27/iPhone 15 Pro+ this fall for free); defer the CLIP leg, and if added later use a permissive multilingual model (SigLIP 2-class, Apache) — Apple's MobileCLIP2 is research-only and unusable.

**Key caveats:** (1) no public benchmark measures Apple Vision OCR accuracy on zh-Hans receipts/whiteboards — worth a 50-image internal eval before committing; (2) CIVIL/SSE used 7B captioners, so caption-leg quality at 500M is unproven — pilot on the actual vault; (3) iOS 27 Foundation Models specifics (device floor, caption quality, rate limits) are from week-one secondary coverage and need verification against Apple docs; (4) "Core ML only" makes any vendored VLM a real conversion project — the zero-code Vision APIs are the only truly free lunch.

## Sources
https://developer.apple.com/documentation/vision/recognizedocumentsrequest
https://developer.apple.com/videos/play/wwdc2025/272/
https://developer.apple.com/documentation/vision/vnrecognizetextrequest/recognitionlanguages
https://developer.apple.com/forums/thread/121048
https://developer.apple.com/documentation/vision/vnclassifyimagerequest
https://gist.github.com/ktustanowski/56c0d7541813868fed4aceb60ab5d149
https://developer.apple.com/documentation/visionkit/imageanalyzer
https://www.bitfactory.io/de/dev-blog/comparing-on-device-ocr-frameworks-apple-vision-and-google-mlkit/
https://aimultiple.com/ocr-accuracy
https://huggingface.co/apple/FastVLM-0.5B/blob/main/LICENSE
https://machinelearning.apple.com/research/fast-vision-language-models
https://huggingface.co/apple/MobileCLIP2-S0
https://huggingface.co/blog/smolvlm2
https://huggingface.co/HuggingFaceTB/SmolVLM2-500M-Video-Instruct
https://huggingface.co/microsoft/Florence-2-base
https://github.com/vikhyat/moondream/blob/main/LICENSE
https://huggingface.co/moondream/moondream3-preview/blob/main/LICENSE.md
https://huggingface.co/ibm-granite/granite-vision-3.3-2b
https://github.com/QwenLM/Qwen3-VL
https://arxiv.org/abs/2510.04010
https://arxiv.org/pdf/2409.13860
https://arxiv.org/abs/2504.10471
https://huggingface.co/blog/isaacchung/introducing-mieb
https://arxiv.org/abs/2407.01449
https://blog.vespa.ai/the-rise-of-vision-driven-document-retrieval-for-rag/
https://arxiv.org/abs/1801.01316
https://www.anthropic.com/news/contextual-retrieval
https://github.com/NirDiamant/RAG_Techniques/blob/main/all_rag_techniques/contextual_chunk_headers.ipynb
https://www.macrumors.com/2026/06/08/apple-unveils-xcode-and-models-improvements/
https://developer.apple.com/videos/play/wwdc2026/241/
https://byteiota.com/apple-foundation-models-wwdc-2026-multimodal-python-sdk/