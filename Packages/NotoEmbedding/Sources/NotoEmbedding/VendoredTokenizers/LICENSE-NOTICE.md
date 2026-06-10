# Vendored Code Notice

The Swift files in this directory are vendored from
[huggingface/swift-transformers](https://github.com/huggingface/swift-transformers),
licensed under the **Apache License, Version 2.0**.

- **Upstream tag:** `1.3.3`
- **Upstream commit:** `2fa33e1f5e7131a7fc64c28e6d161dcec0d24820`
- **Upstream license:** Apache-2.0 — <https://github.com/huggingface/swift-transformers/blob/main/LICENSE>
- **Copyright:** Hugging Face and swift-transformers contributors

## What was vendored

| Local file | Upstream source |
| --- | --- |
| `Tokenizer.swift` | `Sources/Tokenizers/Tokenizer.swift` |
| `BPETokenizer.swift` | `Sources/Tokenizers/BPETokenizer.swift` |
| `PreTokenizer.swift` | `Sources/Tokenizers/PreTokenizer.swift` |
| `Normalizer.swift` | `Sources/Tokenizers/Normalizer.swift` |
| `PostProcessor.swift` | `Sources/Tokenizers/PostProcessor.swift` |
| `Decoder.swift` | `Sources/Tokenizers/Decoder.swift` |
| `ByteEncoder.swift` | `Sources/Tokenizers/ByteEncoder.swift` |
| `String+PreTokenization.swift` | `Sources/Tokenizers/String+PreTokenization.swift` |
| `Config.swift` | `Sources/Hub/Config.swift` |
| `BinaryDistinct.swift` | `Sources/Hub/BinaryDistinct.swift` |

Not vendored: `BertTokenizer`, `UnigramTokenizer`, `TokenLattice`, `Trie`
(non-BPE tokenizer paths), `Hub`/`HubApi`/`YYJSONParser` (network + yyjson
loading), and all Jinja chat-template machinery.

## Local modifications

Each file carries a header comment listing its specific changes. Summary:

1. **No `Hub` / `Jinja` imports.** Everything lives in one module
   (`NotoEmbedding`), and the chat-template machinery was removed entirely.
2. **`Config.swift`:** removed `jinjaValue()`; added a `Config(jsonData:)`
   initializer backed by Foundation `JSONSerialization` (replaces the upstream
   yyjson/Hub loading path; no network access).
3. **`Tokenizer.swift`:** trimmed to the BPE encode/decode path — removed chat
   templates, `AutoTokenizer`, Hub loading, and non-BPE tokenizer
   registrations (`Bert`, `Unigram`, `T5`, Llama subclass).
4. **`BPETokenizer.swift`:** added support for the HF `model.ignore_merges`
   flag (whole-token vocabulary lookup before applying BPE merges), which the
   `ibm-granite/granite-embedding-97m-multilingual-r2` tokenizer requires.
5. **`BinaryDistinct.swift`:** `BinaryDistinctString.init(NSString)` builds its
   UTF-16 array directly from `String.utf16` instead of flat-mapping
   per-`Character` (identical output, much faster for 180k-entry vocabularies).

These files are used to tokenize text for the
`ibm-granite/granite-embedding-97m-multilingual-r2` embedding model. See
`GraniteTokenizer.swift` (outside this directory, original code) for the
public API.
