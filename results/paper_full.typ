// Research report, rounds 1–5. Build: typst compile results/paper.typ
#set page(paper: "us-letter", margin: (x: 2.2cm, y: 2cm), numbering: "1")
#set text(size: 10pt)
#set par(justify: true)
#set heading(numbering: "1.1")
#show heading.where(level: 1): set block(above: 1.5em, below: 0.8em)
#show heading.where(level: 2): set block(above: 1.2em, below: 0.6em)
#show figure.caption: set text(size: 9pt)
#show table.cell.where(y: 0): set text(weight: "bold")
#set table(stroke: (_, y) => if y == 0 { (bottom: 0.6pt) } else { none }, inset: (x: 5pt, y: 3.2pt))
#set footnote.entry(gap: 0.5em)

#let c(..ns) = "[" + ns.pos().map(str).join(", ") + "]"

#let C-sync = luma(120)
#let C-trunc = rgb("#2f6db5")
#let C-mask = rgb("#d9622b")
#let C-bad = rgb("#e8a5a5")
#let C-dep = rgb("#f6d4d4")
#let C-keep = rgb("#dbe8f6")
#let C-re = rgb("#fbe9b7")
#let C-wait = rgb("#fbe9b7")
#let C-skip = luma(235)

// ---------- drawing helpers ----------
#let swatch(c) = box(width: 0.8em, height: 0.8em, fill: c, baseline: 0.1em)

#let linechart(title, sync, trunc, mask, ymax: 200, step: 50, w: 4.3cm, h: 3.2cm) = {
  let xs = (1, 3, 8)
  let px(x) = x / 9 * w
  let py(y) = h - y / ymax * h
  block(inset: (left: 1.9em, bottom: 1.6em, top: 1.4em), box(width: w, height: h, {
    for t in range(0, ymax + 1, step: step) {
      place(line(start: (0pt, py(t)), end: (w, py(t)), stroke: 0.3pt + luma(215)))
      place(dx: -1.9em, dy: py(t) - 0.45em, box(width: 1.6em, align(right, text(7pt)[#t])))
    }
    for x in xs {
      place(dx: px(x) - 1em, dy: h + 0.3em, box(width: 2em, align(center, text(7pt)[#x s])))
    }
    place(line(start: (0pt, h), end: (w, h), stroke: 0.6pt))
    place(line(start: (0pt, 0pt), end: (0pt, h), stroke: 0.6pt))
    for (ys, col) in ((sync, C-sync), (trunc, C-trunc), (mask, C-mask)) {
      let pts = xs.zip(ys).map(((x, y)) => (px(x), py(y)))
      place(curve(stroke: 1.2pt + col, curve.move(pts.first()), ..pts.slice(1).map(p => curve.line(p))))
      for p in pts { place(dx: p.at(0) - 2pt, dy: p.at(1) - 2pt, circle(radius: 2pt, fill: col, stroke: none)) }
    }
    place(dy: -1.3em, text(8pt, weight: "bold", title))
  }))
}

#let barchart(groups, labels, colors, ymax: 80, step: 20, w: 15cm, h: 3.8cm) = {
  let gw = w / groups.len()
  let bw = gw * 0.82 / labels.len()
  let py(y) = h - y / ymax * h
  block(inset: (left: 2.2em, bottom: 1.6em, top: 0.6em), box(width: w, height: h, {
    for t in range(0, ymax + 1, step: step) {
      place(line(start: (0pt, py(t)), end: (w, py(t)), stroke: 0.3pt + luma(215)))
      place(dx: -2.2em, dy: py(t) - 0.45em, box(width: 1.9em, align(right, text(7pt)[#t])))
    }
    for (gi, (name, vals)) in groups.enumerate() {
      let x0 = gi * gw + gw * 0.09
      for (i, v) in vals.enumerate() {
        place(dx: x0 + i * bw, dy: py(v), rect(width: bw * 0.88, height: v / ymax * h, fill: colors.at(i), stroke: none))
        place(dx: x0 + i * bw - 0.6em, dy: py(v) - 1.05em, box(width: bw * 0.88 + 1.2em, align(center, text(6.5pt)[#v])))
      }
      place(dx: gi * gw, dy: h + 0.35em, box(width: gw, align(center, text(8pt, name))))
    }
    place(line(start: (0pt, h), end: (w, h), stroke: 0.6pt))
    place(line(start: (0pt, 0pt), end: (0pt, h), stroke: 0.6pt))
  }))
  align(center, text(8pt, labels.zip(colors).map(((l, c)) => [#swatch(c) #l]).join(box(width: 1.2em))))
}

// timeline segment: lane row, start, length, label, fill
#let U = 0.95cm
#let seg(row, x, len, label, fill, stroke: none) = place(dx: x * U, dy: row * 0.75cm,
  rect(width: len * U - 1pt, height: 0.55cm, fill: fill, stroke: stroke, inset: 0pt,
    align(center + horizon, text(7pt, label))))
#let lane(row, label) = place(dx: -2.9cm, dy: row * 0.75cm + 0.12cm, box(width: 2.7cm, align(right, text(8pt, label))))

// KV-cache cell
#let cell(l, fill: C-keep, dash: none, fg: black) = box(width: 1.15cm, height: 0.62cm,
  fill: fill, stroke: (paint: luma(90), thickness: 0.5pt, dash: dash),
  align(center + horizon, text(8pt, fill: fg, l)))
#let gone(l) = cell(l, fill: none, dash: "dashed", fg: luma(150))
#let dashed-swatch = box(width: 0.8em, height: 0.8em, stroke: (dash: "dashed", paint: luma(90), thickness: 0.5pt), baseline: 0.1em)

// ---------- front matter ----------
#align(center)[
  #set par(justify: false)
  #text(16pt, weight: "bold")[Checking Reasoning Steps Off the Critical Path:\ Asynchronous Solver Verification and KV-Cache Invalidation for Small Language Models]
  #v(0.6em)
  #text(11pt)[Aditya Bankoti]\
  #text(9.5pt)[University of Washington]\
  #text(9.5pt)[Technical report, October 2026]
]
#v(0.8em)

#block(inset: (x: 1.2cm), [
  #set text(size: 9.5pt)
  *Abstract.* Small language models make errors in individual reasoning steps, and an external checker can catch many of them, but checking each step before the next one is written stalls generation. We study a pipeline in which a model writes each reasoning step as a first-order-logic formula with declared dependencies, an SMT solver (Z3) checks the step against the problem's premises, and refuted steps are removed. We ask whether the check improves accuracy, how to keep checking off the critical path, and whether a refuted step and its dependents can be removed from the KV cache in place rather than by truncating everything written after it. On ProverQA-Hard with Qwen3 models of 8B, 14B and 30B-A3B parameters ($n$ = 100 problems for the larger two) the checker does not improve accuracy at any scale; the step format alone adds 8 to 14 points over chain-of-thought. Asynchronous checking, where the model keeps generating while the solver works, is 12 to 67% faster than blocking on every model at no accuracy cost, with the gap growing with checker latency. In-place masking of a refuted step and its declared dependents costs no accuracy at 14B and 30B and is 4 to 10% faster than truncation at high latency, but collapses at 8B (36.7% vs. 63.3%); we trace the collapse to stale cache entries and to the model giving up, not to undeclared dependencies. Finally, a loop detector that crops repeated steps removes 19% of generated tokens and 16% of time with no accuracy change, whereas dependency-scoped waiting and a mask/truncate hybrid add nothing. All runs, logs and the harness are in the project repository.
])
#v(0.6em)

= Introduction

Language models in the 8B to 30B range solve multi-step logical reasoning problems unreliably: individual steps are wrong, and later steps build on them. When each step is written as a logical formula, an automated reasoner can decide whether the step follows from the premises, so step-level errors are detectable in principle. Prior work checks steps after the fact to rerank or diagnose a finished chain #c(2, 4), or online, regenerating from the last verified step when a check fails #c(3).

Two costs make the online version expensive. First, a blocking check adds the checker's latency to every step. Z3 answers in milliseconds on the formulas studied here, but a realistic checker, an autoformalizer sharing the GPU or a proof assistant, takes seconds. Second, the standard remedy for a refuted step is to truncate the context back to that step and regenerate, discarding every later step including those that never depended on it. An attractive alternative is to remove only the refuted step and its dependents from the KV cache and keep the rest, but whether in-place removal from the cache actually removes the step's influence is contested #c(13, 14, 15).

This report evaluates that pipeline end to end. Each step carries an explicit dependency list, so the steps of a problem form a DAG; checking runs asynchronously while generation continues; on a refutation the step and its DAG descendants are removed from the live KV cache by one of three policies, truncation, masking, or masking followed by recomputation of the kept steps. Checker latency is simulated on a token clock so that policies can be compared at latencies of 1, 3 and 8 seconds per check. We then diagnose the one regime where masking fails and test three cheap efficiency fixes.

The findings, over five rounds of experiments:

+ *Step checking does not improve accuracy at 8B, 14B or 30B.* The structured step format is what helps, by 8 to 14 points over chain-of-thought (@sec-acc).
+ *Asynchronous checking is 12 to 67% faster than blocking* on every model, at no accuracy cost, with the gap growing with latency (@sec-async).
+ *DAG-scoped masking is a modest, scale-dependent win over truncation.* At 14B and 30B it costs no accuracy and saves 4 to 10% of time at high latency, significantly fewer tokens at 30B at every latency. At 8B it loses 27 points at 8 s latency (@sec-mask).
+ *The 8B failure is not caused by undeclared dependencies.* A solver-based test finds hidden logical dependents in 2 to 9% of problems, and masking them changes no answer. The loss comes from stale cache entries, which recomputation recovers, and from the model abandoning the proof after a mask (@sec-why).
+ *Of three efficiency fixes, only loop cropping pays:* −19% tokens and −16% modeled time at 14B with identical answers. Dependency-scoped waiting saves about one second per problem, and a mask/truncate hybrid degenerates into truncation (@sec-eff).

= Background and related work <sec-related>

*Solver-checked reasoning steps.* VeriCoT #c(2) translates each step of a finished chain into SMT-LIB and checks it with Z3 against a growing premise set; Safe #c(4) does the same with Lean 4 to rerank samples. LogicTrack #c(3) is the closest correctness loop to ours: it checks each step with Z3 during generation and, on failure, re-prompts from the verified prefix with feedback, reporting a gain from 0.43 to 0.58 for Llama-3.1-8B on its benchmark. LogicGuide #c(5) instead constrains decoding so that steps are sound by construction. None of these study checker latency, dependency-scoped invalidation, or the KV cache. Whole-problem formalization, where the model translates the entire problem and a solver answers it #c(20), is the natural upper bound on what a checker can do, and its failure mode, unfaithful translation, is also ours (@sec-disc).

*Step dependency graphs.* PARC #c(6) builds a premise DAG over reasoning steps and defines accumulation errors, steps that are locally valid but rest on a bad premise; Graph of Verification #c(7) checks claims in topological order of such a DAG. We use the DAG for a different purpose, to decide which later steps a refutation invalidates, and we take it from the model's own `[uses]` declarations. PARC reports that 7B models declare only about 64% of the premises they use, which motivated our solver-based test for undeclared dependencies (@sec-why).

*Removing reasoning steps from the KV cache.* Several systems evict reasoning tokens during decoding to save memory: Think Clearly #c(9) evicts low-attention chunks, PENCIL #c(10) erases finished thoughts under a learned rule, StepKV #c(11) evicts whole steps by utility under a budget, and ArborKV #c(12) manages the cache for tree-of-thoughts search with lazy rehydration on backtracking. Thinking in Place #c(8) is closest in mechanism: the model marks steps dead and the runtime evicts their KV pages, trained on step-dependence DAGs. All of these are triggered by a budget or a learned signal; ours is triggered by a solver verdict, and the invalidated set is the transitive closure of declared dependencies.

*Does masking remove influence?* Recent work argues that masking a span is not the same as never having seen it. Positions Are Not Facts #c(13) finds that answers still match a masked record 74 to 82% of the time, against 34 to 60% after delete-and-recompute; Aborted but Not Forgotten #c(14) shows a rolled-back branch leaking through retained KV entries; KVEraser #c(15) notes that exact erasure requires recomputing every later token. CacheBlend #c(16) recomputes only high-deviation tokens. Our truncate / mask / refresh policies span this space, and our results at 8B reproduce the leakage concern while our results at 14B and 30B show it can be negligible for the kept, independent steps.

*Truth maintenance and provenance.* The idea that a retracted belief should retract everything derived from it is classical: dependency-directed backtracking #c(18), justification-based truth maintenance #c(17), assumption-based TMS #c(19), and incremental view maintenance by deletion and rederivation #c(21). PACMI #c(22) applies provenance-cascading invalidation to an LLM agent's external memory. Our contribution is to apply the same discipline to the live KV cache, where invalidation has a cost model (regenerate, mask or recompute) that these systems do not need.

*Benchmark.* ProverQA #c(1) generates first-order-logic problems with a symbolic prover; each item ships with gold formulas for its premises and conclusion, which is what makes per-step checking against gold premises possible. Its hard split has 6 to 9 reasoning steps, distractor premises, and three labels (True / False / Uncertain).

= Method <sec-method>

== Step format and checker

The prompt lists the problem's premises, each with its gold first-order-logic formula, and asks the model to reason in numbered steps of the form

#align(center, box(inset: 0.4em, fill: luma(245), radius: 2pt, align(left, text(9pt, font: "DejaVu Sans Mono")[Step k \[uses P2, S1\]: ⟨claim in English⟩\ FOL: ⟨formula⟩])))

followed by a final `Answer: A/B/C` line. `P2` names a premise and `S1` an earlier step, so the `[uses]` lists define a DAG over the steps of a problem. Formulas use predicates and constants from the problem, the connectives ¬ ∧ ∨ → ↔ ⊕, and the quantifiers ∀ ∃.

The checker parses the formula $phi$ and asks Z3 two questions against the premise set $Gamma$: whether $Gamma tack.r phi$ (*entailed*) and whether $Gamma tack.r not phi$ (*refuted*); otherwise the verdict is *unknown*. Only refuted steps are rejected. Rejecting every non-entailed step, the policy of our first experiments, cost 28% more tokens, forced 13 of 30 answers, and changed no accuracy, so refute-only is the policy throughout. A rejected step is replaced in the transcript by a one-line note (`Step k was refuted: it contradicts the premises`), and a format guard prevents the model from copying such notes as if they were steps. Each problem is capped at 20 steps, 2,500 generated tokens and 8 rejections; after that the answer is forced to the most likely of A, B, C.

== Asynchronous checking and the latency model <sec-latency>

In the *sync* condition the model waits for each verdict before writing the next step. In the *async* conditions it keeps generating; a verdict is applied when it arrives, usually one or two steps later (@fig-timeline), and the final answer waits for any outstanding verdicts.

Checker latency $L in {1, 3, 8}$ s is simulated on a *token clock*: a verdict becomes available after $L \/ 0.0724$ generated tokens, so $L = 1$ s is about 14 tokens. The clock rate, 72.4 ms per generated token, and a fixed cost of 8.6 s per problem (prefill and Z3) were measured on the 8B model and are held fixed for all models, so *modeled time*

$ T = 8.6 "s" + 0.0724 "s" times "generated tokens" + "checker waits" $

is a function of the transcript alone and comparable across machines and models. Raw wall time on the GPU is reported separately where it matters.

#figure(
  box(inset: (left: 2.9cm, top: 0.2cm), width: 100%, height: 3.3cm, {
    lane(0, [*sync*])
    seg(0, 0, 1.2, [S1], C-keep); seg(0, 1.2, 0.8, [wait], luma(225))
    seg(0, 2.0, 1.2, [S2], C-keep); seg(0, 3.2, 0.8, [wait], luma(225))
    seg(0, 4.0, 1.2, [S3], C-bad); seg(0, 5.2, 0.8, [wait ✗], luma(225))
    seg(0, 6.0, 1.2, [S3′], C-keep); seg(0, 7.2, 0.8, [wait], luma(225))
    seg(0, 8.0, 1.0, [answer], luma(200))
    lane(1.5, [*async*: model])
    lane(2.5, [checker])
    seg(1.5, 0, 1.2, [S1], C-keep); seg(1.5, 1.2, 1.2, [S2], C-keep); seg(1.5, 2.4, 1.2, [S3], C-bad)
    seg(1.5, 3.6, 1.2, [S4], C-keep); seg(1.5, 4.8, 1.2, [S3′ / S5], C-keep); seg(1.5, 6.0, 1.0, [answer], luma(200))
    seg(2.5, 1.2, 0.8, [check S1], luma(235)); seg(2.5, 2.4, 0.8, [check S2], luma(235))
    seg(2.5, 3.6, 0.8, [check S3 ✗], C-dep)
    place(dx: 4.4 * U, dy: 1.05cm, line(length: 1.7cm, angle: 90deg, stroke: (paint: red, thickness: 0.9pt, dash: "dashed")))
    place(dx: 4.4 * U + 3pt, dy: 2.55cm, text(7pt, fill: red)[refuted: truncate or mask])
  }),
  caption: [Blocking versus asynchronous checking. With sync, every step waits $L$ for its verdict. Async keeps generating while the solver works and acts on a refutation when it arrives (here, during S4).],
) <fig-timeline>

== Invalidation policies

When a verdict of *refuted* arrives for step $S_k$, the *invalidated set* is $S_k$ together with every later step whose `[uses]` chain reaches $S_k$. Three policies remove it (@fig-cache):

- *truncate* (`lag_trunc`): cut the KV cache back to the start of $S_k$ and regenerate everything after it. Exact by construction; discards independent later steps too.
- *mask* (`lag_mask`): remove exactly the invalidated steps' token ranges from the cache and continue generating after the last kept step. Independent later steps are kept as they are.
- *refresh* (`lag_refresh`): mask, then recompute the kept later steps so that their cache entries never attended to the refuted step. Exact, at the cost of a prefill over the kept tokens.

Masking is implemented with llama.cpp's `kv_cache_seq_rm` on the step's position range. For every later query this is equivalent to setting the attention logits of those positions to $-infinity$. Positions are not shifted, so the kept steps keep their rotary positions and the cache has gaps; removing a middle range is safe in llama.cpp, whereas a gap at the tail breaks decoding, which is why trailing removals are implemented as truncation. After three consecutive rejections the harness backs up to the last accepted step.

#figure(
  {
    set align(left)
    let row(label, cells, note) = (align(right + horizon, text(8pt, label)), ..cells, align(horizon, text(8pt, note)))
    grid(columns: (2.6cm,) + (1.15cm,) * 7 + (auto,), column-gutter: 2pt, row-gutter: 5pt,
      ..row([S3 refuted],(cell[P], cell[S1], cell[S2], cell([S3 ✗], fill: C-bad), cell[S4], cell([S5→S3], fill: C-dep), cell[S6]), []),
      ..row([*truncate*], (cell[P], cell[S1], cell[S2], gone[S3], gone[S4], gone[S5], gone[S6]), [regenerate from S3]),
      ..row([*mask*], (cell[P], cell[S1], cell[S2], gone[S3], cell[S4], gone[S5], cell[S6]), [continue at S7]),
      ..row([*refresh*], (cell[P], cell[S1], cell[S2], gone[S3], cell([S4], fill: C-re), gone[S5], cell([S6], fill: C-re)), [recompute S4, S6, continue]),
    )
    v(0.3em)
    align(center, text(8pt)[#swatch(C-keep) kept #h(1em) #swatch(C-bad) refuted #h(1em) #swatch(C-dep) uses a refuted step #h(1em) #dashed-swatch removed from cache #h(1em) #swatch(C-re) recomputed])
  },
  caption: [What each policy does to the KV cache when step S3 is refuted. S5 declared `[uses S3]`, so it is invalidated too, while the independent steps S4 and S6 stay under mask and refresh. Truncation discards all of them.],
) <fig-cache>

== Efficiency fixes <sec-method-eff>

Three fixes, evaluated in @sec-eff, target the remaining waste in the asynchronous pipeline (@fig-fixes):

- *Dependency-scoped waiting* (`DEPWAIT`). At answer time the pipeline waits only for the verdicts of the last live step and its transitive `[uses]` ancestors. Pending verdicts on steps the answer does not depend on are not waited for.
- *Loop cropping* (`LOOP=2`). If a new step's formula is identical to that of an earlier live step, the new step is cropped from the cache and replaced by a note (`it repeats an earlier step`). After three crops the answer is forced. This targets a failure mode seen in every condition, including the unchecked ones: the model repeating one formula until it hits the step cap (@sec-loops).
- *Mask/truncate hybrid* (`HYBRID=50`). Under refresh, if fewer than 50 tokens of kept steps would survive a mask, truncate instead; recomputation is not worth a prefill for a short suffix.

#figure(
  {
    set align(left)
    let row(label, cells, note) = (align(right + horizon, text(8pt, label)), ..cells, align(horizon, text(8pt, note)))
    grid(columns: (2.6cm,) + (1.15cm,) * 7 + (auto,), column-gutter: 2pt, row-gutter: 5pt,
      ..row([(a) at the answer], (cell[P], cell[S1 ✓], cell[S2 ✓], cell([S3 ?], fill: C-wait), cell([S4 ?], fill: C-skip), cell([S5→S3 ?], fill: C-wait), cell([answer], fill: luma(215))), [wait for S3, S5; not S4]),
      ..row([(b) S5 repeats S3], (cell[P], cell[S1], cell[S2], cell[S3: φ], cell[S4], gone[S5: φ], cell([note], fill: luma(235))), [crop S5; 3 crops → force answer]),
    )
    v(0.3em)
    align(center, text(8pt)[#swatch(C-wait) verdict pending, on the answer's dependency chain (waited) #h(1em) #swatch(C-skip) pending, independent (not waited) #h(1em) #dashed-swatch cropped])
  },
  caption: [The efficiency fixes. (a) Dependency-scoped waiting: the answer depends on S5, which uses S3, so only those two verdicts are awaited. (b) Loop cropping: a step whose formula repeats an earlier step's is removed and noted.],
) <fig-fixes>

== Diagnostics for the 8B failure <sec-diag>

Two further variants were used only to diagnose why masking loses accuracy at 8B (@sec-why). *Solver-inferred dependents* (`INFER`) extends the invalidated set with any kept step that the premises alone do not prove but that would follow if the refuted formula were believed. The test starts from the problem's rules plus the refuted formula, adds each ground fact that remains consistent, and checks entailment; starting from the full premise set would prove everything from a refuted formula by _ex falso_. *Forced retry* (`RETRY`) forces the token after a mask to begin a new step, to stop the model from jumping straight to an answer.

= Experimental setup <sec-setup>

*Benchmark.* ProverQA-Hard #c(1), the 500-item hard development split: 6 to 9 reasoning steps per problem, distractor premises, labels True / False / Uncertain (A / B / C). Z3 on the gold formulas reproduces the gold label on 498 of 500 items; the two exceptions (ids 411 and 473) are excluded. Always answering Uncertain scores about 40%. Samples are drawn with seed 0: 30 problems for the 8B experiments and 100 for the 14B and 30B. The efficiency experiment (@sec-eff) uses a 30-problem sample of which 28 are in the 100-problem sample; paired comparisons use those 28.

*Models.* Qwen3-8B, Qwen3-14B and Qwen3-30B-A3B (a mixture of experts with 3B active parameters), all Q4_K_M quantized GGUF files from Qwen's Hugging Face repositories, run with llama.cpp (llama-cpp-python 0.3.36) in non-thinking mode, greedy decoding, temperature 0.7 after a rejection. The 8B latency sweep ran on an Apple M4 (24 GB, Metal); everything else ran on a Colab L4 (24 GB), about 18 GPU-hours in total. The 30B-A3B was chosen as the main model because it structures proofs best (15.3 steps per problem in the unchecked format against 10.1 for the 14B), has the highest checked accuracy, and is about 2.5 times faster than the dense 14B.

*Conditions.* `base`: ProverQA's own two-shot chain-of-thought prompt. `fmt`: the step format with formulas, unchecked. `sync`: blocking check. `trunc`, `mask`: asynchronous check at $L in {1, 3, 8}$ s. `refresh`: at $L = 8$ s. For the 30B we also ran a *no-cap* ablation (v3): 60-step and 5,000-token caps, the checker verifying every formula with an extra *restated* verdict for formulas that merely repeat a premise, and a verdict cache.

*Metrics and statistics.* Accuracy; generated tokens per problem; wasted tokens (discarded by truncation, masking or cropping); modeled time (@sec-latency); L4 wall time. All comparisons are paired on the same problems and use two-sided exact sign tests (McNemar's test for accuracy). With $n$ = 30 a sign test reaches $p < 0.05$ only at 6 wins to 0 losses, so the 30-problem runs can detect a 15-point accuracy change but not a 5-point one.

= Results <sec-results>

== Accuracy <sec-acc>

#figure(
  table(columns: 5, align: (left, center, center, center, center),
    [Condition], [8B ($n$=30)], [14B ($n$=100)], [30B ($n$=100)], [30B, no cap],
    [base (plain CoT)], [46.7], [58], [57], [57],
    [fmt (steps, unchecked)], [56.7], [66], [67], [71],
    [sync], [53.3], [65], [73], [71],
    [trunc, $L$ = 1 / 3 / 8 s], [63.3 / 63.3 / 63.3], [70 / 70 / 70], [72 / 73 / 73], [71 / 71 / 71],
    [mask, $L$ = 1 / 3 / 8 s], [60.0 / 53.3 / *36.7*], [70 / 71 / 71], [74 / 72 / 71], [76 / 72 / 73],
    [refresh, $L$ = 8 s], [53.3], [73], [71], [72],
  ),
  caption: [Accuracy (% correct). The 8B mask loss at $L$ = 8 s is the only significant checked-versus-checked difference (0 wins / 8 losses against trunc, $p$ = 0.008).],
) <tab-acc>

#figure(
  barchart(
    (([8B ($n$=30)], (46.7, 56.7, 53.3, 63.3, 36.7)), ([14B], (58, 66, 65, 70, 71)), ([30B-A3B], (57, 67, 73, 73, 71))),
    ([base], [fmt], [sync], [trunc, $L$=8 s], [mask, $L$=8 s]),
    (luma(200), rgb("#9dbbe0"), C-sync, C-trunc, C-mask),
  ),
  caption: [The step format helps; the checker on top of it does not. Masking collapses at 8B with a slow checker but holds at 14B and 30B.],
) <fig-acc>

*The checker does not improve accuracy at any scale.* Checked (sync) minus unchecked (fmt) is −3 points at 8B, −1 at 14B (8 wins / 9 losses, $p$ = 1.0), +6 at 30B (8/2, $p$ = 0.11) and 0 in the 30B no-cap run (9/9). The asynchronous conditions are no better: the best checked condition at 8B (trunc, 63.3%) beats fmt by 3 wins to 1 loss ($p$ = 0.62). What the checker catches are mostly translation errors, malformed formulas or English claims forced into the wrong formula, rather than reasoning errors; at 8B, 58% of rejections were format failures before the format guard, and the checker's feedback biased answers toward Uncertain.

*The step format itself helps.* fmt beats plain chain-of-thought by 10 points at 8B, 8 at 14B, 10 at 30B and 14 in the no-cap run (27/13, $p$ = 0.04). The prompt also shows the formula of every premise, which may account for part of this.

*Per class, the checker's only gain is on Uncertain problems.* On problems whose gold label is Uncertain, trunc beats fmt 3/0, 6/2 and 3/0 on the three models (12/2 pooled); on True and False problems it does not. Refuting a step that "proves" an unprovable goal is the one case where the solver corrects the model.

== Asynchronous versus blocking checks <sec-async>

#figure(
  grid(columns: 3, column-gutter: 0.4cm,
    linechart([8B ($n$=30)], (40.3, 58.0, 102.2), (34.6, 39.0, 51.7), (34.4, 34.8, 43.8), ymax: 120, step: 40),
    linechart([14B], (51.8, 74.4, 130.9), (46.4, 50.6, 62.2), (45.6, 49.0, 55.8), ymax: 150),
    linechart([30B-A3B], (74.7, 107.8, 190.4), (61.0, 63.6, 69.5), (58.7, 59.8, 63.3), ymax: 200),
  ) + align(center, text(8pt)[#swatch(C-sync) sync #box(width: 1.2em) #swatch(C-trunc) async + truncate #box(width: 1.2em) #swatch(C-mask) async + mask]),
  caption: [Modeled seconds per problem versus checker latency. Blocking cost grows with every check; asynchronous cost barely moves.],
) <fig-time>

#figure(
  table(columns: 8, align: (left, center) + (right,) * 5 + (center,),
    [Model], [$L$], [sync], [trunc], [mask], [mask vs sync], [mask vs trunc], [mask fewer tokens, W/L ($p$)],
    [8B ($n$=30)], [1 s], [40.3], [34.6], [34.4], [−15%], [−1%], [4/3 (1.0)],
    [], [3 s], [58.0], [39.0], [34.8], [−40%], [−11%], [7/2 (0.18)],
    [], [8 s], [102.2], [51.7], [43.8], [−57%], [−15%], [9/3 (0.15)],
    table.hline(stroke: 0.3pt + luma(180)),
    [14B], [1 s], [51.8], [46.4], [45.6], [−12%], [−2%], [10/4 (0.18)],
    [], [3 s], [74.4], [50.6], [49.0], [−34%], [−3%], [16/9 (0.23)],
    [], [8 s], [130.9], [62.2], [55.8], [−57%], [−10%], [*32/10 (0.001)*],
    table.hline(stroke: 0.3pt + luma(180)),
    [30B-A3B], [1 s], [74.7], [61.0], [58.7], [−21%], [−4%], [*21/9 (0.04)*],
    [], [3 s], [107.8], [63.6], [59.8], [−45%], [−6%], [*24/9 (0.01)*],
    [], [8 s], [190.4], [69.5], [63.3], [−67%], [−9%], [*26/10 (0.01)*],
  ),
  caption: [Modeled seconds per problem. Last column: problems on which mask generated fewer / more tokens than trunc (exact sign test; bold = $p$ < 0.05).],
) <tab-sys>

Asynchronous checking is the robust systems result. Against blocking it saves 12 to 67% of modeled time, the saving growing with latency on every model (@fig-time, @tab-sys), and it gets the same problems right: at 8B, trunc is faster than sync on 27 to 29 of 30 problems at every latency and its accuracy is identical at $L$ = 1, 3 and 8 s. The mechanism is simple: with sync every check adds $L$ to the critical path, whereas an asynchronous verdict only costs time when it is a refutation, and then only the regenerated tokens.

== Masking versus truncation <sec-mask>

At 14B and 30B, masking the invalidated steps in place costs no accuracy (every mask-versus-trunc comparison has $p >= 0.18$; the largest difference is 7 wins / 2 losses for mask at 30B, $L$ = 1 s, no cap) and recomputing the kept steps adds nothing (refresh versus mask 5/3, 4/4, 3/4). It generates significantly fewer tokens than truncation at 30B at every latency and at 14B at $L$ = 8 s (@tab-sys), which is worth 4 to 10% of modeled time; the saving grows with latency, because a verdict that arrives later has more independent work behind it to keep.

At 8B the picture inverts. Masking is as good as truncation at $L$ = 1 s but loses 10 points at 3 s and 27 points at 8 s, where it wins no problem and loses 8 ($p$ = 0.008). Recomputing the kept steps (refresh) recovers 5 of the 8, which shows that stale cache entries, kept steps whose keys and values were computed while attending to the refuted step, carry a large part of the damage at this scale. A replication of the $L$ = 8 s comparison on a different build (Colab L4, @tab-8b) found the same direction with a smaller gap (18/30 versus 22/30; 2 wins / 6 losses, $p$ = 0.29).

The saving does not come from a smaller cache. Peak live cache is 2,200 to 2,500 cells per problem under every checked condition, and the masked spans themselves are small (19 to 38 tokens at peak). Masking saves by regenerating less after a refutation.

== Why masking fails at 8B <sec-why>

Two hypotheses were testable on the existing logs. The first is that the model relies on refuted steps without declaring it, so masking keeps steps it should remove (the leakage mechanism of #c(13, 14)). The solver test of @sec-diag finds such *hidden dependents* in 2 of 30 problems at 8B, 3 to 5 of 100 at 14B and 6 to 9 of 100 at 30B, and on those problems mask and trunc tie. The second is that the model *quits*: after a mask the 8B wrote no further step in 16 of 20 masked problems and answered Uncertain in 16 of 20 (truncation: 13 and 13), getting 1 of 9 True problems right against 6 of 9.

#figure(
  table(columns: 6, align: (left, center, center, center, center, center),
    [Condition (8B, L4, $L$ = 8 s, $n$ = 30)], [Accuracy], [Tokens], [Masks / truncations], [Answers A/B/C], [True right],
    [trunc], [22/30], [558], [0 / 91], [11 / 7 / 12], [8/9],
    [mask], [18/30], [364], [48 / 4], [8 / 6 / 16], [5/9],
    [mask + RETRY], [19/30], [616], [80 / 9], [11 / 6 / 13], [7/9],
    [mask + INFER], [18/30], [366], [48 / 4], [8 / 6 / 16], [5/9],
  ),
  caption: [Diagnostic run at 8B. Solver-inferred dependents (INFER) masked 7 extra steps and changed no answer. Forcing a retry after a mask (RETRY) recovers True problems but loops, generating more tokens than truncation.],
) <tab-8b>

The run in @tab-8b closes both cheap fixes. INFER changed nothing (0 wins / 0 losses against mask): the declared `[uses]` lists are faithful at the logic level, so undeclared dependence is not the mechanism. RETRY recovered the True problems (7 of 9) but only one problem overall (2/1 against mask), at the cost of 80 masks and 616 tokens per problem, more than truncation. What remains is stale cache entries (recoverable by refresh, at a cost) and the small model's tendency to abandon the proof once part of its context disappears. At 8B, truncation is the right policy. The remaining lever is *exact* masking: letting each step attend only to the prompt and its declared parents, so that undeclared reliance and stale entries become impossible by construction; this needs a block-sparse attention mask that llama.cpp does not expose.

== Removing the step cap exposes loops <sec-loops>

Raising the caps for the 30B (20 → 60 steps, 2,500 → 5,000 tokens) changed no accuracy result (every condition $p >= 0.39$ against the capped run). It did show what the cap was hiding: 20 to 29% of problems run to the new cap, almost all by repeating one formula, for example `perfectionist(Wyatt) ∨ thinks_carefully(Wyatt)` restated up to step 60, each repeat checking as entailed. Loops occur in the unchecked format too (20 of 100 problems), so the model causes them, not the checker. Forced answers are 52 to 75% correct against 70 to 84% for unforced ones. Mean tokens nearly double (fmt 617 → 1,179) while the median barely moves (720 → 767); per condition, about 1,000 to 1,150 steps are *restated* and 1,100 to 1,340 formulas hit the verdict cache. This motivated the loop detector.

== Efficiency fixes <sec-eff>

The three fixes of @sec-method-eff were run at 14B, $L$ = 8 s, on 30 problems, with DEPWAIT and LOOP enabled in every condition and HYBRID=50 in the refresh condition, and compared with the round-3 runs of the same policies on the 28 shared problems (@tab-eff, @tab-eff-pairs).

#figure(
  table(columns: 7, align: (left,) + (center,) * 6,
    [Condition], [Accuracy], [Gen tokens], [Wasted], [Wait s], [Modeled s], [Wall s (L4)],
    [trunc], [21/28], [644], [322], [6.9], [62.1], [25.6],
    [mask], [20/28], [621], [243], [6.8], [60.3], [24.9],
    [refresh], [20/28], [644], [316], [7.0], [62.2], [25.6],
    table.hline(stroke: 0.3pt + luma(180)),
    [trunc + DEPWAIT + LOOP], [21/28], [521], [258], [5.8], [52.1], [20.8],
    [mask + DEPWAIT + LOOP], [20/28], [504], [253], [6.4], [51.5], [20.4],
    [hybrid + DEPWAIT + LOOP], [20/28], [536], [276], [5.6], [53.0], [21.5],
  ),
  caption: [The efficiency fixes at 14B, $L$ = 8 s, on the 28 paired problems. Top: the round-3 runs without fixes, restricted to the same problems. Hybrid is refresh with HYBRID=50.],
) <tab-eff>

#figure(
  table(columns: 5, align: (left, center, center, center, center),
    [Comparison], [Accuracy W/L ($p$)], [Fewer tokens W/L ($p$)], [Faster W/L ($p$)], [Modeled time],
    [trunc + fixes vs trunc], [1/1 (1.0)], [8/2 (0.11)], [*11/1 (0.01)*], [−10.0 s (−16%)],
    [mask + fixes vs mask], [1/1 (1.0)], [*10/2 (0.04)*], [*12/1 (0.003)*], [−8.8 s (−15%)],
    [hybrid + fixes vs refresh], [1/1 (1.0)], [8/4 (0.39)], [11/3 (0.06)], [−9.2 s (−15%)],
    table.hline(stroke: 0.3pt + luma(180)),
    [mask vs trunc (both with fixes)], [0/1 (1.0)], [5/6 (1.0)], [4/6 (0.75)], [−0.6 s],
    [hybrid vs trunc (both with fixes)], [0/1 (1.0)], [0/2 (0.5)], [0/2 (0.5)], [+0.8 s],
  ),
  caption: [Paired tests for @tab-eff (exact sign tests, two-sided; bold = $p$ < 0.05).],
) <tab-eff-pairs>

#figure(
  barchart(
    (([trunc], (862, 574, 481)), ([mask], (896, 645, 382)), ([refresh / hybrid], (882, 668, 405))),
    ([looping problems, without fixes], [looping problems, with fixes], [other problems, with or without fixes]),
    (luma(170), C-trunc, rgb("#9dbbe0")),
    ymax: 1000, step: 200, w: 13cm, h: 3.6cm,
  ),
  caption: [Generated tokens per problem, 14B at $L$ = 8 s, split by whether the loop detector fired (12 to 14 of 28 problems). On the other problems the fixed and unfixed runs produced identical transcripts.],
) <fig-eff>

The fixes save 15 to 16% of modeled time and 19% of tokens at no detectable accuracy cost, and the saving is significant for trunc and mask. Three observations locate the gain:

- *The whole gain is the loop detector.* The detector fired on 12 to 14 of the 28 problems; on those, tokens fall from about 880 to 570–670 (@fig-eff). On the other 14 to 16 problems the transcripts, token counts and modeled times are identical to the decimal: the fixes are inert until a loop or an avoidable wait occurs. Accuracy on the looping problems is the same with and without cropping (8/12, 7/13, 9/14 in both runs), so the cropped tokens were pure waste. Five to six problems per condition reached the three-crop limit and were forced to answer.
- *Dependency-scoped waiting saves about one second per problem.* Waits fall from 6.9 to 5.8 s (trunc) and 6.8 to 6.4 s (mask); only 5 to 6 problems per condition had a pending verdict the answer did not depend on, and all of them were looping problems whose answer was forced. Waiting is about 11% of modeled time at $L$ = 8 s, so there was little to recover.
- *The hybrid degenerates into truncation.* The kept-token rule fired 44 times against 3 recomputations (5.8 recomputed tokens per problem): the suffix after a refuted step is usually shorter than 50 tokens. Hybrid and trunc generate nearly identical transcripts (0/2). The threshold is too high, and at 14B recomputation has nothing to recover in any case.

With the fixes in place, mask and trunc remain tied at 14B (5/6 on tokens, 4/6 on time, 0/1 on accuracy).

= Discussion <sec-disc>

*What the checker is for.* On this benchmark the solver mostly catches translation errors, not reasoning errors, and its one measurable effect on accuracy is on Uncertain problems, where it stops the model from "proving" an unprovable goal. Translation into logic is the bottleneck, as in whole-problem formalization #c(20, 23): a formula that parses and is entailed need not say what the English step says. Constrained decoding fixes the syntax but not the faithfulness.

*What asynchrony is for.* The 12 to 67% saving over blocking is the paper-grade systems result. It requires nothing from the model and loses nothing, and it grows with checker latency, which is exactly the regime (an autoformalizer sharing the GPU, Lean) where a checker is expensive enough to matter.

*Where DAG-scoped masking stands.* Masking is the proposal's novel mechanism, and after five rounds its value is real but modest: at 14B and 30B it is 4 to 10% faster than truncation at high latency, with no accuracy cost, and it is never better at low latency, where a refutation arrives before much independent work exists. At 8B it is harmful at high latency, and the diagnosis in @sec-why says why: not undeclared dependencies, which are rare and inert, but stale entries in the kept steps plus a model that gives up. Those are both properties of the attention computation, not of the dependency bookkeeping, which is why the next version of the idea should change the attention pattern (each step attends only to the prompt and its declared parents) rather than the invalidation policy. Compared with budget-driven KV eviction #c(8, 11), our trigger is a correctness signal and our invalidated set is a provenance closure; compared with the leakage literature #c(13, 14, 15), our results say that leakage is a function of model scale and of how long the stale entries are used.

*Loops.* The cheapest result in this report is also the most practical: a two-line check for a repeated formula removes a fifth of the tokens at 14B and changes no answer. It applies to the unchecked step format as well.

= Limitations <sec-limits>

- *Simulated latency.* Checker latency is a token clock, not a real slow checker; a real autoformalizer would share the GPU and slow generation itself.
- *One benchmark, gold premises.* ProverQA-Hard ships gold formulas for its premises, so the checker verifies only the model's step translations, an upper bound on what a fully model-translated pipeline would achieve.
- *Sample size.* The 8B latency sweep and the diagnostic and efficiency runs use 30 problems, which detects only large accuracy changes (@sec-setup). The null accuracy results at $n$ = 30 are "no detectable change", not "no change". The 14B and 30B main results use 100 problems.
- *Self-declared dependencies.* The DAG comes from the model's `[uses]` lists. The solver test in @sec-why bounds the damage at the logic level but cannot see reliance that is not expressible as entailment.
- *Policy evolution.* Several policies (refute-only rejection, the format guard, the token clock) were fixed in response to measured failures during the first two rounds. The reported runs share one fixed policy and were not tuned on their own results.
- *Quantized models, one decoding setting.* All models are 4-bit, in non-thinking mode, with one seed.

= Conclusion and next steps <sec-conc>

A step-level solver check does not make Qwen3 models of 8B to 30B parameters more accurate on ProverQA-Hard, but running the check asynchronously makes a checked pipeline 12 to 67% cheaper than a blocking one at no cost, and removing a refuted step's dependents from the KV cache in place is a further 4 to 10% at 14B and 30B. A loop detector removes another fifth of the tokens. The clear failure, masking at 8B, is now diagnosed to the attention computation rather than to the dependency graph.

Three next steps follow directly. First, replace the simulated latency with a real slow checker, an LLM autoformalizer sharing the GPU or a Lean backend, and re-run the latency sweep at $n >= 100$. Second, make masking exact with a block-sparse attention mask in which each step attends only to the prompt and its declared parents; this removes both stale entries and undeclared reliance by construction and is the version of the idea that could beat truncation at 8B. Third, if the accuracy question is to be settled, run the checked-versus-unchecked comparison on several hundred problems with a second model family; the current nulls are informative about effect size (a few points at most) but not conclusive.

#v(0.6em)
#line(length: 100%, stroke: 0.4pt)
#text(8.5pt)[*Artifacts.* Harness: `run.py`, `logic.py`, `analyze.py`, `analyze_eff5.py`; cloud driver: `cloud/colab.sh`, `cloud/vm.sh`; raw runs: `results/v2/` (8B), `results_cloud/Qwen3-14B/`, `results_cloud/Qwen3-30B-A3B/`, `results_cloud/Qwen3-30B-A3B_v3/`, `results_cloud/Qwen3-8B_infer/`, `results_cloud/Qwen3-14B_eff/`; per-round write-ups with all paired tests: `results/RESULTS.md`.]

= References

#set text(size: 9pt)
#set par(justify: false)
#set enum(numbering: "[1]", spacing: 0.55em)
+ C. Qi, R. Ma, B. Li, H. Du, B. Hui, J. Wu, Y. Laili and C. He. _Large Language Models Meet Symbolic Provers for Logical Reasoning Evaluation_ (ProverQA). ICLR 2025. arXiv:2502.06563.
+ Y. Feng, N. Weir, K. Bostrom, S. Bayless, D. Cassel, S. Chaudhary, B. Kiesl-Reiter and H. Rangwala. _VeriCoT: Neuro-symbolic Chain-of-Thought Validation via Logical Consistency Checks._ arXiv:2511.04662, 2025.
+ J. Hu, S. Yang, W. Liu and D. Wang. _LogicTrack: Auditing Reasoning Trajectories of Large Language Models with Formal Logic Solvers._ arXiv:2609.21492, 2026.
+ C. Liu et al. _Safe: Enhancing Mathematical Reasoning in Large Language Models via Retrospective Step-aware Formal Verification._ ACL 2025. arXiv:2506.04592.
+ G. Poesia, K. Gandhi, E. Zelikman and N. D. Goodman. _Certified Deductive Reasoning with Language Models_ (LogicGuide). arXiv:2306.04031, 2023.
+ S. Mukherjee, A. Chinta, T. Kim, T. A. Sharma and D. Hakkani-Tür. _Premise-Augmented Reasoning Chains Improve Error Identification in Math Reasoning with LLMs_ (PARC). ICML 2025. arXiv:2502.02362.
+ J. Fang, B. Zhang, C. Wang, J. Wan and Z. Xu. _Graph of Verification: Structured Verification of LLM Reasoning with Directed Acyclic Graphs._ AAAI 2026. arXiv:2506.12509.
+ T. Jin. _Self-Orchestrating Language Models: Leveraging Semantic Dependence for Efficient Inference_ (chapter 4, "Thinking in Place"). arXiv:2609.14850, 2026.
+ D. Choi et al. _Think Clearly: Improving Reasoning via Redundant Token Pruning._ arXiv:2507.08806, 2025.
+ C. Yang, N. Srebro, D. McAllester and Z. Li. _PENCIL: Long Thoughts with Short Memory._ ICML 2025. arXiv:2503.14337.
+ B. Feng et al. _StepKV: Step-Aware KV Cache Compression for LLM Agents._ arXiv:2609.22158, 2026.
+ Y. Chen, Z. Liu, Z. Huang, R. Gui, H. Wang and L. Liu. _ArborKV: Structure-Aware KV Cache Management for Scaling Tree-based LLM Reasoning._ arXiv:2605.22106, 2026.
+ C. Zhou et al. _Positions Are Not Facts: The Mismatch Between KV Caches and Memory._ arXiv:2609.33759, 2026.
+ G. Zhang and H. Yang. _Aborted but Not Forgotten: KV-Cache Retention Breaks Rollback Consistency in Language Agents._ arXiv:2608.15939, 2026.
+ M. Li et al. _KVEraser: Learning to Steer KV Cache for Efficient Localized Context Erasing._ ICML 2026 Workshop on the Impact of Memorization on Trustworthy Foundation Models. arXiv:2606.17034.
+ J. Yao et al. _CacheBlend: Fast Large Language Model Serving for RAG with Cached Knowledge Fusion._ EuroSys 2025. arXiv:2405.16444.
+ J. Doyle. _A Truth Maintenance System._ Artificial Intelligence 12(3), 1979. doi:10.1016/0004-3702(79)90008-0.
+ R. M. Stallman and G. J. Sussman. _Forward Reasoning and Dependency-Directed Backtracking in a System for Computer-Aided Circuit Analysis._ Artificial Intelligence 9(2), 1977. doi:10.1016/0004-3702(77)90029-7.
+ J. de Kleer. _An Assumption-Based TMS._ Artificial Intelligence 28(2), 1986. doi:10.1016/0004-3702(86)90080-9.
+ L. Pan, A. Albalak, X. Wang and W. Y. Wang. _Logic-LM: Empowering Large Language Models with Symbolic Solvers for Faithful Logical Reasoning._ Findings of EMNLP 2023. arXiv:2305.12295.
+ A. Gupta, I. S. Mumick and V. S. Subrahmanian. _Maintaining Views Incrementally._ SIGMOD 1993. doi:10.1145/170035.170066.
+ Y. Wang et al. _PACMI: Provenance-Aware Cascading Memory Invalidation for Long-Term LLM Agents._ arXiv:2610.05732, 2026.
+ R. Cornish et al. _FaithformBench: Benchmarking Faithfulness of Mathematical Chain-of-Thought Autoformalisation._ arXiv:2608.10916, 2026.
