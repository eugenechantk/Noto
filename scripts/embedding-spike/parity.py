#!/usr/bin/env python
"""Parity check: run a Core ML .mlpackage over all 58 fixture texts and compare
per-text cosine similarity against the PyTorch reference embeddings.

Usage: python parity.py <mlpackage_path> <variant_tag>
  e.g. python parity.py GraniteEmbed_fp16.mlpackage fp16
Saves coreml_<tag>_passages.npy / coreml_<tag>_queries.npy and prints min/mean cosine.
"""
import json
import sys
import numpy as np
import coremltools as ct
from transformers import AutoTokenizer

MODEL_DIR = "/tmp/noto-embed-spike/granite/model"
FIXTURES = "/tmp/noto-embed-spike/fixtures.json"
OUT_DIR = "/tmp/noto-embed-spike/granite"
SEQ_LEN = 512


def encode_all(mlmodel, tokenizer, texts):
    out = np.zeros((len(texts), 384), dtype=np.float32)
    for i, text in enumerate(texts):
        enc = tokenizer(text, padding="max_length", max_length=SEQ_LEN,
                        truncation=True, return_tensors="np")
        pred = mlmodel.predict({
            "input_ids": enc["input_ids"].astype(np.int32),
            "attention_mask": enc["attention_mask"].astype(np.int32),
        })
        out[i] = pred["embedding"][0]
    return out


def report(name, coreml_emb, ref_emb):
    # both should be ~unit-norm; normalize defensively for the cosine
    a = coreml_emb / np.linalg.norm(coreml_emb, axis=1, keepdims=True)
    b = ref_emb / np.linalg.norm(ref_emb, axis=1, keepdims=True)
    cos = (a * b).sum(axis=1)
    print(f"  {name}: min={cos.min():.6f} mean={cos.mean():.6f} max={cos.max():.6f}")
    return cos


def main():
    mlpackage_path, tag = sys.argv[1], sys.argv[2]
    compute_units = ct.ComputeUnit.ALL
    if len(sys.argv) > 3 and sys.argv[3] == "cpu":
        compute_units = ct.ComputeUnit.CPU_ONLY

    with open(FIXTURES) as f:
        fixtures = json.load(f)
    passages = [p["text"] for p in fixtures["passages"]]
    queries = [q["text"] for q in fixtures["queries"]]

    tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR)
    mlmodel = ct.models.MLModel(mlpackage_path, compute_units=compute_units)

    ref_p = np.load(f"{OUT_DIR}/ref_passages.npy")
    ref_q = np.load(f"{OUT_DIR}/ref_queries.npy")

    cm_p = encode_all(mlmodel, tokenizer, passages)
    cm_q = encode_all(mlmodel, tokenizer, queries)

    np.save(f"{OUT_DIR}/coreml_{tag}_passages.npy", cm_p)
    np.save(f"{OUT_DIR}/coreml_{tag}_queries.npy", cm_q)

    print(f"Parity for {mlpackage_path} ({compute_units}):")
    cp = report("passages", cm_p, ref_p)
    cq = report("queries ", cm_q, ref_q)
    allc = np.concatenate([cp, cq])
    print(f"  ALL     : min={allc.min():.6f} mean={allc.mean():.6f}")


if __name__ == "__main__":
    main()
