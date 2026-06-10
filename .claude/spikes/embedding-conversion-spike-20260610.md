# Embedding Model Conversion Spike — Results

**Date:** 2026-06-10
**Question:** Can we convert `ibm-granite/granite-embedding-97m-multilingual-r2` to Core ML, and should it beat `intfloat/multilingual-e5-small` as Noto's semantic-search model?
**Verdict: YES on both. Ship granite-97m-r2, int8 variant, pinned to CPU+Neural Engine.**

---

## 1. Conversion outcome

| | granite-97m-r2 | multilingual-e5-small |
|---|---|---|
| Conversion | **Succeeded first approach** (torch.jit.trace, eager attention) | Trivial (plain BERT) |
| Interventions | `reference_compile=False`; additive-mask fill −1e4 instead of fp32-min (fp16/ANE overflow safety) | `torchscript=True` returns tuple → `out[0]` |
| Pooling (verified from repo) | **CLS + L2-norm, no prefixes** | masked-mean + L2-norm, `query:`/`passage:` prefixes required |
| Tokenizer | BPE, 180k vocab (`tokenizer.json` 24 MB) | SentencePiece Unigram, 250k vocab (17 MB) |

Both converted with pooling + L2-normalization **inside the graph**: input `input_ids`+`attention_mask` (int32, 1×512), output one normalized 384-d vector. iOS 17 deployment target (6-bit variants need iOS 18).

## 2. Numerical parity (58 fixture texts, cosine vs PyTorch fp32 reference)

| Variant | granite min/mean | e5 min/mean |
|---|---|---|
| fp16 | 0.999999 / 1.000000 | 0.999935 / 0.999954 |
| **int8** | **0.999734 / 0.999837** | 0.999789 / 0.999845 |
| 6-bit pgc | 0.998117 / 0.998815 (below target) | 0.998878 / 0.999148 (below target; skips embedding table → useless size-wise) |

## 3. Retrieval quality — the decisive result

Eval: 40 note-like passages (20 EN, 12 ZH, 4 JA, 4 mixed), 18 queries incl. 6 cross-lingual. `scripts/embedding-spike/eval.py`.

| Model/variant | hit@1 (all) | hit@5 | MRR | **cross-lingual hit@1** | xling hit@5 | mono hit@1 |
|---|---|---|---|---|---|---|
| **granite int8** | **0.89** | **1.00** | **0.944** | **0.67** | **1.00** | 1.00 |
| granite fp16 / fp32 ref | 0.89 | 1.00 | 0.944 | 0.67 | 1.00 | 1.00 |
| e5 int8 | 0.67 | 0.83 | 0.763 | **0.00** | 0.50 | 1.00 |
| e5 fp32 ref | 0.72 | 0.83 | 0.791 | 0.17 | 0.50 | 1.00 |

- **granite int8 = identical retrieval to its fp32 reference.** Quantization cost: zero on this eval.
- granite's only 2 misses are rank-2 near-ties between genuinely similar notes (ZH running log vs EN workout log; JA tax-prep note vs EN tax note) — acceptable behavior, hit@5 is perfect.
- e5 **fails the exact use case Eugene asked for**: English query → Chinese note ("rent increase negotiation with landlord" → 房东续租 ranked #12; "深蹲和卧推" → EN workout log ranked #12; US tax query #14). Monolingual is fine; cross-lingual is not.

## 4. Size & speed (M3 Max, macOS 26.5, seq 512, median of 30)

| Variant | Size | Latency (CPU+ANE) | Notes |
|---|---|---|---|
| granite fp16 | 186 MB | 13.6 ms (6.9 ms on GPU) | 462/473 ops ANE-resident |
| **granite int8** | **94 MB** | **13.4 ms** | avoid `ALL` (GPU dequant path 39 ms) |
| granite 6-bit | 72 MB | 13.9 ms | parity+quality drop; iOS 18 only; not worth −22 MB |
| e5 int8 | 113 MB | 13.7 ms | macOS 26.5 GPU **hard-crashes** on compressed weights → must pin CPU+ANE |

Seq-length scaling (measured on e5): 512→256 ≈ 3.5× faster (~4 ms). Enumerated shapes (256/512) is a cheap later optimization for short chunks.

## 5. Decision

**granite-embedding-97m-multilingual-r2, int8, `computeUnits = .cpuAndNeuralEngine`.**
Bundle cost: 94 MB model + 24 MB tokenizer.json ≈ **118 MB**. Apache-2.0. No prefix plumbing. CLS pooling.

e5-small remains the documented fallback but lost on the merits: worse cross-lingual retrieval (the feature's core multilingual requirement), bigger (113 MB + prefixes), no quality advantage anywhere.

## 5b. iOS runtime validation — PASSED on simulator (2026-06-10)

Ran the model on an **iPhone 16 Pro simulator (iOS 26.2)** via an XCTest harness (`scripts/embedding-spike/SimRunner/`): Xcode's resource pipeline compiled the `.mlpackage` → `.mlmodelc` at build time (the exact form it ships in inside the app bundle), the test loaded it with `.cpuAndNeuralEngine` and embedded 10 pre-tokenized EN/ZH/JA fixtures.

- **min cosine vs PyTorch fp32 reference: 0.999741** (≥ 0.999 target)
- **min cosine vs the Mac CoreML run: 0.999989** — iOS runtime is numerically identical
- Model load: 0.08 s. Latency: median 336 ms/inference — **simulator-only artifact** (no ANE, unoptimized CPU path); not representative of device. Real-device ANE expectation ~15–40 ms.
- Still pending: physical-device run (ANE latency + memory) — scheduled as part of Phase 2 verification.

## 6. Carry-forward notes for Phase 1/2
1. **Pin compute units to CPU+ANE** for the quantized model everywhere; the GPU path with compressed weights is broken on macOS 26.5 (e5 crashed; granite slow). Re-verify on-device iOS in Phase 2.
2. Swift tokenizer = **BPE** path of vendored swift-transformers Tokenizers (easier than e5's Unigram would have been). Port expected-ids fixtures from the Python tokenizer as the regression gate.
3. CLS pooling (not mean) — take `last_hidden_state[0]`… already inside the converted graph; Swift side just feeds ids+mask and reads the 384 vector.
4. Special tokens: CLS=`<|startoftext|>` (179934), SEP=`<|return|>` (179938), PAD=`<|endoftext|>` (179935).
5. Fixed 1×512 input: pad/truncate every chunk; consider enumerated 256/512 shapes later for latency.
6. If bundle size becomes a ship blocker: 6-bit (72 MB) exists but costs measurable quality; better lever is on-demand model download.

## 7. Artifacts
- **Converted model + tokenizer:** `.claude/spikes/artifacts/` (GraniteEmbed_int8.mlpackage 94 MB, tokenizer.json, configs) — local only, never commit.
- **Reproducible pipeline:** `scripts/embedding-spike/` (convert.py, reference.py, parity.py, quantize.py, measure.py, fixtures.json, eval.py). Venv recipe: python 3.12, torch 2.7.0, transformers 4.55.2, sentence-transformers 4.1.0, coremltools 9.0.
- **On-simulator validation harness:** `scripts/embedding-spike/SimRunner/` (XCTest package + wrapper workspace; copy the model from artifacts before running — see its README).
- Full per-track reports + all .npy embeddings + e5 packages: `/tmp/noto-embed-spike/{granite,e5}/REPORT.md` (tmp — will not survive reboot).
