"""ProverQA FOL -> Z3, and step checking.

Grammar seen in ProverQA-Hard: unary predicates, constants, ∀x, and ¬ ∧ ∨ ⊕ →.
Precedence (tight -> loose): ¬, ∧, ∨, ⊕, →(right-assoc). ↔ and ∃ accepted for model output.
"""
import re
import z3

Obj = z3.DeclareSort("Obj")
TOK = re.compile(r"\s*(∀|∃|¬|∧|∨|⊕|→|↔|\(|\)|,|[A-Za-z_][A-Za-z0-9_]*)")
ASCII = {"~": "¬", "!": "¬", "&": "∧", "|": "∨", "^": "⊕", "->": "→", "<->": "↔", "forall": "∀", "exists": "∃"}


class FolError(ValueError):
    pass


def tokenize(s):
    s = re.sub(r"(?<![\w])(forall|exists)(?![\w])", lambda m: ASCII[m.group(1)], s)
    for a in sorted((a for a in ASCII if not a.isalpha()), key=len, reverse=True):
        s = s.replace(a, ASCII[a])
    s = s.strip().rstrip(".")
    toks, i = [], 0
    while i < len(s):
        m = TOK.match(s, i)
        if not m:
            raise FolError(f"bad char {s[i]!r} in {s!r}")
        toks.append(m.group(1))
        i = m.end()
    return [t for t in toks if t]


class Parser:
    def __init__(self, s, preds, consts):
        self.t, self.i, self.preds, self.consts, self.vars = tokenize(s), 0, preds, consts, {}

    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else None

    def eat(self, tok=None):
        t = self.peek()
        if t is None or (tok and t != tok):
            raise FolError(f"expected {tok or 'token'}, got {t!r}")
        self.i += 1
        return t

    def parse(self):
        e = self.iff()
        if self.peek() is not None:
            raise FolError(f"trailing {self.t[self.i:]}")
        return e

    def iff(self):
        e = self.imp()
        while self.peek() == "↔":
            self.eat()
            e = e == self.imp()
        return e

    def imp(self):
        e = self.xor()
        if self.peek() == "→":
            self.eat()
            return z3.Implies(e, self.imp())
        return e

    def xor(self):
        e = self.disj()
        while self.peek() == "⊕":
            self.eat()
            e = z3.Xor(e, self.disj())
        return e

    def disj(self):
        e = self.conj()
        while self.peek() == "∨":
            self.eat()
            e = z3.Or(e, self.conj())
        return e

    def conj(self):
        e = self.unary()
        while self.peek() == "∧":
            self.eat()
            e = z3.And(e, self.unary())
        return e

    def unary(self):
        t = self.peek()
        if t == "¬":
            self.eat()
            return z3.Not(self.unary())
        if t in ("∀", "∃"):
            self.eat()
            name = self.eat()
            v = z3.Const(name, Obj)
            old = self.vars.get(name)
            self.vars[name] = v
            body = self.unary() if self.peek() != "(" else self.paren_or_atom()
            self.vars.pop(name) if old is None else self.vars.__setitem__(name, old)
            return (z3.ForAll if t == "∀" else z3.Exists)([v], body)
        return self.paren_or_atom()

    def paren_or_atom(self):
        if self.peek() == "(":
            self.eat("(")
            e = self.iff()
            self.eat(")")
            return e
        name = self.eat()
        if not re.match(r"[A-Za-z_]", name):
            raise FolError(f"unexpected {name!r}")
        self.eat("(")
        arg = self.eat()
        self.eat(")")
        if self.preds is not None and name not in self.preds:
            raise FolError(f"unknown predicate {name}")
        p = z3.Function(name, Obj, z3.BoolSort())
        if arg in self.vars:
            return p(self.vars[arg])
        if self.consts is not None and arg not in self.consts:
            raise FolError(f"unknown constant {arg}")
        return p(z3.Const(arg, Obj))


def symbols(fols):
    preds, consts = set(), set()
    for f in fols:
        for p, a in re.findall(r"([A-Za-z_][A-Za-z0-9_]*)\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)", f):
            preds.add(p)
            if not re.match(r"^[a-z]$", a):  # single lowercase letters are bound variables
                consts.add(a)
    return preds, consts


def parse(s, preds=None, consts=None):
    return Parser(s, preds, consts).parse()


class Problem:
    """Premises of one ProverQA item; checks candidate step formulas."""

    def __init__(self, item, timeout_ms=3000):
        fols = list(item["nl2fol"].values())
        self.preds, self.consts = symbols(fols + [item["conclusion_fol"]])
        self.premises = [parse(f) for f in fols]
        is_rule = [bool(set(tokenize(f)) & {"∀", "∃", "→", "∨", "⊕", "↔", "∧"}) for f in fols]
        self.rules = [p for p, r in zip(self.premises, is_rule) if r]
        self.facts = [p for p, r in zip(self.premises, is_rule) if not r]  # ground literals
        self.timeout_ms = timeout_ms

    def _check(self, *exprs):
        s = z3.Solver()
        s.set("timeout", self.timeout_ms)
        s.add(*exprs)
        return s.check()

    def _sat(self, extra):
        return self._check(*self.premises, extra)

    def supports(self, fol, extra):
        """Counterfactual reliance: would `fol` follow if the (refuted) formulas in `extra` were believed?
        The premises refute them, so adding them to the premises would make everything follow (ex falso). Instead:
        start from the rules plus `extra`, add each fact that stays consistent, and ask whether `fol` follows then
        while the real premises do not prove it. None on a parse error."""
        try:
            phi = parse(fol, self.preds, self.consts)
            base = self.rules + [parse(e, self.preds, self.consts) for e in extra]
        except FolError:
            return None
        if self._sat(z3.Not(phi)) == z3.unsat or self._check(*base) != z3.sat:
            return False  # true anyway / the believed formulas contradict the rules themselves
        for f in self.facts:
            if self._check(*base, f) == z3.sat:
                base.append(f)
        return self._check(*base, z3.Not(phi)) == z3.unsat

    def check(self, fol, facts_only=True):
        """-> 'entailed' | 'refuted' | 'unknown' | 'restated' | 'tautology' | 'not_fact' | 'parse_error:<msg>'
        facts_only=False checks any formula (rules, disjunctions, ...); restating a premise is then 'restated',
        so it cannot pass as a derivation."""
        try:
            phi = parse(fol, self.preds, self.consts)
            if facts_only and set(tokenize(fol)) & {"∀", "∃", "→", "∨", "⊕", "↔"}:
                return "not_fact"  # a step must state facts (literals joined by ∧), not restate rules
        except FolError as e:
            return f"parse_error:{e}"
        s = z3.Solver()
        s.add(z3.Not(phi))
        if s.check() == z3.unsat:  # vacuous step, e.g. (A∧R)→A (VeriCoT failure mode)
            return "tautology"
        if not facts_only:
            for p in self.premises:
                s = z3.Solver()
                s.set("timeout", self.timeout_ms)
                s.add(p != phi)
                if s.check() == z3.unsat:
                    return "restated"
        if self._sat(z3.Not(phi)) == z3.unsat:
            return "entailed"
        if self._sat(phi) == z3.unsat:
            return "refuted"
        return "unknown"

    def answer(self, conclusion_fol):
        r = self.check(conclusion_fol, facts_only=False)
        return {"entailed": "A", "refuted": "B", "unknown": "C"}.get(r, "?")


if __name__ == "__main__":
    import json
    import sys

    data = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "data/hard.json"))
    bad = [(x["id"], x["answer"], Problem(x).answer(x["conclusion_fol"])) for x in data]
    bad = [b for b in bad if b[1] != b[2]]
    print(f"z3 reproduces gold answer on {len(data) - len(bad)}/{len(data)}; mismatches: {bad[:10]}")
    p = Problem(data[0])
    assert p.check("is_champion(Legend)") == "entailed", p.check("is_champion(Legend)")
    assert p.check("is_fast(Legend)") == "refuted"
    assert p.check("has_strong_hooves(Legend)") == "unknown"
    assert p.check("made_up(Legend)").startswith("parse_error")
    rule = next(iter(data[0]["nl2fol"].values()))
    assert p.check(rule, facts_only=False) == "restated", p.check(rule, facts_only=False)
    assert p.check("is_champion(Legend) ∨ is_fast(Legend)") == "not_fact"
    assert p.check("is_champion(Legend) ∨ is_competitive(Legend)", facts_only=False) == "entailed"
    assert p.check("is_fast(Legend) ∨ ¬is_champion(Legend)", facts_only=False) == "refuted"
    # believing the refuted ¬is_champion makes is_fast follow (is_champion ∨ is_fast); hooves never follow from is_fast;
    # is_champion is proven by the premises anyway, so it relies on nothing
    assert p.supports("is_fast(Legend)", ["¬is_champion(Legend)"]) is True
    assert p.supports("has_strong_hooves(Legend)", ["is_fast(Legend)"]) is False
    assert p.supports("is_champion(Legend)", ["is_fast(Legend)"]) is False
    assert len(bad) <= len(data) * 0.02, "parser disagrees with gold labels"
    print("self-check ok")
