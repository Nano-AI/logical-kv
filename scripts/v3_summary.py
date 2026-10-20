import json, statistics as st
from math import comb
def load(p): return {r["id"]: r for r in map(json.loads, open(p))}
def sign(w, l):
    n = w + l
    return 1.0 if n == 0 else min(1.0, 2 * sum(comb(n, k) for k in range(min(w, l) + 1)) / 2 ** n)
C = ["base", "fmt", "sync", "lat8/lag_trunc", "lat8/lag_mask", "lat8/lag_refresh", "lat3/lag_trunc", "lat3/lag_mask", "lat1/lag_trunc", "lat1/lag_mask"]
for ver in ["Qwen3-30B-A3B", "Qwen3-30B-A3B_v3"]:
    print(f"\n### {ver}")
    print("cond | acc | unforced acc (n) | capped acc (n) | gen tok median/mean | p90 | steps mean | ctx pos peak | ctx cells peak | cells final | cache hits | restated")
    for c in C:
        R = load(f"results_cloud/{ver}/{c}.jsonl"); rs = list(R.values())
        ok = lambda r: r["pred"] == r["gold"]
        capped = [r for r in rs if r.get("cap") or r.get("forced")]
        unf = [r for r in rs if not (r.get("cap") or r.get("forced"))]
        g = sorted(r.get("gen_tokens", 0) for r in rs)
        verd = [s.get("verdict", "") for r in rs for s in r.get("steps", [])]
        print(c, "|", sum(map(ok, rs)), "|", f"{100*sum(map(ok, unf))/max(1,len(unf)):.0f}% ({len(unf)})", "|",
              f"{100*sum(map(ok, capped))/max(1,len(capped)):.0f}% ({len(capped)})", "|", f"{st.median(g):.0f}/{st.mean(g):.0f}", "|", g[89], "|",
              f"{st.mean(len(r.get('steps', [])) for r in rs):.1f}", "|",
              *(f"{st.mean(r.get(k, 0) for r in rs):.0f} |" for k in ("ctx_pos_peak", "ctx_cells_peak", "ctx_cells_final")),
              sum(r.get("cache_hits", 0) for r in rs), "|", verd.count("restated"))
v2, v3 = "results_cloud/Qwen3-30B-A3B", "results_cloud/Qwen3-30B-A3B_v3"
print("\n### paired accuracy (wins/losses, exact sign p)")
for a, b, d in [("sync", "fmt", v3), ("fmt", "base", v3), ("lat8/lag_mask", "lat8/lag_trunc", v3), ("lat3/lag_mask", "lat3/lag_trunc", v3),
                ("lat1/lag_mask", "lat1/lag_trunc", v3), ("lat8/lag_refresh", "lat8/lag_mask", v3), ("lat1/lag_mask", "sync", v3)]:
    A, B = load(f"{d}/{a}.jsonl"), load(f"{d}/{b}.jsonl")
    w = sum(A[i]["pred"] == A[i]["gold"] != B[i]["pred"] for i in A); l = sum(B[i]["pred"] == B[i]["gold"] != A[i]["pred"] for i in A)
    print(f"v3 {a} vs {b}: {w}/{l} p={sign(w, l):.3f}")
for c in C:
    A, B = load(f"{v3}/{c}.jsonl"), load(f"{v2}/{c}.jsonl")
    w = sum(A[i]["pred"] == A[i]["gold"] != B[i]["pred"] for i in A); l = sum(B[i]["pred"] == B[i]["gold"] != A[i]["pred"] for i in A)
    print(f"v3 vs v2 {c}: {w}/{l} p={sign(w, l):.3f}")
print("\n### mask vs trunc, same problems, excluding problems where either hit a cap (tokens W/L)")
for L in (1, 3, 8):
    A, B = load(f"{v3}/lat{L}/lag_mask.jsonl"), load(f"{v3}/lat{L}/lag_trunc.jsonl")
    ids = [i for i in A if not (A[i].get("cap") or B[i].get("cap"))]
    w = sum(A[i]["gen_tokens"] < B[i]["gen_tokens"] for i in ids); l = sum(A[i]["gen_tokens"] > B[i]["gen_tokens"] for i in ids)
    print(f"L={L}: n={len(ids)} mask fewer {w}/{l} p={sign(w, l):.3f}  median tok {st.median(A[i]['gen_tokens'] for i in ids):.0f} vs {st.median(B[i]['gen_tokens'] for i in ids):.0f}",
          f" caps mask/trunc {sum(bool(A[i].get('cap')) for i in A)}/{sum(bool(B[i].get('cap')) for i in B)}",
          " ctx cells peak", f"{st.mean(A[i]['ctx_cells_peak'] for i in A):.0f} vs {st.mean(B[i]['ctx_cells_peak'] for i in B):.0f}")
