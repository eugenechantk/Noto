# Hybrid Search Quality — Workstream Brief

**Worktree:** `Noto-hybrid-quality` / branch `feature/hybrid-search-quality` (forked from main @ 11ddcf0, which contains the full semantic-search feature).
**Goal:** measurably improve hybrid search ranking quality on Eugene's real vault.

## Agreed priorities (from the bug-019 retro, 2026-06-11)

1. **Golden-query eval harness (do first — makes everything else measurable).**
   - Capture (query → expected note[s]) pairs from Eugene's real usage; seed with the bug-019 set: "vibe code remote control" → 国内终于有厂商要出了 (current fused rank: 67), "vibe coding remote" (55), "vibe code 麦克风" (17), plus the audited wins ("rent negotiation with landlord" → 续租谈判 #1, etc.).
   - Runner: adapt the bug-019 debug harness (`/tmp/noto-debug-search` pattern — full pipeline: GraniteEmbedder + HybridNoteSearch against read-only copies of the real indexes). Report rank per pair + aggregate (MRR, hits@10). Run on demand before/after any ranking change.
2. **FG-CLIP2-Base visual leg (Stage 3) — the biggest capability gap.**
   - Bug 019 proved text-side signals cannot express "looks like a remote control" (Vision labels max 0.20 conf, no remote_control candidate; forced-label probe still rank ~131).
   - Verified candidate: qihoo360/fg-clip2-base — Apache-2.0, EN+ZH best at base size (COCO-CN T→I 62.9), ~285 MB quantized. Conversion spike required, with a Python↔Swift parity harness (custom text tower = silent-misalignment risk). Full dossier: `.claude/research/multimodal/` + `.claude/brainstorm/multimodal-embedding-research.md`.
   - Architecture: third RRF leg (image vectors in a separate space; CLIP text encoder for queries), fused at note level like the semantic leg.
3. **Fusion/ranking tuning (only with #1 in place):** weighted RRF (keyword vs semantic vs visual weights), per-note row cap (currently 2), candidate depths (keyword 150 / semantic 50 / fused 100), BM25 column weights (5.0/1.5/1.0) — all currently untuned defaults; change nothing without eval evidence.

## Constraints / context

- Current ranking machinery: FTS5 BM25 (+OR recall fallback, bug 019) + granite cosine + RRF k=60 with 2-rows-per-note emission cap.
- Eugene's vault: ~900 notes, Readwise-heavy, EN+ZH mixed, ~1,500 remote images.
- TestFlight pushes must be local (model gitignored — copy `GraniteEmbed_int8.mlpackage`, `Config/LocalSecrets.xcconfig`, `fastlane/.env.local` into any new worktree; all three are already seeded in this one).
