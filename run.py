"""Qwen3-8B (llama.cpp, Metal) on ProverQA-Hard under six conditions.

  base         ProverQA's own 2-shot CoT prompt (opendatalab/ProverGen), no tools                  (A)
  fmt          structured "Step k [uses ...]" + FOL lines, no checker; Z3 verdicts logged only     (B)
  sync         fmt + Z3 check right after each step (LogicTrack policy: crop to the step start and
               regenerate, at most 2 regenerations, then force the best candidate forward)         (C)
  lag_trunc    fmt + Z3 check trailing LAG steps behind; reject -> crop KV to the rejected step's start
  lag_mask     fmt + Z3 check trailing LAG steps behind; reject -> drop the rejected step and its
               dependency-DAG descendants from the KV cache (= -inf attention for every future
               token); later independent steps stay in place, KV untouched                         (D, ours)
  lag_refresh  lag_mask + recompute the KV of the kept later steps (DRed-style selective refresh),
               so the cache equals a cold restart from the visible transcript

Lagged conditions share one failure policy: 3 consecutive rejections -> back up to the last accepted
step. Every checked condition stops at MAX_REJECT rejections and is forced to answer.
At answer time the lagged conditions also run a rollback-consistency probe: answer distribution from
the real cache vs from a clean re-prefill of the visible transcript (Aborted but Not Forgotten, §3).

Env: LATENCY=<s>  lagged verdicts arrive <s> seconds after a step is submitted, decoding continues meanwhile
                 (parallel checker pool; Z3 itself is ~ms, the latency is simulated). Time runs on a token clock,
                 decoded tokens x TOK_S, so the sweep is deterministic and immune to machine load.
                 Unset = the fixed LAG-steps schedule used for the first n=30 runs.
     REALTIME=1    LATENCY on the wall clock instead (real sleeps).
     MASK_ON=refuted  checked conds reject (mask / truncate / regenerate) only steps Z3 refutes; unverifiable
                 ones (unknown / bad formula) stay visible as "kept". Default: any non-entailed step is rejected.
     NOTE=specific  the checker note states the verdict ("the premises prove it false") instead of the
                 generic "it does not follow from the premises", which reads as "uncertain" and biased answers to C.
     GUARD=1       a chunk that starts with neither "Step" nor "Answer" (mostly the model copying the checker
                 note, which then got rejected and triggered another note) is cut after a few characters,
                 cropped, and regenerated with "Step" forced. Its tokens still count as generated and wasted.
     GRAMMAR=1     the FOL line is generated under a GBNF: ∧-joined literals over the problem's own symbols.
     OUT=<dir>     results directory.
     CHECK_ALL=1   the checker verifies any formula (rules, disjunctions), not only facts; a step equivalent to a
                 premise is 'restated'. Default: non-fact formulas are 'not_fact' and never verified.
     PROBE=0       skip the rollback-consistency probe (a measurement: one cold re-prefill per problem).
     MAX_STEPS / MAX_GEN / BASE_MAX   caps; v3 runs raise them to safety limits so answers are not cut off.
     CACHE=1       a formula already checked in this problem reuses its verdict without checker latency (cache_hits).
     INFER=1       lag_mask/lag_refresh also mask later steps the solver says rest on the refuted one (not proven by
                 the premises, proven if the refuted formula is believed), not only those that declared it in [uses].
     RETRY=1       after a mask, the next chunk is forced to start with "Step" (one retry before the model may answer).
     DEPWAIT=1     at the Answer line, wait only for pending verdicts of steps the answer rests on (the last live step
                 and its declared ancestors); the others are left unchecked (unwaited).
     HYBRID=<tok>  lag_mask/lag_refresh truncate instead when fewer than <tok> tokens would be kept (hybrid_truncs).
     LOOP=<k>      the k-th live occurrence of a formula is cropped with a note instead of being checked (loops);
                 MAX_LOOPS of them force the answer.

usage: python run.py --cond lag_mask [--n 30]      python run.py --summary      python run.py --spike
"""
import argparse
import json
import os
import random
import re
import sys
import time
from difflib import SequenceMatcher

from logic import Problem

MODEL = os.environ.get("MODEL", "models/qwen3-8b-q4_k_m.gguf")
DATA = "data/hard.json"
OUT = os.environ.get("OUT", "results")
BAD_GOLD = {411, 473}  # z3 on gold FOL disagrees with the gold label
LAG = 2
LATENCY = float(os.environ["LATENCY"]) if os.environ.get("LATENCY") else None
REALTIME = bool(os.environ.get("REALTIME"))
MASK_ON = os.environ.get("MASK_ON", "any")
NOTE = os.environ.get("NOTE", "generic")
GUARD = bool(os.environ.get("GUARD"))
STEP_START = re.compile(r"\s*[*#]*\s*(Step|(Final )?Answer)")
WHY = {"refuted": "the premises prove it false", "unknown": "the premises neither prove nor refute it",
       "repeat": "it repeats an earlier step"}
TOK_S = 0.0724  # s per decoded token: round-1 lagged runs on an idle machine fit wall = 8.6 s + 72.4 ms x gen_tokens
GRAMMAR = bool(os.environ.get("GRAMMAR"))
SYNC_ATTEMPTS = 3      # LogicTrack: first try + at most 2 regenerations per step
MAX_CONSEC = 3         # lagged: consecutive rejections before backing up to the last accepted step
MAX_REJECT = 8
MAX_BACKUPS = 2       # lagged: a branch that needed 2 back-ups is ended and the model must answer
MAX_STEPS = int(os.environ.get("MAX_STEPS", 20))
MAX_GEN = int(os.environ.get("MAX_GEN", 2500))
BASE_MAX = int(os.environ.get("BASE_MAX", 1500))  # ProverGen used 1024; we allow more and log truncation
CHECK_ALL = bool(os.environ.get("CHECK_ALL"))
CACHE = bool(os.environ.get("CACHE"))
INFER = bool(os.environ.get("INFER"))
RETRY = bool(os.environ.get("RETRY"))
DEPWAIT = bool(os.environ.get("DEPWAIT"))
HYBRID = int(os.environ.get("HYBRID", 0))
LOOP = int(os.environ.get("LOOP", 0))
MAX_LOOPS = 3
PROBE = os.environ.get("PROBE", "1") == "1"
GREEDY = dict(temp=0.0)
HOT = dict(temp=0.7, top_p=0.8, top_k=20, min_p=0.0)  # Qwen3 non-thinking recommended sampling
CONDS = ["base", "fmt", "sync", "lag_trunc", "lag_mask", "lag_refresh"]
LIVE = ("pending", "accepted", "unchecked", "forced", "kept")
VISIBLE = LIVE + ("note",)
RANK = {"entailed": 4, "unknown": 3, "restated": 3, "refuted": 2, "tautology": 1, "not_fact": 1}  # LogicTrack: undecided > refuted

STEP_RE = re.compile(r"Step\s*(\d+)\s*(?:\[([^\]]*)\])?\s*:\s*(.*)")
FOL_RE = re.compile(r"FOL:\s*(.+)")
ANS_RE = re.compile(r"Answer:\s*\**\s*\(?([ABC])\b")

EXAMPLE = """Premises:
P1: Tom is a cat. | FOL: is_cat(Tom)
P2: All cats are mammals. | FOL: ∀x (is_cat(x) → is_mammal(x))
P3: Tom is either a mammal or a reptile, but not both. | FOL: is_mammal(Tom) ⊕ is_reptile(Tom)
P4: Sue is a dog. | FOL: is_dog(Sue)
Question: Is the following statement true, false, or uncertain? Tom is a reptile.

Step 1 [uses P1, P2]: Tom is a mammal.
FOL: is_mammal(Tom)
Step 2 [uses S1, P3]: Tom is not a reptile.
FOL: ¬is_reptile(Tom)
Answer: B"""


def step_prompt(item):
    prem = "\n".join(f"P{i}: {nl} | FOL: {fol}" for i, (nl, fol) in enumerate(item["nl2fol"].items(), 1))
    return f"""Solve the logic problem by deriving new facts step by step.

Write every step as exactly two lines:
Step k [uses P#, S#]: <one new fact, in plain English>
FOL: <the same fact as a formula>
- [uses ...] lists every premise (P#) and earlier step (S#) the step relies on.
- The FOL line may only use predicate and constant names that appear in the premises. Use ¬ for "not".
- Stop once the statement in the question or its negation is derived, then write one final line:
Answer: A   (if the statement is true)
Answer: B   (if the statement is false)
Answer: C   (if it is uncertain, i.e. neither it nor its negation follows)

Example:
{EXAMPLE}

Now solve this problem.
Premises:
{prem}
Question: {item['question']}
Options: {' '.join(item['options'])}
"""


def base_messages(item):
    """ProverGen evaluation.py (CoT): system msg + 2-shot hard_CoT user template, copied verbatim."""
    raw = open("papers/proverqa_prompt.txt").read()
    system = raw.split("### BEGIN SYSTEM\n")[1].split("\n### END SYSTEM")[0]
    user = raw.split("### BEGIN USER\n")[1].split("\n### END USER")[0]
    user = (user.replace("[[CONTEXT]]", item["context"].strip()).replace("[[QUESTION]]", item["question"].strip())
            .replace("[[OPTIONS]]", "\n".join(o.strip() for o in item["options"])))
    return system, user


def fol_grammar(prob):
    """GBNF for a fact: 1-3 (¬)pred(const) literals joined by ∧, using only the problem's predicates and constants.
    The leading space is generated, not forced: Qwen tokenizes 'FOL: ¬p' as 'FOL:' ' ¬' 'p', so a forced
    'FOL: ' leaves the model at an unnatural token boundary (it then dropped/added ¬ at random).
    Trailing spaces allowed (the model ends lines with '  \\n'; otherwise ' ' is forced into ' ∧ ' forever)."""
    alt = lambda xs: " | ".join(f'"{x}"' for x in sorted(xs))
    return (f'root ::= " " lit (" ∧ " lit)? (" ∧ " lit)? " "* "\\n"\nlit ::= "¬"? pred "(" const ")"\n'
            f"pred ::= {alt(prob.preds)}\nconst ::= {alt(prob.consts)}\n")


# chat template by model file name: (bos, system wrapper, user open, user close + assistant open, end-of-turn token).
# The last entry (Qwen3) is the default: ChatML with an empty think block = non-thinking mode.
TEMPLATES = {
    "llama-3": ("<|begin_of_text|>", "<|start_header_id|>system<|end_header_id|>\n\n{}<|eot_id|>",
                "<|start_header_id|>user<|end_header_id|>\n\n", "<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n", "<|eot_id|>"),
    "phi-4": ("", "<|im_start|>system<|im_sep|>{}<|im_end|>", "<|im_start|>user<|im_sep|>", "<|im_end|><|im_start|>assistant<|im_sep|>", "<|im_end|>"),
    "mistral": ("<s>", "[SYSTEM_PROMPT]{}[/SYSTEM_PROMPT]", "[INST]", "[/INST]", "</s>"),
    "": ("", "<|im_start|>system\n{}<|im_end|>\n", "<|im_start|>user\n", "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n", "<|im_end|>"),
}
TPL = next(v for k, v in TEMPLATES.items() if k in os.path.basename(MODEL).lower())


def chat(user, system=None):
    bos, sys_t, u_open, u_close, _ = TPL
    return bos + (sys_t.format(system) if system else "") + u_open + user + u_close


def extract_answer(text):
    """JSON 'answer' field (ProverGen format), then answer-ish patterns; None = parse failure (scored wrong)."""
    m = re.search(r"\{.*\}", text, flags=re.S)
    if m:
        try:
            a = str(json.loads(m.group(0)).get("answer", "")).strip().upper()[:1]
            if a and a in "ABC":
                return a
        except (json.JSONDecodeError, AttributeError):
            pass
    for pat in (r'"answer"\s*:\s*"\(?([ABC])', r"Answer\W{0,20}\(?([ABC])\b", r"correct option is\W{0,10}\(?([ABC])\b"):
        found = re.findall(pat, text, flags=re.I)
        if found:
            return found[-1].upper()
    return None


def norm(s):
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9 ]", " ", s.lower())).strip()


def gold_claims(item):
    claims = [s for s in re.split(r"(?<=\.)\s+", item["context"]) if s]
    claims += re.findall(r"conclusion:\s*(.+)", item["reasoning"])
    return [norm(c) for c in claims]


class Run:
    def __init__(self, llm, item, cond):
        self.llm, self.item, self.cond = llm, item, cond
        self.prob = Problem(item)
        self.steps, self.pending, self.attempts = [], [], []
        self.last_accepted_end = None
        self.consecutive = 0
        self.hot = False
        self.retry = False
        self.probe = None
        self.text = None
        self.s = dict(prefill_tokens=0, gen_tokens=0, wasted_tokens=0, salvaged_tokens=0, recomputed_tokens=0,
                      rejections=0, masks=0, truncations=0, backups=0, forced_steps=0, forced_answer=0,
                      wait_s=0.0, offformat_tokens=0, truncated_output=False, verdicts={}, cache_hits=0, cap=None,
                      ctx_pos_peak=0, ctx_cells_peak=0, ctx_cells_final=0, inferred=0, unwaited=0, hybrid_truncs=0,
                      loops=0)
        self.vcache = {}
        self.removed = []  # masked [a, b) position ranges below n_tokens: their KV cells are freed
        eot = llm.tokenize(TPL[4].encode(), add_bos=False, special=True)  # one id when the vocab knows the token
        self.stop_ids = {llm.token_eos(), *(eot if len(eot) == 1 else [])}
        if GRAMMAR:
            from llama_cpp import LlamaGrammar
            self.grammar = LlamaGrammar.from_string(fol_grammar(self.prob))

    # --- llama.cpp primitives -------------------------------------------------
    def tok(self, text):
        return self.llm.tokenize(text.encode(), add_bos=False, special=True)

    def detok(self, toks):
        return self.llm.detokenize(toks).decode("utf-8", errors="ignore")

    def live_cells(self):
        """KV cells actually held: positions in use minus masked ranges (llama.cpp exposes no used-cell count)."""
        n = self.llm.n_tokens
        return n - sum(min(b, n) - a for a, b in self.removed if a < n)

    def ctx_tick(self):
        self.s["ctx_pos_peak"] = max(self.s["ctx_pos_peak"], self.llm.n_tokens)
        self.s["ctx_cells_peak"] = max(self.s["ctx_cells_peak"], self.live_cells())

    def ctx_final(self):
        """context held when the answer is given (before any probe re-prefill)"""
        self.ctx_tick()
        self.s["ctx_cells_final"] = self.live_cells()

    def trim_removed(self):
        """positions >= n_tokens will be rewritten, so masked ranges there no longer free anything"""
        n = self.llm.n_tokens
        self.removed = [(a, min(b, n)) for a, b in self.removed if a < n]

    def generate(self, stop, max_new, grammar=None):
        params = HOT if self.hot else GREEDY
        smp = self.llm._init_sampler(**params, grammar=grammar) if grammar else None  # sample() also accepts
        out = []
        for _ in range(max_new):
            t = smp.sample(self.llm._ctx, -1) if smp else self.llm.sample(**params)
            if t in self.stop_ids:
                return self.detok(out), out, False
            out.append(t)
            self.llm.eval([t])
            self.s["gen_tokens"] += 1
            self.ctx_tick()
            if stop and stop(self.detok(out)):
                return self.detok(out), out, False
        return self.detok(out), out, True

    def refeed(self, step):
        """Recompute a kept chunk's KV at the current end of the cache."""
        step["start"] = self.llm.n_tokens
        self.llm.eval(step["toks"])
        step["end"] = self.llm.n_tokens
        self.s["recomputed_tokens"] += len(step["toks"])

    def mask(self, a, b):
        """-inf attention for every future token: drop KV cells in [a, b); later positions unchanged.
        llama.cpp requires new positions to follow the last cached one, so a masked tail is reused."""
        import llama_cpp
        self.llm._ctx.kv_cache_seq_rm(-1, a, b)
        self.removed.append((a, b))
        last = llama_cpp.llama_memory_seq_pos_max(llama_cpp.llama_get_memory(self.llm._ctx.ctx), 0)
        self.llm.n_tokens = min(self.llm.n_tokens, last + 1)
        self.trim_removed()
        self.fresh_logits()

    def crop(self, p):
        """Truncate: the next eval() overwrites from position p."""
        self.llm.n_tokens = p
        self.trim_removed()
        self.fresh_logits()

    def fresh_logits(self):
        """sample() reads the logits of the last eval; after a crop/mask those are stale, so recompute the
        last kept token (it now also sees the edited cache)."""
        p = self.llm.n_tokens
        last = int(self.llm.input_ids[p - 1])
        self.llm.n_tokens = p - 1
        self.llm.eval([last])

    def note(self, step):
        """Checker feedback appended at the end of the cache (LogicTrack regenerates with feedback)."""
        why = (WHY.get(step["verdict"], "its FOL line is not a single fact") if NOTE == "specific" or step["verdict"] == "repeat"
               else "it does not follow from the premises")
        text = f'(Checker: rejected "{step["claim"][:120]}" - {why}. Derive a different fact, or write the Answer line if nothing more can be derived.)\n'
        n = dict(start=self.llm.n_tokens, text=text, toks=self.tok(text), id=len(self.steps), num=None, uses="",
                 parents=[], claim="", fol=None, status="note", verdict=None)
        self.llm.eval(n["toks"])
        n["end"] = self.llm.n_tokens
        self.steps.append(n)

    # --- driver -----------------------------------------------------------------
    def run(self):
        t0 = time.time()
        self.llm.reset()
        self.llm._ctx.kv_cache_clear()
        if self.cond == "base":
            system, user = base_messages(self.item)
            self.prompt_toks = self.tok(chat(user, system))
            self.llm.eval(self.prompt_toks)
            self.s["prefill_tokens"] = len(self.prompt_toks)
            self.text, _, self.s["truncated_output"] = self.generate(None, BASE_MAX)
            self.ctx_final()
            pred = extract_answer(self.text)
        else:
            self.prompt_toks = self.tok(chat(step_prompt(self.item)))
            self.llm.eval(self.prompt_toks)
            self.s["prefill_tokens"] = len(self.prompt_toks)
            self.prompt_end = self.llm.n_tokens
            pred = self.step_loop()
        self.s["wall_s"] = round(time.time() - t0 - (self.probe or {}).get("probe_s", 0), 2)
        return pred

    def step_loop(self):
        while True:
            live = [s for s in self.steps if s["status"] in LIVE]
            caps = dict(gen=self.s["gen_tokens"] >= MAX_GEN, steps=len(live) >= MAX_STEPS,
                        rejections=self.s["rejections"] >= MAX_REJECT, backups=self.s["backups"] >= MAX_BACKUPS,
                        loops=self.s["loops"] >= MAX_LOOPS)
            if any(caps.values()):
                self.s["cap"] = next(k for k, v in caps.items() if v)
                return self.force_answer()
            start = self.llm.n_tokens
            text, toks = self.gen_chunk()
            chunk = dict(start=start, end=self.llm.n_tokens, text=text, toks=toks)
            ans = ANS_RE.search(text)
            if ans:
                if self.cond.startswith("lag"):
                    if not self.flush(chunk):
                        continue
                self.ctx_final()
                if self.cond.startswith("lag") and PROBE:
                    self.probe = self.consistency_probe(chunk["start"])
                return ans.group(1)
            if not text.strip():
                return self.force_answer()
            step = self.new_step(chunk)
            if LOOP and self.looped(step):
                continue
            if self.cond == "fmt":
                step["verdict"] = self.check(step)
                step["status"] = "unchecked"
            elif self.cond == "sync":
                self.sync_check(step)
            else:
                self.pending.append(step)
                if LATENCY is None:
                    while len(self.pending) > LAG:
                        self.verify(self.pending[0])
                else:  # verdicts that have arrived by this step boundary, oldest first
                    step["due"] = self.now() + (0 if self.cached(step) else LATENCY)
                    while self.pending and self.pending[0]["due"] <= self.now():
                        self.verify(self.pending[0])

    def looped(self, step):
        """LOOP=k: the k-th live occurrence of a formula is a loop, not a derivation. It is the tail of the cache, so
        cropping it is exact and free; a note says so. No verdict is needed, so no checker latency either."""
        key = re.sub(r"\s+", "", step["fol"] or "")
        earlier = sum(1 for s in self.steps if s is not step and s["status"] in LIVE and re.sub(r"\s+", "", s["fol"] or "") == key)
        if not key or earlier < LOOP - 1:
            return False
        self.s["loops"] += 1
        step["status"], step["verdict"], step["gone"] = "looped", "repeat", True
        self.s["wasted_tokens"] += step["end"] - step["start"]
        self.crop(step["start"])
        self.note(step)
        return True

    def gen_guarded(self, stop):
        if self.retry:  # RETRY=1: the chunk after a mask must be a step; left free, the 8B mostly wrote the Answer line
            self.retry = False
            head = self.tok("Step")
            self.llm.eval(head)
            text, toks, _ = self.generate(stop, 160)
            return "Step" + text, head + toks
        start = self.llm.n_tokens
        off = lambda t: GUARD and len(t.strip()) >= 8 and not STEP_START.match(t)
        text, toks, _ = self.generate(lambda t: off(t) or stop(t), 160)
        if not off(text):
            return text, toks
        self.s["offformat_tokens"] += len(toks)
        self.s["wasted_tokens"] += len(toks)
        self.crop(start)
        head = self.tok("Step")
        self.llm.eval(head)
        text, toks, _ = self.generate(stop, 160)
        return "Step" + text, head + toks

    def now(self):
        """checker clock: decoded tokens x TOK_S + waits, or the wall clock if REALTIME"""
        return time.time() if REALTIME else self.s["gen_tokens"] * TOK_S + self.s["wait_s"]

    def gen_chunk(self):
        """One step (or the Answer line). GRAMMAR: free step line, then forced 'FOL:' + constrained formula."""
        stop = lambda t: re.search(r"FOL:[^\n]*\n", t) or ANS_RE.search(t) or t.count("\n") >= 4
        if not GRAMMAR:
            return self.gen_guarded(stop)
        text, toks = self.gen_guarded(lambda t: stop(t) or re.search(r"Step[^\n]*:[^\n]*\n", t))
        if ANS_RE.search(text) or "FOL:" in text or not STEP_RE.search(text) or not text.endswith("\n"):
            return text, toks
        head = self.tok("FOL:")
        self.llm.eval(head)
        body_text, body, _ = self.generate(lambda t: t.endswith("\n"), 80, grammar=self.grammar)
        return text + "FOL:" + body_text, toks + head + body

    def new_step(self, chunk):
        m, f = STEP_RE.search(chunk["text"]), FOL_RE.search(chunk["text"])
        uses = (m.group(2) or "") if m else ""
        parents = []
        for k in re.findall(r"S(?:tep)?\s*(\d+)", uses):
            cands = [s for s in self.steps if s["num"] == int(k) and s["status"] in LIVE]
            if cands:
                parents.append(cands[-1]["id"])
        step = dict(chunk, id=len(self.steps), num=int(m.group(1)) if m else None, uses=uses, parents=parents,
                    claim=m.group(3).strip() if m else chunk["text"].strip()[:200],
                    fol=f.group(1).strip() if f else None, status="pending", verdict=None)
        self.steps.append(step)
        return step

    def cached(self, step):
        return CACHE and bool(step["fol"]) and re.sub(r"\s+", "", step["fol"]) in self.vcache

    def check(self, step):
        """Z3 verdict; a formula already checked in this problem reuses its verdict (cache_hits)."""
        k = re.sub(r"\s+", "", step["fol"] or "")
        if CACHE and k in self.vcache:
            self.s["cache_hits"] += 1
            v = self.vcache[k]
        else:
            v = self.prob.check(step["fol"], facts_only=not CHECK_ALL) if step["fol"] else "parse_error:no FOL line"
            if k:
                self.vcache[k] = v
        key = v.split(":")[0]
        self.s["verdicts"][key] = self.s["verdicts"].get(key, 0) + 1
        return v

    # --- C: LogicTrack-style synchronous checking ---------------------------------
    def sync_check(self, step):
        step["verdict"] = self.check(step)
        if step["verdict"] == "entailed" or (MASK_ON == "refuted" and step["verdict"] != "refuted"):
            step["status"] = "accepted" if step["verdict"] == "entailed" else "kept"
            self.attempts, self.hot = [], False
            return
        self.s["rejections"] += 1
        step["status"] = "rejected"
        self.attempts.append(step)
        self.truncate_to(step["start"])
        self.hot = True
        if len(self.attempts) < SYNC_ATTEMPTS:
            self.note(step)
        else:  # force the best candidate forward
            src = max(self.attempts, key=lambda s: RANK.get(s["verdict"].split(":")[0], 0))
            best = self.new_step(dict(start=0, end=0, text=src["text"], toks=src["toks"]))
            self.refeed(best)
            best["status"], best["verdict"] = "forced", src["verdict"]
            self.s["forced_steps"] += 1
            self.attempts, self.hot = [], False

    # --- lagged conditions ------------------------------------------------------
    def verify(self, step):
        step["verdict"] = self.check(step)
        if step in self.pending:
            self.pending.remove(step)
        if step["verdict"] == "entailed":
            step["status"] = "accepted"
            self.last_accepted_end = step["end"]
            self.consecutive, self.hot = 0, False
            return True
        if MASK_ON == "refuted" and step["verdict"] != "refuted":
            step["status"] = "kept"  # unverifiable is not false: a safe prune needs a refutation
            return True
        self.reject(step)
        return False

    def flush(self, answer_chunk):
        """Check everything still pending before accepting the answer; a rejection voids the answer.
        DEPWAIT=1: wait only for the pending steps the answer rests on (the last live step and its declared ancestors);
        a refuted step the answer never used cannot change it, so the rest are left unchecked (unwaited)."""
        if DEPWAIT and self.pending:
            live = [s for s in self.steps if s["status"] in LIVE]
            need, frontier = set(), {live[-1]["id"]} if live else set()
            while frontier:
                i = frontier.pop()
                need.add(i)
                frontier |= set(self.steps[i]["parents"]) - need
            for s in [s for s in self.pending if s["id"] not in need]:
                self.pending.remove(s)
                s["unwaited"] = True
                self.s["unwaited"] += 1
        for step in list(self.pending):
            if step["status"] != "pending":
                continue
            if LATENCY is not None:  # block until this verdict arrives
                d = step["due"] - self.now()
                if d > 0:
                    if REALTIME:
                        time.sleep(d)
                    self.s["wait_s"] += d
            if not self.verify(step):
                if answer_chunk["start"] < self.llm.n_tokens:  # not already cropped by truncation/backup
                    if self.cond == "lag_mask":
                        self.mask(answer_chunk["start"], answer_chunk["end"])
                    else:
                        self.crop(answer_chunk["start"])
                    self.s["wasted_tokens"] += answer_chunk["end"] - answer_chunk["start"]
                return False
        return True

    def reject(self, step):
        self.s["rejections"] += 1
        self.consecutive += 1
        self.hot = True
        if self.cond == "lag_trunc":
            step["status"] = "rejected"
            self.truncate_to(step["start"])
        else:
            victims = [step] + self.descendants(step)
            kept = [s for s in self.steps if s["start"] > step["start"] and s["status"] in VISIBLE and s not in victims]
            if HYBRID and sum(k["end"] - k["start"] for k in kept if k["status"] != "note") < HYBRID:
                # HYBRID: too little would be kept to be worth an inexact mask or a recompute; truncation is exact
                self.s["hybrid_truncs"] += 1
                step["status"] = "rejected"
                self.truncate_to(step["start"])
            else:
                for v in victims:
                    v["status"], v["gone"] = "masked", True
                    self.s["wasted_tokens"] += v["end"] - v["start"]
                    if v in self.pending:
                        self.pending.remove(v)
                step["masked_with"] = [v["id"] for v in victims]
                step["kept_after"] = [k["id"] for k in kept]
                self.s["masks"] += 1
                self.s["salvaged_tokens"] += sum(k["end"] - k["start"] for k in kept if k["status"] != "note")
                self.retry = RETRY
                if self.cond == "lag_mask":
                    for v in sorted(victims, key=lambda s: -s["start"]):
                        self.mask(v["start"], v["end"])
                else:  # lag_refresh: recompute the kept steps without the rejected branch
                    self.crop(step["start"])
                    for k in sorted(kept, key=lambda s: s["start"]):
                        self.refeed(k)
                        if k["status"] == "accepted":
                            self.last_accepted_end = k["end"]
        if self.consecutive >= MAX_CONSEC:
            self.s["backups"] += 1
            self.consecutive = 0
            self.truncate_to(self.last_accepted_end or self.prompt_end)
        self.note(step)

    def truncate_to(self, p):
        for s in self.steps:
            if s["start"] >= p and not s.get("gone"):
                s["gone"] = True
                self.s["wasted_tokens"] += s["end"] - s["start"]
                if s["status"] in VISIBLE:
                    s["status"] = "truncated"
        self.pending = [s for s in self.pending if s["start"] < p]
        if self.last_accepted_end and self.last_accepted_end > p:
            done = [s["end"] for s in self.steps if s["status"] == "accepted"]
            self.last_accepted_end = max(done) if done else None
        self.crop(p)
        self.s["truncations"] += 1

    def descendants(self, step):
        """Later live steps that (transitively) declared the step in [uses]. INFER=1 also asks the solver: a step
        the premises do not prove, but that would follow if the refuted formulas were believed, rests on them whether
        declared or not (Problem.supports). It reads the step's own FOL line, which a slow real formalizer would delay."""
        out, frontier, bad = [], {step["id"]}, [step["fol"]] if step["fol"] else []
        for s in sorted(self.steps, key=lambda s: s["start"]):
            if s["start"] <= step["start"] or s["status"] not in LIVE:
                continue
            hit = bool(frontier & set(s["parents"]))
            if not hit and INFER and bad and s["fol"] and s["verdict"] != "entailed" and self.prob.supports(s["fol"], bad):
                hit = True
                self.s["inferred"] += 1
            if hit:
                out.append(s)
                frontier.add(s["id"])
                if s["fol"]:
                    bad.append(s["fol"])
        return out

    def answer_dist(self):
        """p(A/B/C | ... 'Answer:') at the current end of the cache."""
        import numpy as np
        letters = [self.tok(f" {c}")[0] for c in "ABC"]
        self.llm.eval(self.tok("Answer:"))
        lg = np.ctypeslib.as_array(self.llm._ctx.get_logits(), shape=(self.llm.n_vocab(),))[letters].astype(float)
        p = np.exp(lg - lg.max())
        return p / p.sum()

    def force_answer(self):
        """Budget exhausted: answer = most likely of A/B/C after 'Answer:'."""
        self.s["forced_answer"] += 1
        self.ctx_final()
        if self.cond.startswith("lag") and PROBE:
            self.probe = self.consistency_probe(self.llm.n_tokens)
            return "ABC"[max(range(3), key=lambda i: self.probe["p_live"][i])]
        return "ABC"[int(self.answer_dist().argmax())]

    def consistency_probe(self, pos):
        """p(A/B/C | 'Answer:') from the live cache vs from a cold re-prefill of the visible transcript."""
        t0 = time.time()
        dist = self.answer_dist
        self.crop(pos)
        p_live = dist()
        visible = [s for s in sorted(self.steps, key=lambda s: s["start"]) if s["status"] in VISIBLE]
        self.llm.reset()
        self.llm._ctx.kv_cache_clear()
        self.llm.eval(self.prompt_toks + [t for s in visible for t in s["toks"]])
        p_cold = dist()
        return dict(p_live=p_live.round(4).tolist(), p_cold=p_cold.round(4).tolist(), probe_s=round(time.time() - t0, 2),
                    tv=round(0.5 * float(abs(p_live - p_cold).sum()), 4), flip=int(p_live.argmax() != p_cold.argmax()),
                    stale=self.cond == "lag_mask" and any(
                        self.steps[k]["status"] != "note" for s in self.steps for k in s.get("kept_after", [])))


def sample_ids(n, seed=0):
    return random.Random(seed).sample([i for i in range(500) if i not in BAD_GOLD], n)


def wrong_prunes(item, steps):
    """Rejected steps whose English claim matches a context sentence or gold conclusion (i.e. was true)."""
    gold = gold_claims(item)
    out = []
    for s in steps:
        if s.get("verdict") and s["verdict"] != "entailed" and s["status"] in ("masked", "rejected", "truncated"):
            c = norm(s["claim"])
            if c and max(SequenceMatcher(None, c, g).ratio() for g in gold) >= 0.92:
                out.append(s["id"])
    return out


def main_run(cond, n):
    from llama_cpp import Llama
    llm = Llama(MODEL, n_ctx=12288, n_gpu_layers=-1, n_batch=512, flash_attn=True, verbose=False, seed=0)
    data = json.load(open(DATA))
    os.makedirs(OUT, exist_ok=True)
    path = f"{OUT}/{cond}.jsonl"
    done = {json.loads(line)["id"] for line in open(path)} if os.path.exists(path) else set()
    for i in sample_ids(n):
        if i in done:
            continue
        item = data[i]
        llm.set_seed(i)
        r = Run(llm, item, cond)
        pred = r.run()
        for s in r.steps:
            if s["status"] == "pending":
                s["status"] = "unverified_at_end"
        wp = wrong_prunes(item, r.steps)
        rec = dict(id=i, cond=cond, latency=LATENCY, realtime=REALTIME, grammar=GRAMMAR, mask_on=MASK_ON, note=NOTE, guard=GUARD, check_all=CHECK_ALL, cache=CACHE, infer=INFER, retry=RETRY, depwait=DEPWAIT, hybrid=HYBRID, loop=LOOP, max_steps=MAX_STEPS, gold=item["answer"], pred=pred, correct=pred == item["answer"], **r.s,
                   wrong_prunes=len(wp), wrong_prune_ids=wp, probe=r.probe,
                   steps=[{k: v for k, v in s.items() if k not in ("gone", "toks")} for s in r.steps], text=r.text)
        with open(path, "a") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        print(f"[{cond}] id={i} gold={item['answer']} pred={pred} gen={r.s['gen_tokens']} rej={r.s['rejections']} "
              f"wall={r.s['wall_s']}s" + (f" tv={r.probe['tv']}" if r.probe else ""), flush=True)


def summary():
    hdr = ("cond", "n", "acc%", "gen tok/q", "wasted/q", "salvaged/q", "recomputed/q", "rej/q", "wrong prunes",
           "forced ans", "wall s/q", "tok/s", "probe TV (stale only)", "flips", "z3 verdicts, all steps")
    print("| " + " | ".join(hdr) + " |\n|" + "---|" * len(hdr))
    for c in CONDS:
        p = f"{OUT}/{c}.jsonl"
        if not os.path.exists(p):
            continue
        R = [json.loads(line) for line in open(p)]
        n = len(R)
        tot = lambda k: sum(r.get(k) or 0 for r in R)
        v = {}
        for r in R:
            for k, x in r["verdicts"].items():
                v[k] = v.get(k, 0) + x
        pr = [r["probe"] for r in R if r.get("probe")]
        stale = [q for q in pr if q["stale"]]
        tv = f"{sum(q['tv'] for q in stale) / len(stale):.3f} (n={len(stale)})" if stale else "-"
        row = (c, n, f"{100 * tot('correct') / n:.1f}", f"{tot('gen_tokens') / n:.0f}", f"{tot('wasted_tokens') / n:.0f}",
               f"{tot('salvaged_tokens') / n:.0f}", f"{tot('recomputed_tokens') / n:.0f}", f"{tot('rejections') / n:.2f}",
               tot("wrong_prunes"), tot("forced_answer"), f"{tot('wall_s') / n:.1f}",
               f"{tot('gen_tokens') / max(tot('wall_s'), 1e-9):.1f}", tv, sum(q["flip"] for q in pr) if pr else "-",
               " ".join(f"{k}={x}" for k, x in sorted(v.items())))
        print("| " + " | ".join(map(str, row)) + " |")


def spike():
    """KV removal works mid-cache; does a masked fact leak through later tokens?"""
    from llama_cpp import Llama
    llm = Llama(MODEL, n_ctx=2048, n_gpu_layers=-1, flash_attn=True, verbose=False, seed=0)
    bos, _, u_open, u_close, eot = TPL
    ask = "\nWhat is the secret code? If no code was given, reply exactly NONE." + u_close
    filler = "The sky is blue. Grass is green. Water is wet. Remember everything above. " * 3
    head, span = bos + u_open + "Here are some notes.\n", "The secret code is 7391.\n"

    def tok(t):
        return llm.tokenize(t.encode(), add_bos=False, special=True)

    def answer():
        out = []
        for _ in range(24):  # chatty models preface the code with ~10 tokens
            t = llm.sample(temp=0.0)
            if t == llm.token_eos() or llm.detokenize([t]) == eot.encode():
                break
            out.append(t)
            llm.eval([t])
        return llm.detokenize(out).decode(errors="ignore").strip()

    res = {}
    for mode in ("no_mask", "mask_only", "clean_recompute"):
        llm.reset()
        llm._ctx.kv_cache_clear()
        llm.eval(tok(head))
        a = llm.n_tokens
        if mode != "clean_recompute":  # clean = the span never existed
            llm.eval(tok(span))
        b = llm.n_tokens
        llm.eval(tok(filler))
        if mode == "mask_only":
            llm._ctx.kv_cache_seq_rm(-1, a, b)
        llm.eval(tok(ask))
        res[mode] = answer()
    print(json.dumps(res, indent=1))
    assert "7391" in res["no_mask"], "model should recall the code when nothing is masked"
    assert "7391" not in res["clean_recompute"], "clean recompute must not know the code"
    print("spike ok; mask_only leaked" if "7391" in res["mask_only"] else "spike ok; mask_only did not leak here")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--cond", choices=CONDS)
    ap.add_argument("--n", type=int, default=30)
    ap.add_argument("--summary", action="store_true")
    ap.add_argument("--spike", action="store_true")
    a = ap.parse_args()
    if a.summary:
        summary()
    elif a.spike:
        spike()
    elif a.cond:
        main_run(a.cond, a.n)
    else:
        ap.print_help()
        sys.exit(1)
