#!/usr/bin/env python
"""Convert ibm-granite/granite-embedding-97m-multilingual-r2 (ModernBERT) to Core ML.

Approach:
- Load ModernBertModel with attn_implementation="eager", reference_compile=False.
- Patch ModernBertModel._update_attention_mask to use an FP16-safe additive mask
  fill (-1e4) instead of torch.finfo(float32).min (-3.4e38, overflows to -inf in
  FP16 and can produce NaNs on ANE).
- Wrap in an nn.Module that does CLS pooling + L2 normalization INSIDE the graph.
- torch.jit.trace at fixed shape (1, 512), convert to mlprogram FP16, iOS17 target.

Inputs : input_ids (1,512) int32, attention_mask (1,512) int32
Output : embedding (1,384) float32, L2-normalized
"""
import numpy as np
import torch
import torch.nn as nn
import coremltools as ct
from transformers import AutoModel, AutoTokenizer

MODEL_DIR = "/tmp/noto-embed-spike/granite/model"
OUT_DIR = "/tmp/noto-embed-spike/granite"
SEQ_LEN = 512
NEG = -1e4  # FP16-safe additive mask value


def patched_update_attention_mask(self, attention_mask, output_attentions=False):
    """Faithful reimplementation of ModernBertModel._update_attention_mask with
    an FP16-safe fill value. Original uses torch.finfo(self.dtype).min."""
    dtype = torch.float32
    bsz, seq = attention_mask.shape
    # _prepare_4d_attention_mask equivalent: [b, 1, tgt, src] additive mask
    expanded = attention_mask[:, None, None, :].expand(bsz, 1, seq, seq).to(dtype)
    global_attention_mask = (1.0 - expanded) * NEG

    rows = torch.arange(seq).unsqueeze(0)
    distance = torch.abs(rows - rows.T)
    window_mask = (distance <= self.config.local_attention // 2).unsqueeze(0).unsqueeze(0)
    sliding_window_mask = global_attention_mask.masked_fill(window_mask.logical_not(), NEG)
    return global_attention_mask, sliding_window_mask


class GraniteEmbedder(nn.Module):
    """ModernBERT encoder + CLS pooling + L2 normalize, single graph."""

    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, input_ids, attention_mask):
        out = self.model(input_ids=input_ids, attention_mask=attention_mask, return_dict=False)
        cls = out[0][:, 0]                                   # CLS pooling (1_Pooling config)
        return cls / cls.norm(dim=-1, keepdim=True).clamp(min=1e-12)  # 2_Normalize


def main():
    torch.manual_seed(0)
    model = AutoModel.from_pretrained(
        MODEL_DIR, torch_dtype=torch.float32,
        attn_implementation="eager", reference_compile=False,
    )
    model.eval()
    # Patch mask construction for FP16 safety
    model._update_attention_mask = patched_update_attention_mask.__get__(model, type(model))

    tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR)
    enc = tokenizer("The quick brown fox jumps over the lazy dog.",
                    padding="max_length", max_length=SEQ_LEN, truncation=True,
                    return_tensors="pt")
    input_ids = enc["input_ids"].to(torch.int32)
    attention_mask = enc["attention_mask"].to(torch.int32)

    wrapper = GraniteEmbedder(model).eval()

    with torch.no_grad():
        ref_out = wrapper(input_ids, attention_mask)
    print("eager wrapper output:", ref_out.shape, "norm:", ref_out.norm().item())

    print("tracing...")
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, (input_ids, attention_mask), strict=False)
        traced_out = traced(input_ids, attention_mask)
    cos = torch.nn.functional.cosine_similarity(ref_out, traced_out).item()
    print(f"trace vs eager cosine: {cos:.8f}")

    print("converting to Core ML (mlprogram, FP16, iOS17)...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, SEQ_LEN), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, SEQ_LEN), dtype=np.int32),
        ],
        outputs=[ct.TensorType(name="embedding", dtype=np.float32)],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
    )
    mlmodel.short_description = (
        "granite-embedding-97m-multilingual-r2 (ModernBERT). "
        "CLS-pooled, L2-normalized 384-d sentence embedding. seq 512 fixed."
    )
    out_path = f"{OUT_DIR}/GraniteEmbed_fp16.mlpackage"
    mlmodel.save(out_path)
    print("saved", out_path)

    # quick smoke parity on the trace sentence
    pred = mlmodel.predict({
        "input_ids": input_ids.numpy().astype(np.int32),
        "attention_mask": attention_mask.numpy().astype(np.int32),
    })
    emb = pred["embedding"]
    cos = float(np.dot(emb[0], ref_out[0].numpy()) /
                (np.linalg.norm(emb[0]) * np.linalg.norm(ref_out[0].numpy())))
    print(f"coreml fp16 vs pytorch cosine (smoke): {cos:.6f}")


if __name__ == "__main__":
    main()
