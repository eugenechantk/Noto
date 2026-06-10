#!/usr/bin/env python
"""Latency measurement: single inference at seq 512, median of 30 predicts
after 5 warmup, for each .mlpackage variant under several compute units.
"""
import time
import numpy as np
import coremltools as ct
from transformers import AutoTokenizer

MODEL_DIR = "/tmp/noto-embed-spike/granite/model"
OUT_DIR = "/tmp/noto-embed-spike/granite"
SEQ_LEN = 512

VARIANTS = ["GraniteEmbed_fp16.mlpackage", "GraniteEmbed_int8.mlpackage",
            "GraniteEmbed_6bit.mlpackage"]
UNITS = [("ALL", ct.ComputeUnit.ALL),
         ("CPU_AND_NE", ct.ComputeUnit.CPU_AND_NE),
         ("CPU_ONLY", ct.ComputeUnit.CPU_ONLY)]


def main():
    tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR)
    text = ("Architecture decision: the sync engine will use a write-ahead log "
            "with vector clocks per device. " * 10)  # long-ish input, truncated to 512
    enc = tokenizer(text, padding="max_length", max_length=SEQ_LEN,
                    truncation=True, return_tensors="np")
    inputs = {"input_ids": enc["input_ids"].astype(np.int32),
              "attention_mask": enc["attention_mask"].astype(np.int32)}

    for variant in VARIANTS:
        path = f"{OUT_DIR}/{variant}"
        for unit_name, unit in UNITS:
            try:
                t_load = time.perf_counter()
                m = ct.models.MLModel(path, compute_units=unit)
                # first predict triggers compile/load on the target compute unit
                m.predict(inputs)
                load_s = time.perf_counter() - t_load
                for _ in range(4):
                    m.predict(inputs)  # warmup (5 total with the first)
                times = []
                for _ in range(30):
                    t0 = time.perf_counter()
                    m.predict(inputs)
                    times.append((time.perf_counter() - t0) * 1000)
                med = float(np.median(times))
                p90 = float(np.percentile(times, 90))
                print(f"{variant:38s} {unit_name:10s} median={med:8.2f} ms  "
                      f"p90={p90:8.2f} ms  (load+first={load_s:.1f}s)")
                del m
            except Exception as e:
                print(f"{variant:38s} {unit_name:10s} FAILED: {e}")


if __name__ == "__main__":
    main()
