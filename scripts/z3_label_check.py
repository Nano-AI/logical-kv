"""Sanity check: does Z3 over ProverQA nl2fol reproduce gold labels?
True(A) iff premises |= c; False(B) iff premises |= not c; else Uncertain(C).
Usage: python3 -I z3_label_check.py path/to/hard.json
"""
import json, re, sys, collections
import z3

U = z3.DeclareSort("U")
preds, consts = {}, {}
TOK = re.compile(r"\s*(∀|∃|¬|∧|∨|→|↔|⊕|\(|\)|,|\w+)")


def parse(s):
    toks = TOK.findall(s)
    assert "".join(toks) == re.sub(r"\s+", "", s), s
    pos = 0
    def peek(): return toks[pos] if pos < len(toks) else None
    def eat(t=None):
        nonlocal pos
        tok = toks[pos]; assert t is None or tok == t, (t, tok, s); pos += 1; return tok
    # precedence (low->high): ↔ → ⊕ ∨ ∧ ; → right-assoc
    def iff(env):
        a = imp(env)
        while peek() == "↔": eat(); a = a == imp(env)
        return a
    def imp(env):
        a = xor(env)
        if peek() == "→": eat(); return z3.Implies(a, imp(env))
        return a
    def xor(env):
        a = disj(env)
        while peek() == "⊕": eat(); a = z3.Xor(a, disj(env))
        return a
    def disj(env):
        a = conj(env)
        while peek() == "∨": eat(); a = z3.Or(a, conj(env))
        return a
    def conj(env):
        a = unary(env)
        while peek() == "∧": eat(); a = z3.And(a, unary(env))
        return a
    def unary(env):
        t = peek()
        if t == "¬": eat(); return z3.Not(unary(env))
        if t in ("∀", "∃"):
            eat(); v = eat(); x = z3.Const(v, U)
            body = unary({**env, v: x})  # quantifier scopes over next unary (parenthesised body)
            return z3.ForAll([x], body) if t == "∀" else z3.Exists([x], body)
        if t == "(":
            eat(); a = iff(env); eat(")"); return a
        name = eat(); eat("("); args = [eat()]
        while peek() == ",": eat(); args.append(eat())
        eat(")")
        f = preds.setdefault((name, len(args)), z3.Function(name, *([U] * len(args)), z3.BoolSort()))
        return f(*[env[a] if a in env else consts.setdefault(a, z3.Const("c_" + a, U)) for a in args])
    out = iff({}); assert pos == len(toks), s
    return out


def entails(prem, goal):
    sv = z3.Solver(); sv.set("timeout", 10000); sv.add(*prem); sv.add(z3.Not(goal))
    return sv.check()


def label(prem, c):
    t, f = entails(prem, c), entails(prem, z3.Not(c))
    if t == z3.unsat and f == z3.unsat: return "INCONSISTENT"
    if t == z3.unsat: return "A"
    if f == z3.unsat: return "B"
    if z3.unknown in (t, f): return "UNKNOWN"
    return "C"


if __name__ == "__main__":
    assert label([parse("∀x (p(x) → q(x))"), parse("p(a)")], parse("q(a)")) == "A"
    assert label([parse("p(a) ⊕ q(a)"), parse("p(a)")], parse("q(a)")) == "B"
    assert label([parse("p(a) ∨ q(a)")], parse("q(a)")) == "C"
    data = json.load(open(sys.argv[1]))
    res, bad = collections.Counter(), []
    for ex in data:
        preds.clear(); consts.clear()
        try:
            got = label([parse(v) for v in ex["nl2fol"].values()], parse(ex["conclusion_fol"]))
        except Exception as e:
            got = "PARSE_ERR"
        res[(ex["answer"], got)] += 1
        if got != ex["answer"]: bad.append((ex["id"], ex["answer"], got))
    agree = sum(v for (g, p), v in res.items() if g == p)
    print(f"agree {agree}/{len(data)}", dict(res))
    print("first mismatches:", bad[:15])
