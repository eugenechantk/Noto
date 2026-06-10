# clipFamily

## Summary
FG-CLIP2-Base (qihoo360, Apache 2.0, 384M params, SigLIP2-B/16 towers @256px, Gemma-256k tokenizer, 64-token text, 768-d) is the clear winner for a multilingual (EN+ZH) text→image search leg: it beats SigLIP2-B on English retrieval (COCO T→I 54.5 vs 53.2) and crushes it on Chinese (COCO-CN T→I 62.9 vs 46.2), even beating Chinese-CLIP on its home benchmarks — at the same size as SigLIP2-B. It fits ~285 MB with int8 weights + 4-bit embedding-table palettization (the 197M-param 256k-vocab embedding dominates size; EN+ZH vocab pruning can cut another ~120M params). Apple MobileCLIP/MobileCLIP2 are the best English-only per-MB models with official CoreML + iOS demo, but are disqualified twice: English-only CLIP-BPE tokenizer (no ZH) and MobileCLIP2/current PyTorch weights are apple-amlr (research-only, explicitly no commercial products); only the v1 CoreML exports remain apple-ascl (permissive) with a now-dangling license link — legally murky. MetaCLIP2 and jina-clip-v2 are CC-BY-NC (excluded); mSigLIP-B (Apache, XM3600 T→I 50.0) is the fallback. SigLIP-family token limit is 64 (confirmed), ample for short queries. All SigLIP-family models use 256×256, /255, mean/std 0.5 preprocessing; ViT-B/16 @256 converts to CoreML (community SigLIP2 image-tower conversion exists) and is ANE-eligible at fp16 fixed shapes.

## Findings
## CLIP-family dual encoders for an image-only third search leg (EN+ZH text queries)

Scope: image index embedded by a CLIP image tower; queries embedded by the matching CLIP text tower. Granite keeps text→text. Requirements: permissive license, EN+ZH queries (cross-lingual), on-device Core ML, ≤~300 MB added, iPhone-class latency. Research date: 2026-06-10.

---

### 1. Apple MobileCLIP / MobileCLIP2 — best per-MB, but disqualified (license + English-only)

**Variants** (from [apple/ml-mobileclip](https://github.com/apple/ml-mobileclip) README; params = image + text, latency on iPhone 12 Pro Max via Core ML):

| Model | Img+Txt params | Latency (img+txt) | IN-1k ZS | Avg-38 |
|---|---|---|---|---|
| MobileCLIP-S0 (v1) | 11.4M + 42.4M | 1.5 + 1.6 ms | 67.8 | 58.1 |
| MobileCLIP-S1 (v1) | 21.5M + 63.4M | 2.5 + 3.3 ms | 72.6 | 61.3 |
| MobileCLIP-S2 (v1) | 35.7M + 63.4M | 3.6 + 3.3 ms | 74.4 | 63.7 |
| MobileCLIP-B(LT) (v1) | 86.3M + 63.4M | 10.4 + 3.3 ms | 77.2 | 65.8 |
| MobileCLIP2-S0 | 11.4M + 63.4M | 1.5 + 3.3 ms | 71.5 | 59.7 |
| MobileCLIP2-S2 | 35.7M + 63.4M | 3.6 + 3.3 ms | 77.2 | 64.1 |
| MobileCLIP2-B | 86.3M + 63.4M | 10.4 + 3.3 ms | 79.4 | 65.8 |
| MobileCLIP2-S3 | 125.1M + 123.6M | 8.0 + 6.6 ms | 80.7 | 66.8 |
| MobileCLIP2-L/14 | 304.3M + 123.6M | 57.9 + 6.6 ms | 81.9 | 67.8 |
| MobileCLIP2-S4 | 321.6M + 123.6M | 19.6 + 6.6 ms | 81.9 | 67.5 |

Architecture facts verified from the repo config (`mobileclip_s0.json`): embed_dim 512 (S-variants/B; 768 for S3/S4/L), image_size 256, **context_length 77, vocab 49408 = OpenAI CLIP BPE → English-only tokenizer. No multilingual variant exists.** Preprocessing for S0–B: 256×256, `image_mean (0,0,0), image_std (1,1,1)` (i.e. just /255); S3/S4/L-14 use default OpenCLIP (CLIP mean/std).

**License forensics (the important part):**
- HF API license tags today: `apple/MobileCLIP-S0`, `-S2` (v1 PyTorch) = **apple-amlr**; all `apple/MobileCLIP2-*` = **apple-amlr**.
- `LICENSE_MODELS` in the GitHub repo = **Apple Machine Learning Research Model License**: "Research Purposes … does not include any commercial exploitation, product development or use in any commercial product or service." → **cannot ship in Noto.**
- BUT [apple/coreml-mobileclip](https://huggingface.co/apple/coreml-mobileclip) (official Core ML exports of v1 S0/S1/S2/B-LT, image+text `.mlpackage` pairs) is tagged `license_name: apple-ascl` with `license_link` → `LICENSE_weights_data` on GitHub — **that file 404s today**. Git history shows `LICENSE_weights_data` was created 2024-07-22 and replaced in the 2025-08-29 "MobileCLIP2 release" commit. The original text (recovered at commit 341ef05) is an Apple Sample-Code-style grant: "use, reproduce, modify and redistribute the Apple Software, with or without modifications, in source and/or binary forms" — permissive, no NC clause, commercial OK. So v1 weights were originally permissive; Apple's current posture re-tags everything research-only, and only the CoreML repo still carries the permissive tag (untouched since Nov 2024).
- Net: MobileCLIP2 = hard no (AMLR). MobileCLIP v1 CoreML = arguably still ASCL-licensed, but the dangling link + retroactive re-tagging makes it a legal gray zone I would not ship on.
- **Either way both fail the ZH requirement** (English BPE tokenizer), so this family is out for this leg regardless. Worth keeping bookmarked: official iOS demo app (`ios_app/` MobileCLIPExplore, iOS 17.2+, real-time camera zero-shot at 2.1–13.7 ms ideal latency) is the best on-device CLIP deployment reference for the eventual implementation.
- No official MobileCLIP2 CoreML repo exists (searched; only v1 `apple/coreml-mobileclip`).

### 2. SigLIP / SigLIP2 (Google) — Apache 2.0, "multilingual" but English-leaning

- **License:** all `google/siglip2-*` and `google/siglip-*-multilingual` HF repos = **apache-2.0** (verified via HF API). Clean.
- **Sizes:** SigLIP2 ships B (86M vision), L (303M), So400m, g; FixRes (224/256/384/512) and NaFlex. **No variant smaller than B**, and the text tower is huge because of the **multilingual Gemma tokenizer, 256k vocab** (embedding table alone = 256k×768 ≈ 197M params). `google/siglip2-base-patch16-256` total = **375.2M params** (HF safetensors count). mSigLIP `google/siglip-base-patch16-256-multilingual` = **370.6M**.
- **Token limit confirmed: 64** for SigLIP, mSigLIP and SigLIP2 (paper: "we set the text length to 64", lowercased input). Fine for search queries (64 Gemma tokens ≈ 40+ English words; ZH ~1–2 chars/token ≈ 60+ characters).
- **Multilingual reality check** (SigLIP2 paper, [arXiv:2502.14786](https://arxiv.org/abs/2502.14786), Table 1 @256px): training mix is **90% English / 10% non-English**. XM3600 R@1 T→I / I→T: SigLIP B/16 22.4/29.3 → SigLIP2 B/16 **40.7/51.0** → **mSigLIP B/16 50.0/62.8**. So SigLIP2 is dramatically better than SigLIP1 multilingually but still ~9 pts behind mSigLIP T→I at base size; English: SigLIP2-B COCO T→I 53.2, IN-1k 79.1 (vs SigLIP-B 47.2/76.2; mSigLIP is notably weaker in English). No per-language ZH table in the paper text (Figure 2 only).
- **ZH specifically is SigLIP2-B's weakness** — from FG-CLIP2 paper baselines: SigLIP2-B COCO-CN T→I **46.2**, Flickr-CNA T→I **49.1** — far below Chinese-CLIP-B (54.9/62.4).
- **Preprocessing:** resize to 256×256 (no crop), rescale 1/255, normalize mean (0.5,0.5,0.5) std (0.5,0.5,0.5).
- **CoreML evidence:** community conversion exists — `batmac/ViT-B-16-SigLIP2-Image-CoreML` (image tower, apache-2.0) on HF. Standard ViT-B/16 @256 (257 tokens) converts with coremltools and is ANE-eligible at fp16 fixed shapes (Apple's ANE-transformers guidance applies). No official Google CoreML release.

### 3. FG-CLIP2 (Qihoo 360, Oct 2025) — the recommendation

- **What it is:** bilingual (EN+ZH) fine-grained CLIP, **initialized from SigLIP2 pre-trained weights**, same **Gemma 256k tokenizer**; base = ViT-B/16, hidden 768, **num_patches 256 → 256×256 input**, text `max_position_embeddings: 64` (long-caption mode 196 via `longtext_len`), projection/embedding dim **768** (verified from `config.json`).
- **License:** `qihoo360/fg-clip2-base` and `-large` = **apache-2.0** (HF API). Model card caveat: "datasets and checkpoints subject to their original licenses" — the init checkpoint is SigLIP2 (Apache 2.0), so the chain is clean. The Gemma *tokenizer* file is distributed inside Apache-2.0 SigLIP2/FG-CLIP2 repos (it is a sentencepiece model, not Gemma model weights, so Gemma ToU does not attach — but worth a one-time legal sanity check given your Gemma wariness).
- **Sizes:** base **383.8M params** total (HF safetensors); large 896.6M (over budget). Also a So400m variant.
- **Benchmarks** ([arXiv:2510.10921](https://arxiv.org/abs/2510.10921), Tables 3–4), base size, R@1 I→T / T→I:
  - English: COCO 72.1/**54.5** (SigLIP2-B: 69.7/53.2), Flickr30k 94.1/**81.9** (SigLIP2-B: 92.6/78.0). IN-1k ZS **79.5** (SigLIP2-B 79.1).
  - Chinese: COCO-CN 77.2/**62.9** vs Chinese-CLIP-B 68.8/54.9 and SigLIP2-B 68.5/46.2; Flickr-CNA 85.4/**69.9** vs Chinese-CLIP-B 75.8/62.4 and SigLIP2-B 71.7/49.1. (MUGE not reported; XM3600 not reported.)
  - i.e., at identical size/architecture to SigLIP2-B it is strictly better in English AND beats the Chinese-specialist model in Chinese — exactly the EN+ZH profile Noto needs. Larger variants: L/16 COCO T→I 58.6, COCO-CN T→I 66.5, IN-1k 83.1.
- **Budget math (base):** fp16 ≈ 768 MB (no), int8 ≈ 384 MB (over). Realistic plan: int8 everything + **4-bit palettization of the 197M-param embedding table** → ≈ 87 (vision) + 95 (text non-embedding) + ~98 (embedding @4-bit) ≈ **~280–285 MB** — inside budget. Further option: **EN+ZH vocab pruning** of the 256k sentencepiece vocab (text tower only runs on short user queries, so this is easy to validate) — pruning to ~100k tokens removes ~120M params → ~160–225 MB total depending on precision. The per-photo indexing cost is only the **image tower ≈ 87 MB int8 / 174 MB fp16**.
- **Deployment caveats:** custom `Fgclip2Model` (`trust_remote_code` HF implementation) — no official CoreML/ONNX; conversion is DIY but the towers are vanilla SigLIP2 (ViT + transformer encoder), and the batmac SigLIP2 CoreML conversion is an existence proof. Vendor the Gemma sentencepiece tokenizer (swift-transformers handles sentencepiece). Use fixed 256×256 (config's data-adaptive resolutions {128…1024} are a training detail; base eval config pins 256 patches). Business-risk footnote: Qihoo 360 is a US Entity List company — that restricts exports *to* them, not your use of their Apache weights, but worth noting for App Review/optics.

### 4. Other multilingual options (mostly excluded)

| Model | License | Params | EN+ZH verdict |
|---|---|---|---|
| mSigLIP B/16-256 (`google/siglip-base-patch16-256-multilingual`) | apache-2.0 | 370.6M | Best XM3600 in SigLIP1 family (T→I 50.0); WebLI w/o language filter; 64 tokens; viable **fallback**, but weaker English than SigLIP2/FG-CLIP2 and 2023-era |
| Chinese-CLIP ViT-B/16 (OFA-Sys) | MIT (GitHub; HF tag missing) | ~188M (ViT-B/16 @224 + Chinese BERT vocab 21128, proj 512) | ZH-only text encoder → EN queries fail; dual-model/dual-index hack rejected (two embedding spaces, 2× image indexing) |
| MetaCLIP 2 "worldwide" (Meta, 2025; incl. s16 small 389.7M) | **cc-by-nc-4.0** | 390M–2B | SOTA multilingual (XM3600 64.3 I→T for H/14, beats mSigLIP) but **NC → excluded** |
| jina-clip-v2 (multilingual, 89 langs) | **cc-by-nc-4.0** | 865M | NC → excluded |
| visheratin/mexma-siglip2 | MIT tag | 1.0B | Too big; underlying MEXMA encoder is Meta CC-BY-NC — license chain suspect |
| AltCLIP (BAAI, EN+ZH bilingual) | apache-ish | ~860M (XLM-R-L text) | Too big, 2022-era, superseded by FG-CLIP2 |
| M-CLIP (multilingual-clip) | MIT | XLM-R-Large text (560M) | Text tower alone blows budget; 2022-era |
| TinyCLIP (microsoft/Cream) | MIT | 8–60M towers | English-only, no ZH → out (would otherwise be the per-MB floor) |

### Answers to the three key questions

1. **Best multilingual text→image per MB:** **FG-CLIP2-Base** — at ~280 MB (int8 + 4-bit embedding) it delivers the best published EN AND ZH retrieval at base size; nothing permissively licensed is both smaller and multilingual (the 256k-vocab embedding puts a ~370–384M floor under every multilingual SigLIP-family model; everything genuinely small — MobileCLIP, TinyCLIP — is English-only or research-licensed). Fallbacks in order: SigLIP2-B/16-256 (battle-tested HF official, but ZH T→I drops ~14–21 pts), mSigLIP-B-256.
2. **Token limits:** SigLIP/SigLIP2/mSigLIP/FG-CLIP2 = **64 tokens confirmed** (FG-CLIP2 has a 196-token long-caption mode); CLIP/MobileCLIP = 77. Search queries are typically <15 tokens — 64 is ample, including ZH (Gemma sentencepiece covers Chinese natively; input is lowercased).
3. **Preprocessing & ANE:** SigLIP-family (incl. FG-CLIP2-base): resize to **256×256** (plain resize, no crop), /255, normalize mean=std=0.5 → x∈[−1,1]; fixed input shape. ViT-B/16 @256 (257 tokens) is ANE-compatible when converted to fp16 mlpackage with fixed shapes (community SigLIP2-B image-tower CoreML conversion exists; Apple's ANE-transformer guidance applies; expect tens of ms per image on A17/A18-class ANE — estimate, must be benchmarked). MobileCLIP's FastViT hybrids remain the gold standard for ANE CLIP (1.5–10 ms official numbers) but are unusable here for license+language reasons.

### Caveats
- SigLIP2-B XM3600 figures appeared as 40.3/50.7 in one render and 40.7/51.0 in another (table version drift in the arXiv HTML); directionally identical.
- FG-CLIP2 has no official mobile/CoreML artifacts, no XM3600/MUGE numbers, and a `trust_remote_code` implementation — conversion and a small EN/ZH retrieval eval on your own photo set are the validation steps before committing.
- ANE residency and real latency for the FG-CLIP2 image tower are projected, not measured — benchmark the converted mlpackage with `MLComputeUnits.all` before sizing the indexing pipeline.
- Apple ASCL-vs-AMLR situation could change again; if MobileCLIP2 is ever re-licensed permissively (or a multilingual MobileCLIP appears), it would instantly become the better-engineered choice for the image tower.

## Sources
https://github.com/apple/ml-mobileclip
https://huggingface.co/apple/coreml-mobileclip
https://huggingface.co/apple/MobileCLIP2-S0
https://huggingface.co/apple/MobileCLIP-S2
https://raw.githubusercontent.com/apple/ml-mobileclip/main/LICENSE_MODELS
https://raw.githubusercontent.com/apple/ml-mobileclip/341ef058802f0e4e5ab13c02f0cb32a3a94e367b/LICENSE_weights_data
https://github.com/apple/ml-mobileclip/blob/main/ios_app/README.md
https://github.com/apple/ml-mobileclip/blob/main/mobileclip/configs/mobileclip_s0.json
https://arxiv.org/abs/2502.14786
https://arxiv.org/html/2502.14786v1
https://huggingface.co/google/siglip2-base-patch16-256
https://huggingface.co/google/siglip-base-patch16-256-multilingual
https://huggingface.co/blog/siglip2
https://huggingface.co/qihoo360/fg-clip2-base
https://huggingface.co/qihoo360/fg-clip2-base/resolve/main/config.json
https://github.com/360CVGroup/FG-CLIP
https://arxiv.org/abs/2510.10921
https://arxiv.org/html/2510.10921v1
https://huggingface.co/facebook/metaclip-2-worldwide-s16-384
https://huggingface.co/papers/2507.22062
https://github.com/facebookresearch/metaclip
https://huggingface.co/jinaai/jina-clip-v2
https://huggingface.co/visheratin/mexma-siglip2
https://github.com/OFA-Sys/Chinese-CLIP
https://huggingface.co/OFA-Sys/chinese-clip-vit-base-patch16
https://github.com/microsoft/Cream
https://huggingface.co/batmac/ViT-B-16-SigLIP2-Image-CoreML
https://machinelearning.apple.com/research/neural-engine-transformers