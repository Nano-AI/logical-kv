"""Round 5: 14B efficiency run (DEPWAIT+LOOP; trunc, mask, hybrid refresh) vs the round-3 14B L=8 baselines on the same ids."""
import json, glob, statistics as st
from math import comb

P = "results_cloud"
TOK_S, FIXED = 0.0724, 8.6  # token clock from the laptop runs; modeled time = FIXED + TOK_S*gen + waits


def load(path):
    return {r["id"]: r for r in (json.loads(l) for l in open(path) if l.strip())}


def sign_p(wins, losses):  # two-sided exact sign test
    n = wins + losses
    k = min(wins, losses)
    return 1.0 if n == 0 else min(1.0, 2 * sum(comb(n, i) for i in range(k + 1)) / 2 ** n)


def modeled(r):
    return FIXED + TOK_S * r["gen_tokens"] + r.get("wait_s", 0)


new = {c: load(f"{P}/Qwen3-14B_eff/lat8/{c}.jsonl") for c in ("lag_trunc", "lag_mask", "lag_refresh")}
old = {c: load(f"{P}/Qwen3-14B/lat8/{c}.jsonl") for c in ("lag_trunc", "lag_mask", "lag_refresh")}
ids = sorted(set.intersection(*(set(v) for v in list(new.values()) + list(old.values()))))  # paired: ids present in every run
print(f"n={len(ids)} common ids")

rows = [("old " + c, {i: old[c][i] for i in ids if i in old[c]}) for c in old] + [("new " + c, new[c]) for c in new]
print(f"{'cond':18} {'acc':>5} {'gen':>6} {'waste':>6} {'wait_s':>7} {'model_s':>8} {'wall_s':>7} {'unwait':>6} {'loops':>5} {'hyb':>4} {'masks':>5} {'trunc':>5}")
for name, d in rows:
    rs = [d[i] for i in ids if i in d]
    if not rs:
        continue
    m = lambda k: st.mean(r.get(k, 0) or 0 for r in rs)
    print(f"{name:18} {sum(r['correct'] for r in rs):2d}/{len(rs):<2d} {m('gen_tokens'):6.0f} {m('wasted_tokens'):6.0f} {m('wait_s'):7.1f} {st.mean(modeled(r) for r in rs):8.1f} {m('wall_s'):7.1f} {m('unwaited'):6.2f} {m('loops'):5.2f} {m('hybrid_truncs'):4.2f} {m('masks'):5.2f} {m('truncations'):5.2f}")

print("\npaired tests (a vs b on common ids): accuracy discordant pairs, gen-token sign test, modeled-time sign test")
pairs = [("new lag_trunc", new["lag_trunc"], "old lag_trunc", old["lag_trunc"]),
         ("new lag_mask", new["lag_mask"], "old lag_mask", old["lag_mask"]),
         ("new lag_refresh", new["lag_refresh"], "old lag_refresh", old["lag_refresh"]),
         ("new lag_mask", new["lag_mask"], "new lag_trunc", new["lag_trunc"]),
         ("new lag_refresh", new["lag_refresh"], "new lag_trunc", new["lag_trunc"]),
         ("new lag_refresh", new["lag_refresh"], "new lag_mask", new["lag_mask"])]
for na, a, nb, b in pairs:
    common = [i for i in ids if i in a and i in b]
    aw = sum(a[i]["correct"] and not b[i]["correct"] for i in common)
    bw = sum(b[i]["correct"] and not a[i]["correct"] for i in common)
    fewer = sum(a[i]["gen_tokens"] < b[i]["gen_tokens"] for i in common)
    more = sum(a[i]["gen_tokens"] > b[i]["gen_tokens"] for i in common)
    faster = sum(modeled(a[i]) < modeled(b[i]) for i in common)
    slower = sum(modeled(a[i]) > modeled(b[i]) for i in common)
    dt = st.mean(modeled(a[i]) - modeled(b[i]) for i in common) if common else 0
    print(f"{na:16} vs {nb:16}: acc +{aw}/-{bw} p={sign_p(aw, bw):.2f} | fewer tok {fewer}/{more} p={sign_p(fewer, more):.2f} | faster {faster}/{slower} p={sign_p(faster, slower):.2f} (mean {dt:+.1f} s)")
