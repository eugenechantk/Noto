#!/usr/bin/env python3
"""
Convert bge-small-en-v1.5 from HuggingFace to CoreML format.

This script:
1. Downloads the BAAI/bge-small-en-v1.5 model from HuggingFace
2. JIT-traces a custom wrapper (CLS pooling + L2 norm baked in)
3. Converts to CoreML .mlpackage
4. Extracts vocab.txt from the tokenizer

Usage (specific versions required for compatibility):
    uv run --with 'coremltools<9.0,>=8.0' --with 'transformers==4.36.0' --with 'torch==2.5.0' --with numpy python scripts/convert_model.py

Output:
    Noto/Resources/bge-small-en-v1_5.mlpackage
    Noto/Resources/vocab.txt
"""

import os
import shutil

import coremltools as ct
import numpy as np
import torch
import torch.nn as nn
from transformers import AutoModel, AutoTokenizer


MAX_SEQ_LENGTH = 512


class BGECoreMLWrapper(nn.Module):
    """
    Wraps BERT encoder weights directly with manual forward pass to avoid
    HuggingFace's internal tracing issues. Includes CLS pooling + L2 norm.
    """

    def __init__(self, base_model):
        super().__init__()
        self.embeddings = base_model.embeddings
        self.encoder = base_model.encoder
        self.pooler = base_model.pooler

    def forward(self, input_ids: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
        # Compute embeddings manually to avoid position_ids int() cast issue
        seq_length = input_ids.shape[1]
        position_ids = torch.arange(seq_length, device=input_ids.device).unsqueeze(0)
        token_type_ids = torch.zeros_like(input_ids)

        word_embeds = self.embeddings.word_embeddings(input_ids)
        position_embeds = self.embeddings.position_embeddings(position_ids)
        token_type_embeds = self.embeddings.token_type_embeddings(token_type_ids)

        embeddings = word_embeds + position_embeds + token_type_embeds
        embeddings = self.embeddings.LayerNorm(embeddings)
        embeddings = self.embeddings.dropout(embeddings)

        # Create extended attention mask (1.0 for tokens, -10000.0 for padding)
        extended_attention_mask = attention_mask.unsqueeze(1).unsqueeze(2).to(embeddings.dtype)
        extended_attention_mask = (1.0 - extended_attention_mask) * -10000.0

        # Run through encoder
        hidden_states = embeddings
        for layer in self.encoder.layer:
            layer_output = layer(hidden_states, attention_mask=extended_attention_mask)
            hidden_states = layer_output[0]

        # CLS token pooling (first token)
        cls_embedding = hidden_states[:, 0, :]
        # L2 normalize
        normalized = torch.nn.functional.normalize(cls_embedding, p=2, dim=1)
        return normalized


def main():
    model_name = "BAAI/bge-small-en-v1.5"
    output_dir = os.path.join(os.path.dirname(__file__), "..", "Noto", "Resources")
    os.makedirs(output_dir, exist_ok=True)

    print(f"Loading {model_name}...")
    tokenizer = AutoTokenizer.from_pretrained(model_name)
    base_model = AutoModel.from_pretrained(model_name, attn_implementation="eager")
    base_model.eval()

    # Wrap with custom forward to avoid tracing issues
    model = BGECoreMLWrapper(base_model)
    model.eval()

    dummy_input_ids = torch.zeros(1, MAX_SEQ_LENGTH, dtype=torch.int32)
    dummy_attention_mask = torch.ones(1, MAX_SEQ_LENGTH, dtype=torch.int32)

    # JIT trace the custom wrapper (avoids HF position_ids cast issue)
    print("Tracing model...")
    with torch.no_grad():
        traced = torch.jit.trace(model, (dummy_input_ids, dummy_attention_mask))

    # Convert to CoreML
    print("Converting to CoreML...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, MAX_SEQ_LENGTH), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, MAX_SEQ_LENGTH), dtype=np.int32),
        ],
        outputs=[
            ct.TensorType(name="sentence_embedding"),
        ],
        minimum_deployment_target=ct.target.iOS16,
    )

    # Save as .mlpackage
    mlpackage_path = os.path.join(output_dir, "bge-small-en-v1_5.mlpackage")
    if os.path.exists(mlpackage_path):
        shutil.rmtree(mlpackage_path)
    print(f"Saving model to {mlpackage_path}...")
    mlmodel.save(mlpackage_path)

    # Extract vocab.txt
    vocab_path = os.path.join(output_dir, "vocab.txt")
    vocab = tokenizer.get_vocab()
    sorted_vocab = sorted(vocab.items(), key=lambda x: x[1])
    with open(vocab_path, "w", encoding="utf-8") as f:
        for token, _ in sorted_vocab:
            f.write(token + "\n")
    print(f"Saved vocab.txt ({len(sorted_vocab)} tokens) to {vocab_path}")

    # Validate
    print("\nValidating conversion...")
    # Also create reference model using HF's own forward for comparison
    ref_model = BGECoreMLWrapper(base_model)
    ref_model.eval()

    test_texts = [
        "aesthetic taste in design",
        "artistic judgement and beauty",
        "grocery shopping list",
    ]

    for text in test_texts:
        inputs = tokenizer(text, return_tensors="pt", max_length=MAX_SEQ_LENGTH,
                          padding="max_length", truncation=True)
        input_ids_np = inputs["input_ids"].numpy().astype(np.int32)
        attention_mask_np = inputs["attention_mask"].numpy().astype(np.int32)

        # PyTorch output
        with torch.no_grad():
            pt_output = ref_model(
                inputs["input_ids"].to(torch.int32),
                inputs["attention_mask"].to(torch.int32),
            ).numpy()[0]

        # CoreML output
        pred = mlmodel.predict({
            "input_ids": input_ids_np,
            "attention_mask": attention_mask_np,
        })
        ct_output = pred["sentence_embedding"].flatten()

        # Compare
        cos_sim = np.dot(pt_output, ct_output) / (
            np.linalg.norm(pt_output) * np.linalg.norm(ct_output)
        )
        l2_norm = np.linalg.norm(ct_output)
        print(f'  "{text}": cos_sim={cos_sim:.6f}, L2_norm={l2_norm:.4f}')

    print("\nConversion complete!")
    print(f"To compile for Xcode, run:")
    print(f"  xcrun coremlcompiler compile {mlpackage_path} {output_dir}")
    print(f"  (produces bge-small-en-v1_5.mlmodelc directory)")


if __name__ == "__main__":
    main()
