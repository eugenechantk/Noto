#!/usr/bin/env python3
"""
Convert bge-small-en-v1.5 from HuggingFace to CoreML format.

This script:
1. Downloads the BAAI/bge-small-en-v1.5 model from HuggingFace
2. Traces it with CLS pooling and L2 normalization baked in
3. Converts to CoreML .mlpackage / .mlmodelc
4. Extracts vocab.txt from the tokenizer

Usage:
    pip install coremltools transformers torch numpy
    python scripts/convert_model.py

Output:
    Noto/Search/Resources/bge-small-en-v1_5.mlpackage
    Noto/Search/Resources/vocab.txt
"""

import os
import shutil

import coremltools as ct
import numpy as np
import torch
import torch.nn as nn
from transformers import AutoModel, AutoTokenizer


class BGEWithPoolingAndNorm(nn.Module):
    """Wraps the BERT model with CLS pooling and L2 normalization."""

    def __init__(self, base_model):
        super().__init__()
        self.base_model = base_model

    def forward(self, input_ids, attention_mask):
        outputs = self.base_model(input_ids=input_ids, attention_mask=attention_mask)
        # CLS token pooling (first token)
        cls_embedding = outputs.last_hidden_state[:, 0, :]
        # L2 normalize
        normalized = torch.nn.functional.normalize(cls_embedding, p=2, dim=1)
        return normalized


def main():
    model_name = "BAAI/bge-small-en-v1.5"
    output_dir = os.path.join(os.path.dirname(__file__), "..", "Noto", "Search", "Resources")
    os.makedirs(output_dir, exist_ok=True)

    print(f"Loading {model_name}...")
    tokenizer = AutoTokenizer.from_pretrained(model_name)
    base_model = AutoModel.from_pretrained(model_name)
    base_model.eval()

    model = BGEWithPoolingAndNorm(base_model)
    model.eval()

    # Trace the model
    max_seq_length = 512
    dummy_input_ids = torch.zeros(1, max_seq_length, dtype=torch.int32)
    dummy_attention_mask = torch.ones(1, max_seq_length, dtype=torch.int32)

    print("Tracing model...")
    with torch.no_grad():
        traced = torch.jit.trace(model, (dummy_input_ids, dummy_attention_mask))

    # Convert to CoreML
    print("Converting to CoreML...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, max_seq_length), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, max_seq_length), dtype=np.int32),
        ],
        outputs=[
            ct.TensorType(name="sentence_embedding"),
        ],
        minimum_deployment_target=ct.target.iOS16,
    )

    # Save as .mlpackage
    mlpackage_path = os.path.join(output_dir, "bge-small-en-v1_5.mlpackage")
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
    test_texts = [
        "aesthetic taste in design",
        "artistic judgement and beauty",
        "grocery shopping list",
    ]

    for text in test_texts:
        inputs = tokenizer(text, return_tensors="pt", max_length=max_seq_length,
                          padding="max_length", truncation=True)
        input_ids = inputs["input_ids"].numpy().astype(np.int32)
        attention_mask = inputs["attention_mask"].numpy().astype(np.int32)

        # PyTorch output
        with torch.no_grad():
            pt_output = model(
                torch.tensor(input_ids),
                torch.tensor(attention_mask),
            ).numpy()[0]

        # CoreML output
        pred = mlmodel.predict({
            "input_ids": input_ids,
            "attention_mask": attention_mask,
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
