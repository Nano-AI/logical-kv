"""Round 6: five more models at n=30 (Llama 3.1 8B, Phi-4, Mistral Small 24B, Qwen3-32B, Qwen3-4B), the v2 condition set.
Prints the RESULTS.md tables: accuracy per condition, async-vs-blocking and mask-vs-trunc savings with paired sign tests."""
import json, os
from math import comb

P = "results_cloud"
TOK_S, FIXED = 0.0724, 8.6  # token clock; modeled time = FIXED + TOK_S*gen + waits
MODELS = ["Llama-3.1-8B", "Phi-4", "Mistral-Small-24B", "Qwen3-32B", "Qwen3-4B"]


def load(p):
    return {r["id"]: r for r in (json.loads(l) for l in open(p) if l.strip())} if os.path.exists(p) else {}


def sign_p(w, l):  # two-sided exact sign test
    n, k = w + l, min(w, l)
    return 1.0 if n == 0 else min(1.0, 2 * sum(comb(n, i) for i in range(k + 1)) / 2 ** n)


def t_async(r):
    return FIXED + TOK_S * r["gen_tokens"] + r.get("wait_s", 0)


def t_sync(r, L):
    return FIXED + TOK_S * r["gen_tokens"] + L * (sum(r["verdicts"].values()) - r.get("cache_hits", 0))


def wl(a, b, ids):  # accuracy wins/losses of a over b
    return sum(a[i]["correct"] and not b[i]["correct"] for i in ids), sum(b[i]["correct"] and not a[i]["correct"] for i in ids)


pooled = {}
print("### Accuracy (correct of 30; checked conditions at L=8)\n")
print("| Model | base | fmt | sync | trunc | mask | refresh | fmt vs base | sync vs fmt | mask vs fmt | mask vs base |")
print("|---|---|---|---|---|---|---|---|---|---|---|")
for m in MODELS:
    d = {c: load(f"{P}/{m}/{c}.jsonl") for c in ("base", "fmt", "sync")}
    d |= {c: load(f"{P}/{m}/lat8/lag_{c}.jsonl") for c in ("trunc", "mask", "refresh")}
    ids = sorted(set.intersection(*(set(v) for v in d.values())))
    acc = {c: f"{100 * sum(d[c][i]['correct'] for i in ids) / len(ids):.1f}" for c in d}
    tests = []
    for a, b in (("fmt", "base"), ("sync", "fmt"), ("mask", "fmt"), ("mask", "base")):
        w, l = wl(d[a], d[b], ids)
        tests.append(f"{w}/{l} p={sign_p(w, l):.2f}")
        key = "qwen" if m.startswith("Qwen") else "other"
        pooled.setdefault((key, a, b), [0, 0]); pooled[(key, a, b)][0] += w; pooled[(key, a, b)][1] += l
    print(f"| {m} | " + " | ".join(acc[c] for c in ("base", "fmt", "sync", "trunc", "mask", "refresh")) + " | " + " | ".join(tests) + " |")
print("\nPooled (wins/losses, two-sided sign test):\n")
for key in ("other", "qwen"):
    name = "Llama + Phi-4 + Mistral" if key == "other" else "Qwen3-32B + Qwen3-4B"
    print(f"- {name}: " + "; ".join(f"{a} vs {b} {w}/{l} p={sign_p(w, l):.3f}" for (k, a, b), (w, l) in pooled.items() if k == key))

print("\n### Systems (modeled seconds per problem; paired sign tests on per-problem time)\n")
print("| Model | L | sync | trunc | mask | async saving (trunc vs sync) | mask vs trunc | mask acc − trunc acc |")
print("|---|---|---|---|---|---|---|---|")
for m in MODELS:
    sync = load(f"{P}/{m}/sync.jsonl")
    for L in (1, 3, 8):
        tr, mk = load(f"{P}/{m}/lat{L}/lag_trunc.jsonl"), load(f"{P}/{m}/lat{L}/lag_mask.jsonl")
        ids = sorted(set(tr) & set(mk) & set(sync))
        ts, tt, tm = ([f(x) for x in ids] for f in (lambda i: t_sync(sync[i], L), lambda i: t_async(tr[i]), lambda i: t_async(mk[i])))
        ms = lambda x: sum(x) / len(x)
        aw, al = sum(a < b for a, b in zip(tt, ts)), sum(a > b for a, b in zip(tt, ts))
        mw, ml = sum(a < b for a, b in zip(tm, tt)), sum(a > b for a, b in zip(tm, tt))
        cw, cl = wl(mk, tr, ids)
        dacc = 100 * (sum(mk[i]["correct"] for i in ids) - sum(tr[i]["correct"] for i in ids)) / len(ids)
        print(f"| {m} | {L} | {ms(ts):.1f} | {ms(tt):.1f} | {ms(tm):.1f} | −{100 * (1 - ms(tt) / ms(ts)):.0f}% ({aw}/{al} p={sign_p(aw, al):.3f}) | "
              f"{100 * (1 - ms(tm) / ms(tt)):+.1f}% ({mw}/{ml} p={sign_p(mw, ml):.2f}) | {dacc:+.1f} ({cw}/{cl} p={sign_p(cw, cl):.2f}) |")
