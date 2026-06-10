#!/usr/bin/env python
"""PyTorch reference embeddings for granite-embedding-97m-multilingual-r2.

Encodes all fixture texts (40 passages + 18 queries) with sentence-transformers
at max_seq_length=512, producing L2-normalized 384-d vectors.

Pooling: CLS (per 1_Pooling/config.json: pooling_mode_cls_token=true)
Normalize: L2 (2_Normalize module)
Prefixes: NONE (config_sentence_transformers.json prompts: query="", document="")
"""
import json
import numpy as np
from sentence_transformers import SentenceTransformer

MODEL_DIR = "/tmp/noto-embed-spike/granite/model"
FIXTURES = "/tmp/noto-embed-spike/fixtures.json"
OUT_DIR = "/tmp/noto-embed-spike/granite"

def main():
    with open(FIXTURES) as f:
        fixtures = json.load(f)
    passages = [p["text"] for p in fixtures["passages"]]
    queries = [q["text"] for q in fixtures["queries"]]
    print(f"{len(passages)} passages, {len(queries)} queries")

    model = SentenceTransformer(MODEL_DIR, device="cpu")
    model.max_seq_length = 512  # match the fixed Core ML shape
    print("max_seq_length:", model.max_seq_length)

    ref_p = model.encode(passages, normalize_embeddings=True, batch_size=8,
                         convert_to_numpy=True, show_progress_bar=True)
    ref_q = model.encode(queries, normalize_embeddings=True, batch_size=8,
                         convert_to_numpy=True, show_progress_bar=True)
    print("passages:", ref_p.shape, "queries:", ref_q.shape)
    assert ref_p.shape == (40, 384) and ref_q.shape == (18, 384)
    # sanity: unit norms
    print("norms p:", np.linalg.norm(ref_p, axis=1).min(), np.linalg.norm(ref_p, axis=1).max())

    np.save(f"{OUT_DIR}/ref_passages.npy", ref_p.astype(np.float32))
    np.save(f"{OUT_DIR}/ref_queries.npy", ref_q.astype(np.float32))
    print("saved ref_passages.npy / ref_queries.npy")

if __name__ == "__main__":
    main()
