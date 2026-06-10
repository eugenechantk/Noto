# deployment

## Summary
On-device CLIP-class deployment on iOS is proven and mature (Apple's own MobileCLIP CoreML models run 1.5–10.4 ms/image on an iPhone 12 Pro Max; Queryable ships CLIP photo search commercially), but the field has a hard constraint for Noto: every fast, Apple-built option (MobileCLIP v1/v2) is English-only and now license-encumbered (MobileCLIP2 and all current Apple HF PyTorch repos are research-only apple-amlr; the v1 CoreML repo's permissive apple-ascl tag points to a license file Apple replaced in Aug 2025). The only ready-made, Apache-2.0, multilingual (EN+ZH), CoreML-shipping image-text pair found is UForm3 multilingual (~198 MB quantized pair, 256-d, first-party Swift SDK); SigLIP2 is the quality winner on paper (Apache-2.0, multilingual) but has no public CoreML text encoder and its 256k-vocab text tower strains a 300 MB budget; jina-clip-v2 is CC-BY-NC (disqualified); nomic-embed-vision's aligned text space is English-centric. Apple provides no text-queryable image embedding API as of iOS 26/WWDC 2026 — VNGenerateImageFeaturePrintRequest is image-image only (768-d normalized since iOS 17), and WWDC 2026's Foundation Models image input is VLM understanding, not embeddings — which makes "Apple VLM captions image → granite embeds caption" a zero-new-model architecture that preserves today's EN+ZH cross-lingual bar. Swift tokenizer/preprocessing vendoring is a solved problem: Apple's own MobileCLIPExplore demo ships a complete MIT-licensed Swift CLIP BPE tokenizer, and Queryable/CLIP-Finder2 provide MIT MPSGraph preprocessing + tokenizer code; swift-transformers covers BERT/Unigram/BPE (UForm-compatible) but has no CLIPTokenizer registry entry.

## Findings
# On-Device CLIP-Class Embedding Models for iOS — Deployment Evidence (June 2026)

## 1. Apple's MobileCLIP CoreML artifacts (the strongest engineering evidence)

**Repo:** [apple/coreml-mobileclip](https://huggingface.co/apple/coreml-mobileclip) (1,091 downloads). Ships 8 `.mlpackage` files — image + text encoders for 4 variants (fp16, measured from the HF tree API):

| Variant | Image enc | Text enc | Pair total | Latency (img+txt, iPhone 12 Pro Max, iOS 17.0.3, coremltools 7.0) | IN-1k ZS |
|---|---|---|---|---|---|
| S0 | 21.7 MB | 80.9 MB | **102.6 MB** | 1.5 + 1.6 ms | 67.8% |
| S1 | 40.9 MB | 121.0 MB | 161.9 MB | 2.5 + 3.3 ms | 72.6% |
| S2 | 68.0 MB | 121.0 MB | **189.0 MB** | 3.6 + 3.3 ms | 74.4% |
| B-LT | 164.6 MB | 121.0 MB | 285.6 MB | 10.4 + 3.3 ms | 77.2% |

No tokenizer files in the HF repo — the tokenizer ships in the demo app (below). Latency numbers are Apple-published (README + [ml-mobileclip](https://github.com/apple/ml-mobileclip)).

**Apple's iOS demo app** (`ios_app/MobileCLIPExplore` in [apple/ml-mobileclip](https://github.com/apple/ml-mobileclip)): real-time zero-shot classification from camera, iOS 17.2+. Verified via repo tree that it ships a **complete vendorable Swift CLIP tokenizer**: `Tokenizer/CLIPTokenizer.swift`, `Tokenizer/GPT2ByteEncoder.swift`, `Resources/clip-vocab.json`, `Resources/clip-merges.txt`. CoreML models are downloaded separately into `Models/`. Code is MIT.

### The license problem (critical)
- **Verified via git history** (`gh api`): the weights license file `LICENSE_weights_data` created 2024-07-22 was **ASCL-style permissive** — "Apple grants you a personal, non-exclusive license… to use, reproduce, modify and redistribute the Apple Software, with or without modifications, in source and/or binary forms" — no commercial restriction.
- At the **MobileCLIP2 release (commit e15d36ef, 2025-08-29)** that file was replaced by `LICENSE_MODELS` = **Apple ML Research Model license: "exclusively for Research Purposes… does not include any commercial exploitation, product development or use in any commercial product or service"** ([current text](https://github.com/apple/ml-mobileclip/blob/main/LICENSE_MODELS)).
- All Apple HF PyTorch repos (MobileCLIP-S0…B, all MobileCLIP2-*) are now tagged **apple-amlr (research-only)**, confirmed on [apple/MobileCLIP-S2](https://huggingface.co/apple/MobileCLIP-S2) and [apple/MobileCLIP2-B LICENSE](https://huggingface.co/apple/MobileCLIP2-B/blob/main/LICENSE).
- [apple/coreml-mobileclip](https://huggingface.co/apple/coreml-mobileclip) still carries `license_name: apple-ascl` but its `license_link` points to the now-deleted `LICENSE_weights_data` (404). **Net: v1 CoreML weights were distributed under permissive terms Jul 2024–Aug 2025; current status is ambiguous and needs counsel before shipping.** Precedent (not clearance): Queryable ships MobileCLIP in a paid App Store app today.
- **MobileCLIP2** (better accuracy, S0 at 1.5+3.3 ms): research-only, **no Apple CoreML repo exists** (verified via HF API; only community [plhery/mobileclip2-onnx](https://huggingface.co/plhery/mobileclip2-onnx)). **Not shippable.**

### The multilingual problem (the real killer for Noto)
MobileCLIP v1/v2 are trained on DataCompDR/DFNDR (English-centric web data); model cards make no multilingual claim. **EN query → ZH note (or ZH query) would regress vs the granite bar.** MobileCLIP cannot be Noto's text tower for ZH.

## 2. Multilingual CLIP-class alternatives (license + CoreML status)

| Model | License | ZH? | CoreML available? | Size (quantized pair) |
|---|---|---|---|---|
| **UForm3 multilingual** ([unum-cloud/uform3-image-text-multilingual-base](https://huggingface.co/unum-cloud/uform3-image-text-multilingual-base)) | **Apache-2.0** | Yes (21 langs incl. Chinese) | **Yes, in-repo**: `image_encoder_neural.mlpackage` 86.6 MB + `text_encoder_neural.mlpackage` 111.2 MB (verified via tree API; fp32 variants 344/441 MB also present) + `tokenizer.json` 24 MB | **~198 MB** |
| SigLIP2-B/16 ([google/siglip2-base-patch16-224](https://huggingface.co/google/siglip2-base-patch16-224)) | Apache-2.0 | Yes (multilingual) | **Image encoder only**: [batmac/ViT-B-16-SigLIP2-Image-CoreML](https://huggingface.co/batmac/ViT-B-16-SigLIP2-Image-CoreML) (ANE-optimized, Apache-2.0, 15 downloads). **No public CoreML text encoder found** (verified author's model list + HF search) — DIY conversion required | text tower has 256k-vocab Gemma tokenizer → ~375M total params; int8 ≈ 375 MB — **over the 300 MB budget** without 4-bit embedding-table quantization |
| jina-clip-v2 ([jinaai/jina-clip-v2](https://huggingface.co/jinaai/jina-clip-v2)) | **CC-BY-NC-4.0 — disqualified** | Yes (89 langs) | No | — |
| nomic-embed-vision-v1.5 ([HF](https://huggingface.co/nomic-ai/nomic-embed-vision-v1.5)) | Apache-2.0 (relicensed from CC-BY-NC) | **No** — aligned to English nomic-embed-text-v1.5 space (multilingual nomic v2 is NOT aligned to vision) | No public CoreML found | 92M vision |

**UForm deployment evidence:** first-party Swift SDK ([unum-cloud/uform Swift README](https://github.com/unum-cloud/uform/blob/main/swift/README.md), iOS 16+, depends on a swift-transformers fork for tokenization — verified in Package.swift). Measured ANE text encoding 0.53 ms (english-small, M4 iPad). Demo app [ashvardanian/SwiftSemanticSearch](https://github.com/ashvardanian/SwiftSemanticSearch) does real-time text-to-image search with USearch ("scales even to 100M+ entries on an iPhone"). **Caveats:** 256-d embeddings, 50-token text limit, 224×224 input; retrieval quality is "tiny-model" tier (XTD-10 R@10 90.2–96.1; beats OpenCLIP on COCO-SM non-English but well below SigLIP2-class); check repo maintenance freshness before committing.

## 3. Real photo-search-at-scale evidence: Queryable & CLIP-Finder2

**[Queryable](https://github.com/mazzzystar/Queryable)** (MIT, paid App Store app — commercial CLIP-on-iOS precedent since 2023):
- Originally OpenAI CLIP ViT-B/32 (512-d, ~300 MB combined CoreML); **default switched to MobileCLIP-S2 on 2024-09-01**.
- Numbers from the [author's writeup](https://mazzzystar.com/2022/12/29/Run-CLIP-on-iPhone-to-Search-Photos/): indexing ~**2,000 photos/min on iPhone 12 mini**; query latency **<1 s under 10k photos, ~2.8 s at 35k** (brute-force scan — argues for an ANN index at vault scale); iOS 16+, A13 minimum.
- Vendorable Swift tokenizer verified in tree: `CLIP/Tokenizer/BPETokenizer.swift` + `merges.txt`/`vocab.json`.
- Lesson: "the export results of the ImageEncoder's Core ML have a certain level of precision error" — validate cosine-sim parity after conversion.

**[CLIP-Finder2](https://github.com/fguzman82/CLIP-Finder2)** (MIT): MobileCLIP-S0 CoreML on ANE; `CLIP_Tokenizer.swift` ported from open_clip + `bpe_simple_vocab_16e6.txt` (verified in tree); **GPU image preprocessing via MPSGraph** and MPSGraph dot-product similarity; indexes the photo library on ANE in **batches of 512**; includes per-compute-unit profiling. Companion conversion guide: [HF blog: From PyTorch to CoreML](https://huggingface.co/blog/fguzman82/frompytorch-to-coreml).

## 4. Swift tokenizer / preprocessing vendoring options (CoreML path, no MLX)
- **Apple MobileCLIPExplore** (MIT code): `CLIPTokenizer.swift` + `GPT2ByteEncoder.swift` + vocab/merges — best-quality CLIP BPE to vendor.
- **Queryable / CLIP-Finder2** (MIT): independent Swift CLIP BPE implementations + MPSGraph preprocessing.
- **[huggingface/swift-transformers](https://github.com/huggingface/swift-transformers)**: registry (verified in `Tokenizer.swift`) supports `BertTokenizer`, `BPETokenizer` (GPT2/Llama/Gemma/etc.), `UnigramTokenizer` (XLM-R), `T5Tokenizer` — **no `CLIPTokenizer` entry**, so OpenAI-CLIP-style models need a vendored tokenizer; UForm's BERT-style multilingual tokenizer IS covered (and UForm's SDK already wires it).
- Image preprocessing (resize/center-crop/normalize) — three proven approaches in the cited repos: MPSGraph (CLIP-Finder2), CoreML model-embedded preprocessing (Queryable), UForm SDK processor configs.

## 5. Apple platform APIs: no text-queryable image embeddings as of iOS 26 / WWDC 2026
- **[VNGenerateImageFeaturePrintRequest](https://developer.apple.com/documentation/vision/vngenerateimagefeatureprintrequest) / [VNFeaturePrintObservation](https://developer.apple.com/documentation/vision/vnfeatureprintobservation)** (iOS 13+/macOS 10.15+): exposes `data`, `elementCount`, `elementType`, `computeDistance(_:to:)`. Revision 1 (≤iOS 16 default): **2048-d non-normalized float**; Revision 2 (iOS 17+): **768-d normalized** ([MWM analysis](https://medium.com/@MWM.io/apples-vision-framework-exploring-advanced-image-similarity-techniques-f7bb7d008763)). **Image-image similarity only — Apple makes no text-alignment claim anywhere; you cannot embed a text query into this space.** Useful only for find-similar-image/dedup.
- **iOS 26 Vision additions (WWDC25)**: `RecognizeDocumentsRequest` (26-language document/text/table extraction — actually useful for OCRing images in notes into the existing granite text pipeline) and `DetectLensSmudgeRequest`. No embedding API. ([WWDC25 session 272](https://developer.apple.com/videos/play/wwdc2025/272/))
- **WWDC 2026 (June 2026)**: Foundation Models framework now **accepts image input** (on-device VLM understanding) and Apple announced a second, more capable on-device model for higher-end hardware ([Apple newsroom](https://www.apple.com/newsroom/2026/06/apple-unveils-next-generation-of-apple-intelligence-siri-ai-and-more/), [Callstack analysis](https://www.callstack.com/blog/on-device-ai-after-wwdc-2026-whats-new), [TechCrunch](https://techcrunch.com/2026/06/09/wwdc-2026-everything-announced-on-siri-ai-os-27-apple-intelligence-and-more/)). **Still no developer-facing image- or image-text-embedding API.** `NLContextualEmbedding` remains text-only.
- **Architecture implication for Noto**: the zero-new-model path is *Foundation Models VLM captions/describes the image → granite-97m embeds the caption text*. This adds 0 MB to the bundle, keeps the EN+ZH cross-lingual bar exactly where it is today (captions land in granite's multilingual space), at the cost of caption fidelity vs true CLIP-space retrieval and Apple-Intelligence-device gating.

## 6. Bottom line for Noto's constraints
1. **No off-the-shelf option matches granite's EN+ZH bar in CLIP space except UForm3 multilingual** (~198 MB CoreML pair, Apache-2.0, Swift SDK, ZH included) — but its retrieval quality is tiny-model tier; benchmark EN+ZH on your own data before committing.
2. **MobileCLIP v1 CoreML** is the best pure engineering artifact (Apple-converted, 1.5–10.4 ms, tokenizer included, 102–286 MB pairs) but is **English-only** and its license is now ambiguous (permissive 2024 terms vs Apple's 2025 research-only switch). MobileCLIP2: research-only, hard no.
3. **SigLIP2-B** is the quality+license winner on paper but requires DIY text-encoder CoreML conversion and aggressive quantization of its 256k-vocab embedding table to fit ~300 MB.
4. **Caption-with-Apple-VLM → granite** is the only path that adds zero bundle weight and provably preserves today's multilingual bar; treat CLIP-space search as an enhancement layered on top later.
5. Vision feature prints are free and instant but solve a different problem (visual dedup/similar-image), not text search.

## Sources
https://huggingface.co/apple/coreml-mobileclip
https://huggingface.co/apple/coreml-mobileclip/raw/main/README.md
https://huggingface.co/api/models/apple/coreml-mobileclip/tree/main?recursive=true
https://github.com/apple/ml-mobileclip
https://github.com/apple/ml-mobileclip/blob/main/LICENSE_MODELS
https://github.com/apple/ml-mobileclip/tree/main/ios_app
https://huggingface.co/apple/MobileCLIP-S2
https://huggingface.co/apple/MobileCLIP2-B/blob/main/LICENSE
https://huggingface.co/plhery/mobileclip2-onnx
https://machinelearning.apple.com/research/mobileclip
https://github.com/mazzzystar/Queryable
https://mazzzystar.com/2022/12/29/Run-CLIP-on-iPhone-to-Search-Photos/
https://apps.apple.com/us/app/queryable-photo-search-app/id1661598353
https://github.com/fguzman82/CLIP-Finder2
https://huggingface.co/blog/fguzman82/frompytorch-to-coreml
https://huggingface.co/Norod78/CoreML-MobileCLIP-S0
https://huggingface.co/batmac/ViT-B-16-SigLIP2-Image-CoreML
https://huggingface.co/google/siglip2-base-patch16-224
https://huggingface.co/blog/siglip2
https://huggingface.co/jinaai/jina-clip-v2
https://huggingface.co/nomic-ai/nomic-embed-vision-v1.5
https://huggingface.co/nomic-ai/nomic-embed-vision-v1.5/discussions/3
https://www.nomic.ai/news/nomic-embed-vision
https://huggingface.co/unum-cloud/uform3-image-text-multilingual-base
https://huggingface.co/api/models/unum-cloud/uform3-image-text-multilingual-base/tree/main?recursive=true
https://github.com/unum-cloud/uform
https://github.com/unum-cloud/uform/blob/main/swift/README.md
https://github.com/ashvardanian/SwiftSemanticSearch
https://github.com/huggingface/swift-transformers
https://github.com/huggingface/swift-transformers/blob/main/Sources/Tokenizers/Tokenizer.swift
https://github.com/ZachNagengast/similarity-search-kit
https://developer.apple.com/documentation/vision/vnfeatureprintobservation
https://developer.apple.com/documentation/vision/vngenerateimagefeatureprintrequest
https://medium.com/@MWM.io/apples-vision-framework-exploring-advanced-image-similarity-techniques-f7bb7d008763
https://developer.apple.com/videos/play/wwdc2025/272/
https://developer.apple.com/documentation/vision/recognizedocumentsrequest
https://www.apple.com/newsroom/2026/06/apple-unveils-next-generation-of-apple-intelligence-siri-ai-and-more/
https://www.callstack.com/blog/on-device-ai-after-wwdc-2026-whats-new
https://techcrunch.com/2026/06/09/wwdc-2026-everything-announced-on-siri-ai-os-27-apple-intelligence-and-more/
https://developer.apple.com/videos/play/wwdc2025/360/