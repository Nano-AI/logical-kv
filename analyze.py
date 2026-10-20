"""Extra metrics from results/*.jsonl (run after run.py). usage: python analyze.py [results_dir]"""
import glob
import json
import os
import re
import sys
from math import comb

OUT = sys.argv[1] if len(sys.argv) > 1 else "results"
CONDS = ["base", "fmt", "sync", "lag_trunc", "lag_mask", "lag_refresh"]
REASONING = ("refuted", "unknown")
FORMAT = ("not_fact", "parse_error", "tautology")


def load(c):
    p = f"{OUT}/{c}.jsonl"
    return {r["id"]: r for r in map(json.loads, open(p))} if os.path.exists(p) else {}


R = {c: load(c) for c in CONDS}
R = {c: r for c, r in R.items() if r}
REF = {c: r for c, r in ((c, load(c) if OUT == "results" else
                          {r["id"]: r for r in map(json.loads, open(f"results/{c}.jsonl"))}) for c in CONDS
                         if os.path.exists(f"results/{c}.jsonl"))}  # first-round runs, for paired comparisons


def sign_p(w, l):
    """two-sided exact binomial (sign / McNemar) p-value"""
    n, k = w + l, min(w, l)
    return min(1.0, 2 * sum(comb(n, i) for i in range(k + 1)) / 2 ** n) if n else 1.0


def restated(r):
    """entailed live steps whose formula repeats an earlier one (Z3 accepts a restatement as 'new')"""
    seen, dup, tot = set(), 0, 0
    for s in r["steps"]:
        if s["status"] in ("accepted", "unchecked", "forced") and (s["verdict"] or "") == "entailed":
            f = re.sub(r"\s+", "", s["fol"] or "")
            tot, dup = tot + 1, dup + (f in seen)
            seen.add(f)
    return dup, tot

print("## 1. Kill test on unchecked structured runs (fmt): how often is a step wrong, and what could be salvaged")
if "fmt" in R:
    steps = [s for r in R["fmt"].values() for s in r["steps"] if s["status"] == "unchecked"]
    kinds = {}
    for s in steps:
        k = (s["verdict"] or "none").split(":")[0]
        kinds[k] = kinds.get(k, 0) + 1
    bad = [s for s in steps if (s["verdict"] or "").split(":")[0] != "entailed"]
    print(f"steps={len(steps)}  verdicts={kinds}")
    print(f"reasoning errors (refuted/unknown): {sum(kinds.get(k, 0) for k in REASONING)}/{len(steps)}"
          f"   format errors (not_fact/parse_error/tautology): {sum(kinds.get(k, 0) for k in FORMAT)}/{len(steps)}")
    probs_with_bad = sum(any((s["verdict"] or "").split(":")[0] in REASONING for s in r["steps"]) for r in R["fmt"].values())
    print(f"problems with >=1 reasoning-error step: {probs_with_bad}/{len(R['fmt'])}")
    # salvage potential: for each first reasoning-error step, later steps that are NOT DAG descendants
    later_total = later_indep = 0
    for r in R["fmt"].values():
        st = [s for s in r["steps"] if s["status"] == "unchecked"]
        for i, s in enumerate(st):
            if (s["verdict"] or "").split(":")[0] not in REASONING:
                continue
            desc = {s["id"]}
            for t in st[i + 1:]:
                if desc & set(t["parents"]):
                    desc.add(t["id"])
            rest = st[i + 1:]
            later_total += len(rest)
            later_indep += sum(t["id"] not in desc for t in rest)
            break
    if later_total:
        print(f"after the first reasoning error: {later_indep}/{later_total} later steps are independent "
              f"({100 * later_indep / later_total:.0f}%) -> upper bound on what DAG masking can keep")
    else:
        print("no later steps after reasoning errors (errors are at the end of chains)")

print("\n## 2. Rejections by type (checked conditions)")
for c in ("sync", "lag_trunc", "lag_mask", "lag_refresh"):
    if c not in R:
        continue
    rej = [s for r in R[c].values() for s in r["steps"] if s["status"] in ("rejected", "masked") and s.get("verdict")
           and s["verdict"] != "entailed"]
    kinds = {}
    for s in rej:
        k = s["verdict"].split(":")[0]
        kinds[k] = kinds.get(k, 0) + 1
    wp = sum(r["wrong_prunes"] for r in R[c].values())
    print(f"{c:12} rejected={len(rej):4}  {kinds}  wrong-prune proxy={wp}")
for c in R:
    if c != "base":
        d, t = map(sum, zip(*(restated(r) for r in R[c].values())))
        print(f"{c:12} restated steps (entailed, formula repeats an earlier step): {d}/{t}")

print("\n## 3. Paired accuracy (same problems): wins / losses, exact McNemar p")
for c, rr in R.items():
    for ref in dict.fromkeys(("base", "fmt", c)):
        if ref not in REF or (ref == c and OUT == "results"):
            continue
        ids = set(rr) & set(REF[ref])
        w = sum(rr[i]["correct"] and not REF[ref][i]["correct"] for i in ids)
        l_ = sum(REF[ref][i]["correct"] and not rr[i]["correct"] for i in ids)
        print(f"{c:12} vs round-1 {ref:9} n={len(ids)} acc={100 * sum(rr[i]['correct'] for i in ids) / len(ids):5.1f}%"
              f"  wins={w} losses={l_} p={sign_p(w, l_):.2f}")
if "base" in REF:
    gold = [r["gold"] for r in REF["base"].values()]
    print(f"majority-class baseline on this sample: {100 * max(gold.count(x) for x in 'ABC') / len(gold):.1f}% "
          f"(A={gold.count('A')} B={gold.count('B')} C={gold.count('C')})")

print("\n## 4. Rollback consistency (live cache vs cold re-prefill of the visible transcript)")
for c in ("lag_trunc", "lag_mask", "lag_refresh"):
    if c not in R:
        continue
    pr = [r["probe"] for r in R[c].values() if r.get("probe")]
    stale = [p for p in pr if p["stale"]]
    for name, group in (("all", pr), ("stale-KV cases", stale)):
        if group:
            tvs = sorted(p["tv"] for p in group)
            print(f"{c:12} {name:15} n={len(group):2} mean TV={sum(tvs) / len(tvs):.4f} max TV={tvs[-1]:.4f} "
                  f"answer flips={sum(p['flip'] for p in group)}")

POLICIES = (("mask any non-entailed step", "results/lat", "results/sync.jsonl"),
            ("mask only refuted steps", "results/refuted_lat", "results/sync.jsonl"),
            ("v2: format guard + reject only refuted steps (sync too)", "results/v2/lat", "results/v2/sync.jsonl"),
            *((f"v2 policy, {d.split('/')[1]} on Colab, n=100", f"{d}lat", f"{d}sync.jsonl")
              for d in sorted(glob.glob("results_cloud/*/"))))
C_FIX = 8.6  # s/problem fixed cost (prefill etc.) from the same round-1 fit as run.TOK_S
for policy, prefix, sync_p in POLICIES:
    print(f"\n## 5. Checker-latency sweep (token clock, see run.py LATENCY), policy: {policy}")
    sweep = {float(d.split("lat")[-1]): d for d in glob.glob(f"{prefix}*") if os.path.isdir(d)}
    if not (sweep and os.path.exists(sync_p)):
        continue
    from run import TOK_S
    sync = [json.loads(line) for line in open(sync_p)]
    print(f"modeled s/problem = {C_FIX} + {TOK_S * 1000:.1f} ms x generated tokens + checker waits (idle-machine speed); "
          "sync waits L per check, lagged conds wait only for verdicts still pending at the answer")
    print(f"sync ({sync_p}): acc {100 * sum(r['correct'] for r in sync) / len(sync):.1f}%, "
          f"gen tok {sum(r['gen_tokens'] for r in sync) / len(sync):.0f}\n")
    print("| L s | sync | lag_mask | lag_trunc | mask gen tok | trunc gen tok | mask acc% | trunc acc% | mask wait s "
          "| trunc wait s | mask fewer tokens W/L, p | raw wall mask / trunc | copied-note tok mask / trunc |\n|" + "---|" * 13)
    for L in sorted(sweep):
        # sync blocks L s per real checker call; cached repeats (v3) return at once
        sw = sum(C_FIX + TOK_S * r["gen_tokens"] + L * (sum(r["verdicts"].values()) - r.get("cache_hits", 0))
                 for r in sync) / len(sync)
        m, t = ({r["id"]: r for r in map(json.loads, open(f))} if os.path.exists(f := f"{sweep[L]}/{c}.jsonl") else {}
                for c in ("lag_mask", "lag_trunc"))
        avg = lambda d, k, x=1: f"{x * sum(r[k] for r in d.values()) / len(d):.1f}" if d and k in next(iter(d.values())) else "-"
        model = lambda d: f"{sum(C_FIX + TOK_S * r['gen_tokens'] + r['wait_s'] for r in d.values()) / len(d):.1f}" if d else "-"
        ids = set(m) & set(t)
        w = sum(m[i]["gen_tokens"] < t[i]["gen_tokens"] for i in ids)
        l_ = sum(m[i]["gen_tokens"] > t[i]["gen_tokens"] for i in ids)
        print(f"| {L:g} | {sw:.1f} | {model(m)} | {model(t)} | {avg(m, 'gen_tokens')} | {avg(t, 'gen_tokens')} | "
              f"{avg(m, 'correct', 100)} | {avg(t, 'correct', 100)} | {avg(m, 'wait_s')} | {avg(t, 'wait_s')} | "
              f"{w}/{l_}, p={sign_p(w, l_):.3f} (n={len(ids)}) | {avg(m, 'wall_s')} / {avg(t, 'wall_s')} | "
              f"{avg(m, 'offformat_tokens')} / {avg(t, 'offformat_tokens')} |")
