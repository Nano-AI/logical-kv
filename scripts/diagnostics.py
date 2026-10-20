"""Three fresh diagnostics on the existing logs (no model runs):
1. accuracy per gold class (A/B/C) per condition -- is 'Uncertain' the bottleneck?
2. answer/step consistency -- did the model derive the conclusion (or its negation) and still answer wrong?
3. hidden dependents in lag_mask -- kept steps that are NOT entailed by the premises alone but ARE entailed once
   the masked step's formula is added: they secretly relied on the refuted step and should have been masked too."""
import json
import os
import sys
from collections import Counter, defaultdict

import z3

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJ)
from logic import Problem, parse, FolError  # noqa: E402

DATA = {x["id"]: x for x in json.load(open(f"{PROJ}/data/hard.json"))}
MODELS = {"8B": f"{PROJ}/results/v2", "14B": f"{PROJ}/results_cloud/Qwen3-14B", "30B": f"{PROJ}/results_cloud/Qwen3-30B-A3B"}


def load(p):
    try:
        return [json.loads(l) for l in open(p)]
    except FileNotFoundError:
        return []


def entails(prob, extra, fol):
    s = z3.Solver()
    s.set("timeout", 3000)
    try:
        s.add(*prob.premises, *[parse(e, prob.preds, prob.consts) for e in extra], z3.Not(parse(fol, prob.preds, prob.consts)))
    except FolError:
        return None
    return s.check() == z3.unsat


def equiv(prob, a, b):
    s = z3.Solver()
    s.set("timeout", 3000)
    try:
        s.add(parse(a, prob.preds, prob.consts) != parse(b, prob.preds, prob.consts))
    except FolError:
        return False
    return s.check() == z3.unsat


print("## 1. accuracy by gold class (A=True B=False C=Uncertain)")
for m, d in MODELS.items():
    conds = {"base": f"{PROJ}/results/base.jsonl" if m == "8B" else f"{d}/base.jsonl",
             "fmt": f"{PROJ}/results/fmt.jsonl" if m == "8B" else f"{d}/fmt.jsonl",
             "sync": f"{d}/sync.jsonl", "trunc L8": f"{d}/lat8/lag_trunc.jsonl", "mask L8": f"{d}/lat8/lag_mask.jsonl"}
    for c, p in conds.items():
        rs = load(p)
        if not rs:
            continue
        by = defaultdict(lambda: [0, 0])
        pred = Counter(r["pred"] for r in rs)
        for r in rs:
            by[r["gold"]][0] += r["pred"] == r["gold"]
            by[r["gold"]][1] += 1
        print(f"{m:>3} {c:<9} " + "  ".join(f"{g}: {by[g][0]:>2}/{by[g][1]:<2} ({100 * by[g][0] / by[g][1]:3.0f}%)" for g in "ABC")
              + f"   predicted A/B/C = {pred['A']}/{pred['B']}/{pred['C']}")

print("\n## 2. answer vs own derived steps (fmt / sync): conclusion or its negation derived as an accepted/unchecked step")
for m, d in MODELS.items():
    for c in ("fmt", "sync"):
        p = f"{PROJ}/results/{c}.jsonl" if m == "8B" else f"{d}/{c}.jsonl"
        rs = load(p)
        if not rs:
            continue
        derived = wrong_after = mismatch = 0
        for r in rs:
            item, prob = DATA[r["id"]], Problem(DATA[r["id"]])
            goal = item["conclusion_fol"]
            implied = None
            for s in r.get("steps", []):
                if s.get("verdict") != "entailed" or not s.get("fol"):
                    continue
                if equiv(prob, s["fol"], goal):
                    implied = "A"
                elif equiv(prob, s["fol"], f"¬({goal})"):
                    implied = "B"
            if implied:
                derived += 1
                if r["pred"] != implied:
                    mismatch += 1
                    wrong_after += r["pred"] != r["gold"]
        print(f"{m:>3} {c:<5} derived the goal or its negation in {derived}/{len(rs)} problems; answered differently in {mismatch}, of which {wrong_after} wrong")

print("\n## 3. hidden dependents in lag_mask (kept step not entailed alone, entailed with the masked formulas)")
for m, d in MODELS.items():
    for L in (1, 3, 8):
        rs = load(f"{d}/lat{L}/lag_mask.jsonl")
        if not rs:
            continue
        kept_n = hidden = same = probs_hidden = 0
        acc_h = [0, 0]
        acc_nh = [0, 0]
        for r in rs:
            prob = Problem(DATA[r["id"]])
            steps = {s["id"]: s for s in r.get("steps", [])}
            h_here = 0
            for s in r.get("steps", []):
                if not s.get("kept_after"):
                    continue
                bad = [steps[i]["fol"] for i in s.get("masked_with", [s["id"]]) if steps[i].get("fol")]
                for k in s["kept_after"]:
                    ks = steps[k]
                    if ks.get("status") == "note" or not ks.get("fol"):
                        continue
                    kept_n += 1
                    if any(equiv(prob, ks["fol"], b) for b in bad):
                        same += 1
                        h_here += 1
                    elif ks.get("verdict") != "entailed" and prob.supports(ks["fol"], bad):
                        hidden += 1
                        h_here += 1
            if any(s.get("kept_after") for s in r.get("steps", [])):
                a = acc_h if h_here else acc_nh
                a[0] += r["pred"] == r["gold"]
                a[1] += 1
            probs_hidden += bool(h_here)
        print(f"{m:>3} L={L}: kept steps after a mask {kept_n:>3}; restate the masked formula {same:>2}; "
              f"secretly rely on it {hidden:>2}; problems affected {probs_hidden:>2}/{len(rs)} | "
              f"acc with hidden dep {acc_h[0]}/{acc_h[1]} vs masked-but-clean {acc_nh[0]}/{acc_nh[1]}")

print("\n## 4. on the problems where mask kept a hidden dependent: mask vs trunc vs sync accuracy (same problems)")
for m, d in MODELS.items():
    for L in (1, 3, 8):
        rs = load(f"{d}/lat{L}/lag_mask.jsonl")
        if not rs:
            continue
        tr = {r["id"]: r for r in load(f"{d}/lat{L}/lag_trunc.jsonl")}
        sy = {r["id"]: r for r in load(f"{d}/sync.jsonl")}
        ids = []
        for r in rs:
            prob = Problem(DATA[r["id"]])
            steps = {s["id"]: s for s in r.get("steps", [])}
            hit = False
            for s in r.get("steps", []):
                if not s.get("kept_after"):
                    continue
                bad = [steps[i]["fol"] for i in s.get("masked_with", [s["id"]]) if steps[i].get("fol")]
                for k in s["kept_after"]:
                    ks = steps[k]
                    if ks.get("status") != "note" and ks.get("fol") and ks.get("verdict") != "entailed" and prob.supports(ks["fol"], bad):
                        hit = True
            if hit:
                ids.append(r["id"])
        mk = {r["id"]: r for r in rs}
        acc = lambda R: sum(R[i]["pred"] == R[i]["gold"] for i in ids if i in R)
        print(f"{m:>3} L={L}: n={len(ids):>2}  mask {acc(mk):>2}  trunc {acc(tr):>2}  sync {acc(sy):>2}")
