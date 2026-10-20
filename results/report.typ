// Results summary, rounds 1–3. Build: typst compile results/report.typ
#set page(paper: "us-letter", margin: (x: 2cm, y: 1.8cm), numbering: "1")
#set text(size: 10pt)
#set par(justify: true)
#set heading(numbering: "1.")
#show heading: set block(above: 1.2em, below: 0.7em)
#show figure.caption: set text(size: 9pt)
#show table.cell.where(y: 0): set text(weight: "bold")
#set table(stroke: (_, y) => if y == 0 { (bottom: 0.6pt) } else { none }, inset: (x: 5pt, y: 3.2pt))

#let C-sync = luma(120)
#let C-trunc = rgb("#2f6db5")
#let C-mask = rgb("#d9622b")
#let C-bad = rgb("#e8a5a5")
#let C-dep = rgb("#f6d4d4")
#let C-keep = rgb("#dbe8f6")
#let C-re = rgb("#fbe9b7")

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

#let barchart(groups, labels, colors, ymax: 80, w: 15cm, h: 3.8cm) = {
  let gw = w / groups.len()
  let bw = gw * 0.82 / labels.len()
  let py(y) = h - y / ymax * h
  block(inset: (left: 1.9em, bottom: 1.6em, top: 0.6em), box(width: w, height: h, {
    for t in range(0, ymax + 1, step: 20) {
      place(line(start: (0pt, py(t)), end: (w, py(t)), stroke: 0.3pt + luma(215)))
      place(dx: -1.9em, dy: py(t) - 0.45em, box(width: 1.6em, align(right, text(7pt)[#t])))
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

// ---------- document ----------
#align(center)[
  #text(15pt, weight: "bold")[Solver-Checked Reasoning with KV-Cache Invalidation]\
  #v(0.2em)
  #text(10pt)[Results summary, rounds 1–3 · UW undergraduate research · October 2026]
]
#v(0.6em)

*Question.* A language model reasons step by step, and an SMT solver (Z3) checks each step against the problem's premises. We ask two things:
- Does step checking improve accuracy?
- When a step is refuted, can it be removed cheaply? Instead of truncating everything after it, we mask the refuted step and its dependents in the KV cache and keep the independent work.

*Short answer.*
- Checking does not improve accuracy at any model size we tried.
- The systems side works: checking asynchronously is 12–67% faster than waiting for each verdict.
- At 14B and 30B, masking dependents costs no accuracy and uses significantly fewer tokens than truncation.

= Method

*Task and models.*
- *Task:* ProverQA-Hard, first-order-logic problems with answers True / False / Uncertain; Z3 reproduces the gold label on 498/500.
- *Models:* Qwen3-8B (n = 30, laptop GPU); Qwen3-14B and Qwen3-30B-A3B (n = 100 each, Colab L4). All are Q4_K_M quantized, run via llama.cpp.

*Step format.* Each step has the form `Step k [uses P2, S1]: <fact>`, followed by `FOL: <formula>`. The solver labels the formula _entailed_, _refuted_ or _unknown_ given the premises. Only refuted steps are rejected.

*Conditions.*
- *base:* ProverQA's own chain-of-thought prompt.
- *fmt:* the step format, unchecked.
- *sync:* wait for every verdict.
- *trunc:* asynchronous checking; on a refutation, cut the cache back to the refuted step and regenerate.
- *mask:* asynchronous checking; remove the refuted step and every step whose `[uses]` chain reaches it, and keep the rest.
- *refresh:* mask, then recompute the kept steps so their cache entries never saw the refuted one.

Masking deletes a middle range of the cache (`kv_cache_seq_rm`). That is equivalent to setting those positions' attention to −∞ for all future tokens.

*Latency.* Checker latency $L in {1, 3, 8}$ s is simulated on a token clock: $L = 1$ s is about 14 generated tokens. Modeled time per problem is $8.6 "s" + 72.4 "ms" times "tokens" +$ checker waits, which makes it comparable across machines.

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
  caption: [Blocking vs. asynchronous checking. With sync, every step waits $L$ for its verdict. Async keeps generating while the solver works and acts on a refutation when it arrives (here, during S4).],
) <fig-timeline>

#figure(
  {
    set align(left)
    let row(label, cells, note) = (align(right + horizon, text(8pt, label)), ..cells, align(horizon, text(8pt, note)))
    grid(columns: (2.6cm,) + (1.15cm,) * 7 + (auto,), column-gutter: 2pt, row-gutter: 5pt,
      ..row([S3 refuted],(cell[P], cell[S1], cell[S2], cell([S3 ✗], fill: C-bad), cell[S4], cell([S5→S3], fill: C-dep), cell[S6]), []),
      ..row([*truncate*], (cell[P], cell[S1], cell[S2], gone[S3], gone[S4], gone[S5], gone[S6]), [regenerate from S3]),
      ..row([*mask* (ours)], (cell[P], cell[S1], cell[S2], gone[S3], cell[S4], gone[S5], cell[S6]), [continue at S7]),
      ..row([*refresh*], (cell[P], cell[S1], cell[S2], gone[S3], cell([S4], fill: C-re), gone[S5], cell([S6], fill: C-re)), [recompute S4, S6, continue]),
    )
    v(0.3em)
    align(center, text(8pt)[#swatch(C-keep) kept #h(1em) #swatch(C-bad) refuted #h(1em) #swatch(C-dep) uses a refuted step #h(1em) #box(width: 0.8em, height: 0.8em, stroke: (dash: "dashed", paint: luma(90), thickness: 0.5pt), baseline: 0.1em) removed from cache #h(1em) #swatch(C-re) recomputed])
  },
  caption: [What each policy does to the KV cache when step S3 is refuted. Step S5 declared `[uses S3]`, so masking removes it too, while independent steps S4 and S6 stay. Truncation discards all of them.],
) <fig-cache>

= Results

#figure(
  table(columns: 5, align: (left, center, center, center, center),
    [Condition], [8B (n=30)], [14B (n=100)], [30B (n=100)], [30B, no cap],
    [base (plain CoT)], [46.7], [58], [57], [57],
    [fmt (steps, unchecked)], [56.7], [66], [67], [71],
    [sync], [53.3], [65], [73], [71],
    [trunc, $L$ = 1 / 3 / 8 s], [63.3 / 63.3 / 63.3], [70 / 70 / 70], [72 / 73 / 73], [71 / 71 / 71],
    [mask, $L$ = 1 / 3 / 8 s], [60.0 / 53.3 / *36.7*], [70 / 71 / 71], [74 / 72 / 71], [76 / 72 / 73],
    [refresh, $L$ = 8 s], [53.3], [73], [71], [72],
  ),
  caption: [Accuracy (% correct). Always answering "Uncertain" scores about 40%. The 8B mask loss at $L$ = 8 s is the only significant checked-vs-checked difference (0 wins / 8 losses vs. trunc, $p$ = 0.008).],
) <tab-acc>

#figure(
  barchart(
    (([8B (n=30)], (46.7, 56.7, 53.3, 63.3, 36.7)), ([14B], (58, 66, 65, 70, 71)), ([30B-A3B], (57, 67, 73, 73, 71))),
    ([base], [fmt], [sync], [trunc, $L$=8 s], [mask, $L$=8 s]),
    (luma(200), rgb("#9dbbe0"), C-sync, C-trunc, C-mask),
  ),
  caption: [The step format helps (+8 to +14 points over CoT); the checker on top of it does not. Masking collapses at 8B with a slow checker but is fine at 14B and 30B.],
) <fig-acc>

#figure(
  grid(columns: 3, column-gutter: 0.4cm,
    linechart([8B (n=30)], (40.3, 58.0, 102.2), (34.6, 39.0, 51.7), (34.4, 34.8, 43.8), ymax: 120, step: 40),
    linechart([14B], (51.8, 74.4, 130.9), (46.4, 50.6, 62.2), (45.6, 49.0, 55.8), ymax: 150),
    linechart([30B-A3B], (74.7, 107.8, 190.4), (61.0, 63.6, 69.5), (58.7, 59.8, 63.3), ymax: 200),
  ) + align(center, text(8pt)[#swatch(C-sync) sync #h(1.2em) #swatch(C-trunc) async + truncate #h(1.2em) #swatch(C-mask) async + mask]),
  caption: [Modeled seconds per problem vs. checker latency. Blocking cost grows with every check; async cost barely moves.],
) <fig-time>

#figure(
  table(columns: 8, align: (left, center) + (right,) * 5 + (center,),
    [Model], [$L$], [sync], [trunc], [mask], [mask vs sync], [mask vs trunc], [fewer tokens, W/L ($p$)],
    [8B (n=30)], [1 s], [40.3], [34.6], [34.4], [−15%], [−1%], [4/3 (1.0)],
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
  caption: [Modeled seconds per problem. Last column: problems where mask generated fewer / more tokens than trunc (exact sign test; bold = p < 0.05). Mask is 1–15% faster than trunc, the gap growing with latency.],
) <tab-sys>

= Findings

+ *The checker does not improve accuracy at any scale.* Checked (sync) minus unchecked (fmt) is −3 points at 8B, −1 at 14B and +6 at 30B ($p$ = 0.11). The step format itself is what helps: +8 to +14 points over plain CoT, significant at $p$ = 0.04 for the 30B in the no-cap run.
+ *Asynchronous checking is the robust systems result.* It is 12–67% faster than blocking on every model, with the gap growing with checker latency (@fig-time), and costs no accuracy.
+ *Masking depends on model scale.*
  - At 8B, masking with a slow checker lost 8 problems to truncation and won none. By the time a verdict arrived, later "independent" steps had already absorbed the refuted step's content without declaring it in `[uses]`. Recomputing (refresh) recovered 5 of the 8.
  - At 14B and 30B, masking costs no accuracy (all $p >= 0.18$), and refresh adds nothing.
  - At 30B, masking uses significantly fewer tokens than truncation at every latency, saving 4–9% of time.
+ *Ablation: removing the step cap (20 → 60 steps) changed no accuracy result* (every condition $p >= 0.39$). It exposed repetition loops: 20–29% of problems repeat one formula until the new cap, in unchecked runs too. Mean tokens nearly double (617 → 1179 for fmt) while the median barely moves (720 → 767). The 20-step cap is a reasonable stopping rule.
+ *Context use.* Peak live KV cache is about 2,200–2,500 tokens per problem. Masked spans are small (19–38 tokens at peak), so masking saves by regenerating less after a refutation, not by keeping a smaller cache.

= Limitations and next steps

*Limitations.*
- Checker latency is simulated rather than coming from a real slow checker.
- Masking relies on the model's self-declared dependencies, which the 8B violated.
- The results come from one benchmark.
- The 8B runs use n = 30.

*Next steps.*
1. Use a real slow checker, such as an LLM autoformalizer sharing the GPU, or Lean.
2. Make masking exact by letting each step attend only to the prompt and its declared parents (block-sparse attention). Undeclared reliance then becomes impossible by construction.
