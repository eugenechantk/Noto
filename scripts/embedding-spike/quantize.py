#!/usr/bin/env python
"""Quantize the FP16 GraniteEmbed mlpackage.

Variant 1: int8 linear-symmetric per-channel weight quantization (iOS17 base).
Variant 2: 6-bit k-means palettization, per-grouped-channel (group_size=16).
           per_grouped_channel requires an iOS18 minimum deployment target, so
           this variant re-converts the traced model with iOS18 first.
"""
import sys
import numpy as np
import torch
import coremltools as ct
import coremltools.optimize.coreml as cto

OUT_DIR = "/tmp/noto-embed-spike/granite"
SRC = f"{OUT_DIR}/GraniteEmbed_fp16.mlpackage"
SEQ_LEN = 512


def quantize_int8():
    mlmodel = ct.models.MLModel(SRC, compute_units=ct.ComputeUnit.CPU_ONLY)
    op_cfg = cto.OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8",
                                         granularity="per_channel")
    cfg = cto.OptimizationConfig(global_config=op_cfg)
    q8 = cto.linear_quantize_weights(mlmodel, config=cfg)
    q8.save(f"{OUT_DIR}/GraniteEmbed_int8.mlpackage")
    print("saved GraniteEmbed_int8.mlpackage")


def palettize_6bit():
    # Re-convert with iOS18 target (per_grouped_channel needs iOS18 opset).
    from convert import GraniteEmbedder, patched_update_attention_mask, MODEL_DIR
    from transformers import AutoModel, AutoTokenizer

    model = AutoModel.from_pretrained(
        MODEL_DIR, torch_dtype=torch.float32,
        attn_implementation="eager", reference_compile=False)
    model.eval()
    model._update_attention_mask = patched_update_attention_mask.__get__(model, type(model))
    tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR)
    enc = tokenizer("The quick brown fox jumps over the lazy dog.",
                    padding="max_length", max_length=SEQ_LEN, truncation=True,
                    return_tensors="pt")
    wrapper = GraniteEmbedder(model).eval()
    with torch.no_grad():
        traced = torch.jit.trace(
            wrapper, (enc["input_ids"].to(torch.int32), enc["attention_mask"].to(torch.int32)),
            strict=False)
    base18 = ct.convert(
        traced,
        inputs=[ct.TensorType(name="input_ids", shape=(1, SEQ_LEN), dtype=np.int32),
                ct.TensorType(name="attention_mask", shape=(1, SEQ_LEN), dtype=np.int32)],
        outputs=[ct.TensorType(name="embedding", dtype=np.float32)],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS18,
    )
    pal_cfg = cto.OpPalettizerConfig(mode="kmeans", nbits=6,
                                     granularity="per_grouped_channel",
                                     group_size=16)
    cfg6 = cto.OptimizationConfig(global_config=pal_cfg)
    p6 = cto.palettize_weights(base18, config=cfg6)
    p6.save(f"{OUT_DIR}/GraniteEmbed_6bit.mlpackage")
    print("saved GraniteEmbed_6bit.mlpackage (iOS18 min target)")


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    if which in ("all", "int8"):
        quantize_int8()
    if which in ("all", "6bit"):
        palettize_6bit()


if __name__ == "__main__":
    main()
