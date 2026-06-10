"""Comparative retrieval eval: granite-97m-r2 vs multilingual-e5-small (all CoreML variants).

Embeddings are L2-normalized, so cosine = dot product.
Metrics: hit@1, hit@5, MRR over 18 queries; cross-lingual subset (6 queries) reported separately.
q17 accepts p18 or p26 (same topic in EN and ZH).
"""
import json
import numpy as np

fixtures = json.load(open("/tmp/noto-embed-spike/fixtures.json"))
passages = fixtures["passages"]
queries = fixtures["queries"]
pid_to_idx = {p["id"]: i for i, p in enumerate(passages)}

TRACKS = {
    "granite": "/tmp/noto-embed-spike/granite",
    "e5": "/tmp/noto-embed-spike/e5",
}
VARIANTS = ["ref", "coreml_fp16", "coreml_int8", "coreml_6bit"]


def load(track_dir, variant):
    try:
        p = np.load(f"{track_dir}/{variant}_passages.npy")
        q = np.load(f"{track_dir}/{variant}_queries.npy")
        return p, q
    except FileNotFoundError:
        return None, None


def evaluate(P, Q):
    sims = Q @ P.T  # (18, 40)
    rows = []
    for qi, q in enumerate(queries):
        accept = {pid_to_idx[q["relevant"]]}
        if "relevant_alt" in q:
            accept.add(pid_to_idx[q["relevant_alt"]])
        order = np.argsort(-sims[qi])
        rank = min(int(np.where(order == a)[0][0]) for a in accept) + 1  # 1-based best rank
        rows.append({"q": q, "rank": rank, "top": [passages[i]["id"] for i in order[:5]]})
    def agg(subset):
        if not subset:
            return None
        return {
            "n": len(subset),
            "hit@1": sum(r["rank"] == 1 for r in subset) / len(subset),
            "hit@5": sum(r["rank"] <= 5 for r in subset) / len(subset),
            "mrr": float(np.mean([1.0 / r["rank"] for r in subset])),
        }
    return rows, agg(rows), agg([r for r in rows if r["q"].get("crosslingual")]), agg([r for r in rows if not r["q"].get("crosslingual")])


print(f"{'model/variant':<24} {'all hit@1':>9} {'hit@5':>6} {'MRR':>6} | {'xling hit@1':>11} {'hit@5':>6} {'MRR':>6} | {'mono hit@1':>10}")
print("-" * 100)
misses = {}
for track, tdir in TRACKS.items():
    for variant in VARIANTS:
        P, Q = load(tdir, variant)
        if P is None:
            continue
        rows, all_m, xl_m, mono_m = evaluate(P.astype(np.float64), Q.astype(np.float64))
        print(f"{track}/{variant:<16} {all_m['hit@1']:>9.2f} {all_m['hit@5']:>6.2f} {all_m['mrr']:>6.3f} | "
              f"{xl_m['hit@1']:>11.2f} {xl_m['hit@5']:>6.2f} {xl_m['mrr']:>6.3f} | {mono_m['hit@1']:>10.2f}")
        misses[f"{track}/{variant}"] = [(r["q"]["id"], r["q"]["text"][:40], r["q"]["relevant"], r["rank"], r["top"]) for r in rows if r["rank"] > 1]

print("\n=== Misses (rank > 1) ===")
for key, ms in misses.items():
    if "ref" in key or "int8" in key:
        print(f"\n{key}: {len(ms)} miss(es)")
        for qid, qtext, rel, rank, top in ms:
            print(f"  {qid} '{qtext}' want={rel} rank={rank} top5={top}")
