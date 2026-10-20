// Research report, significant results only. Build: typst compile results/paper.typ
// Long version with every round, including null results: results/paper_full.typ
#set page(paper: "us-letter", margin: (x: 2.2cm, y: 2cm), numbering: "1")
#set text(size: 10pt)
#set par(justify: true)
#set heading(numbering: "1.1")
#show heading.where(level: 1): set block(above: 1.5em, below: 0.8em)
#show heading.where(level: 2): set block(above: 1.2em, below: 0.6em)
#show figure.caption: set text(size: 9pt)
#show table.cell.where(y: 0): set text(weight: "bold")
#set table(stroke: (_, y) => if y == 0 { (bottom: 0.6pt) } else { none }, inset: (x: 5pt, y: 3.2pt))
#show table: set par(justify: false)
#set footnote.entry(gap: 0.5em)

#let c(..ns) = "[" + ns.pos().map(str).join(", ") + "]"
#let mono(body) = text(font: "DejaVu Sans Mono", size: 0.8em, body)

#let C-sync = luma(120)
#let C-trunc = rgb("#2f6db5")
#let C-mask = rgb("#d9622b")
#let C-bad = rgb("#e8a5a5")
#let C-dep = rgb("#f6d4d4")
#let C-keep = rgb("#dbe8f6")
#let C-ok = rgb("#d6ecd2")

// ---------- drawing helpers ----------
#let swatch(c) = box(width: 0.8em, height: 0.8em, fill: c, baseline: 0.1em)

#let ylab(h, body) = place(dx: -3.4em, dy: 0pt, box(width: 1em, height: h, align(center + horizon, rotate(-90deg, reflow: true, text(7pt, fill: luma(80), body)))))
#let xlab(w, h, body) = place(dx: 0pt, dy: h + 1.2em, box(width: w, align(center, text(7pt, fill: luma(80), body))))

#let linechart(title, sync, trunc, mask, ymax: 200, step: 50, w: 4.3cm, h: 3.2cm, ylabel: [seconds per problem], xlabel: [checker delay $L$]) = {
  let xs = (1, 3, 8)
  let px(x) = x / 9 * w
  let py(y) = h - y / ymax * h
  block(inset: (left: 3.3em, bottom: 2.4em, top: 1.4em), box(width: w, height: h, {
    for t in range(0, ymax + 1, step: step) {
      place(line(start: (0pt, py(t)), end: (w, py(t)), stroke: 0.3pt + luma(215)))
      place(dx: -1.9em, dy: py(t) - 0.45em, box(width: 1.6em, align(right, text(7pt)[#t])))
    }
    for x in xs {
      place(dx: px(x) - 1em, dy: h + 0.3em, box(width: 2em, align(center, text(7pt)[#x s])))
    }
    ylab(h, ylabel); xlab(w, h, xlabel)
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

// grouped bars; dim: same shape as the values, true = draw the bar pale (not significant)
#let barchart(groups, labels, colors, ymax: 80, step: 20, w: 15cm, h: 3.8cm, dim: none, unit: "", ylabel: none) = {
  let gw = w / groups.len()
  let bw = gw * 0.82 / labels.len()
  let py(y) = h - y / ymax * h
  block(inset: (left: 3.4em, bottom: 1.6em, top: 0.6em), box(width: w, height: h, {
    for t in range(0, ymax + 1, step: step) {
      place(line(start: (0pt, py(t)), end: (w, py(t)), stroke: 0.3pt + luma(215)))
      place(dx: -2.2em, dy: py(t) - 0.45em, box(width: 1.9em, align(right, text(7pt)[#t#unit])))
    }
    if ylabel != none { ylab(h, ylabel) }
    for (gi, (name, vals)) in groups.enumerate() {
      let x0 = gi * gw + gw * 0.09
      for (i, v) in vals.enumerate() {
        let pale = dim != none and dim.at(gi).at(i)
        let col = if pale { colors.at(i).lighten(65%) } else { colors.at(i) }
        place(dx: x0 + i * bw, dy: py(v), rect(width: bw * 0.88, height: v / ymax * h, fill: col, stroke: none))
        place(dx: x0 + i * bw - 0.6em, dy: py(v) - 1.05em, box(width: bw * 0.88 + 1.2em, align(center, text(6.5pt, fill: if pale { luma(120) } else { black })[#v])))
      }
      place(dx: gi * gw, dy: h + 0.35em, box(width: gw, align(center, text(8pt, name))))
    }
    place(line(start: (0pt, h), end: (w, h), stroke: 0.6pt))
    place(line(start: (0pt, 0pt), end: (0pt, h), stroke: 0.6pt))
  }))
  align(center, text(8pt, labels.zip(colors).map(((l, c)) => [#swatch(c) #l]).join(box(width: 1.2em))))
}

// heat table: rows = models, columns = checker delays. Cell colour = significance, scaled so the block's most
// significant cell is full colour and p = 1 is white; hue = direction; bold = p < 0.05. Cells are (value, p).
#let heatcell(v, p, pmin, neg, pos, fmt) = {
  let q = if pmin >= 1 { 0 } else { calc.log(calc.max(p, 1e-9), base: 10) / calc.log(pmin, base: 10) }
  let q = calc.min(1, calc.max(0, q))
  let c = color.mix((white, (1 - 0.75 * q) * 100%), (if v < 0 { neg } else { pos }, 0.75 * q * 100%))  // capped so black text stays readable
  let ps = if p < 0.01 { str(calc.round(p, digits: 3)) } else { str(calc.round(p, digits: 2)) }
  table.cell(fill: c, stroke: 0.4pt + luma(185), align(center + horizon, stack(dir: ttb, spacing: 2pt,
    text(8.5pt, weight: if p < 0.05 { "bold" } else { "regular" }, fmt(v)), text(5.5pt, fill: luma(70))[$p$=#ps])))
}
#let heat(labels, time, acc) = {
  let one(v) = { let r = calc.round(v, digits: 1); let i = calc.trunc(r); str(i) + "." + str(calc.round(calc.abs(r - i) * 10)) }  // one decimal, always
  let pct(v) = [#one(v)%]
  let pts(v) = if v > 0 [+#one(v)] else if v < 0 [−#one(-v)] else [0.0]
  let pmin(b) = calc.min(..b.map(r => r.map(c => c.at(1))).flatten())
  let (pt, pa) = (pmin(time), pmin(acc))
  let head(t) = table.cell(colspan: 3, align(center, text(8pt, weight: "bold", t)))
  let sub(t) = align(center, pad(top: 3pt, text(7.5pt, fill: luma(90), t)))
  let sq = 1.0cm
  table(columns: (auto, sq, sq, sq, 0.35cm, sq, sq, sq), rows: (auto, auto, ..labels.map(l => sq)), stroke: none, inset: (x: 3pt, y: 0pt), gutter: 2pt, align: horizon,
    [], head[time saved], [], head[accuracy change],
    [], sub[1 s], sub[3 s], sub[8 s], [], sub[1 s], sub[3 s], sub[8 s],
    ..labels.zip(time, acc).map(((l, t, a)) => (
      align(right, text(8pt, l)),
      ..t.map(((v, p)) => heatcell(v, p, pt, rgb("#b86a2a"), rgb("#1f7f8c"), pct)), [],
      ..a.map(((v, p)) => heatcell(v, p, pa, rgb("#d9534f"), rgb("#3f9a5f"), pts)),
    )).flatten())
}

#let U = 0.95cm
#let seg(row, x, len, label, fill, stroke: none) = place(dx: x * U, dy: row * 0.75cm,
  rect(width: len * U - 1pt, height: 0.55cm, fill: fill, stroke: stroke, inset: 0pt,
    align(center + horizon, text(7pt, label))))
#let lane(row, label) = place(dx: -2.9cm, dy: row * 0.75cm + 0.12cm, box(width: 2.7cm, align(right, text(8pt, label))))

#let cell(l, fill: C-keep, dash: none, fg: black, w: 1.15cm) = box(width: w, height: 0.62cm,
  fill: fill, stroke: (paint: luma(90), thickness: 0.5pt, dash: dash),
  align(center + horizon, text(8pt, fill: fg, l)))
#let gone(l, w: 1.15cm) = cell(l, fill: none, dash: "dashed", fg: luma(150), w: w)
#let dashed-swatch = box(width: 0.8em, height: 0.8em, stroke: (dash: "dashed", paint: luma(90), thickness: 0.5pt), baseline: 0.1em)

// flowchart: boxes at absolute positions, arrows with heads
#let fbox(x, y, w, h, body, fill: luma(247)) = place(dx: x, dy: y, box(width: w, height: h, inset: (x: 5pt, y: 4pt), fill: fill, stroke: 0.6pt + luma(110), radius: 3pt, align(center + horizon, text(8pt, body))))
#let head(x, y, ux, uy) = {  // triangle with tip at (x, y), pointing along unit (ux, uy)
  let L = 5pt; let W = 2.6pt
  place(polygon(fill: black, (x, y), (x - ux * L + uy * W, y - uy * L - ux * W), (x - ux * L - uy * W, y - uy * L + ux * W)))
}
#let arr(x1, y1, x2, y2) = {
  let dx = (x2 - x1).cm(); let dy = (y2 - y1).cm(); let n = calc.sqrt(dx * dx + dy * dy)
  place(line(start: (x1, y1), end: (x2, y2), stroke: 0.7pt))
  head(x2, y2, dx / n, dy / n)
}

// ---------- front matter ----------
#align(center)[
  #set par(justify: false)
  #text(16pt, weight: "bold")[Keeping a Step Checker Off the Critical Path:\ Measured Savings from Asynchronous Verification, KV-Cache Masking and Loop Cropping]
  #v(0.6em)
  #text(11pt)[Aditya Bankoti]\
  #text(9.5pt)[University of Washington]\
  #text(9.5pt)[Technical report, October 2026]
]
#v(0.8em)

#block(inset: (x: 1.2cm), [
  #set text(size: 9.5pt)
  *Abstract.* A language model that reasons in written steps makes mistakes in individual steps. If each step is also written as a logic formula, an automated prover can check it against the problem's premises. This report measures the cost of running such a checker alongside a small language model, and three ways of lowering it, on ProverQA-Hard with Qwen3 models of 8B, 14B and 30B parameters and simulated checker delays of 1, 3 and 8 seconds, then on five more models from four families at a smaller sample. All comparisons are paired on the same problems. Letting the model keep writing while the checker works is faster than pausing for each verdict on every model at every delay ($p < 0.001$), by 12 to 67%. When a step is refuted, deleting only it and the steps built on it (masking) beats deleting everything after it (truncation) on the 30B at every delay and on the 14B at 8 s ($p <= 0.04$), by 4 to 10%; on the Qwen3-8B at 8 s it instead costs accuracy (0 wins, 8 losses, $p$ = 0.008), a failure that recurs on none of the other seven models. Deleting steps that repeat an earlier step removes 19% of generated text and 16% of time on the 14B ($p <= 0.01$) without changing an answer. The checked pipeline beats plain chain-of-thought on every model, but which half does the work depends on the family: on Qwen3 the step format alone carries the gain (8 to 20 points) and the checker adds nothing; on Llama, Phi and Mistral the format alone does nothing and the checker carries it (pooled 17 wins to 3 losses, $p$ = 0.003).
])
#v(0.6em)

= Introduction

Language models of 8 to 30 billion parameters can solve multi-step logic problems, but a wrong step early in the chain corrupts everything after it. If each step is written both in English and as a formula in formal logic, a program can check the formula against the problem's premises and catch the mistake when it is made. This report is about such a pipeline: a small language model writes numbered steps, each with a formula and a list of the earlier steps it relies on; the prover Z3 (@sec-z3) checks each formula; and a step that contradicts the premises is removed together with every later step that relied on it.

The step format made the models more accurate; the checker on top of it did not (@sec-acc). What we measured is the checker's cost, which depends on three choices: whether the model waits for each verdict; whether a refuted step takes everything after it with it, or only the steps that depended on it; and whether obviously wasted text, such as a step that repeats an earlier one, is cut. Each choice was tested as a paired comparison on the same problems. We report only differences that are statistically significant; a companion report covers every experiment, including those that found nothing.

+ *The checked pipeline beats plain chain-of-thought on every model, but the gain comes from a different half depending on the family.* On the five Qwen3 models the step format alone raises accuracy by 8 to 20 points and the checker adds nothing; on Llama 3.1, Phi-4 and Mistral the format alone does nothing and the checker carries the gain (pooled 17/3, $p$ = 0.003) (@sec-acc).
+ *Letting the model keep writing while the checker works ("asynchronous") beats waiting for each verdict ("blocking")* on every model at every delay, saving 12 to 67% of the time per problem with the same answers (@sec-async).
+ *On the two larger models, deleting only a refuted step and the steps built on it ("masking") beats deleting everything after it ("truncation")* by 4 to 10%: on the 30B at every delay, on the 14B when the checker is slow (@sec-mask).
+ *On the 8B with a slow checker, masking costs accuracy:* 36.7% correct against 63.3% under truncation ($p$ = 0.008). The loss recurs on none of the other seven models, including a 4B and an 8B of another family, so it is one model's failure rather than a size threshold (@sec-mask).
+ *Deleting steps that repeat an earlier step ("loop cropping") removes 19% of the generated text and 16% of the time on the 14B,* with identical answers (@sec-loops).

#block(width: 100%, inset: 8pt, stroke: 0.5pt + luma(150), radius: 3pt, [
  #set text(size: 9pt)
  *Terms.*
  #set par(spacing: 0.5em)
  - *First-order logic (FOL) formula.* A statement built from predicates such as `is_open_minded(Raphael)` with ¬ (not), ∧ (and), ∨ (or), → (implies), ⊕ (exactly one of), ∀ (for all) and ∃ (there exists).
  - *Z3.* An automated prover: given a set of formulas, it decides whether they can all be true at once (@sec-z3).
  - *Verdict.* What the checker says about a step's formula: *entailed* (the premises force it true), *refuted* (they force it false) or *unknown*.
  - *Checker delay $L$.* The time from a step being written to its verdict arriving; simulated as 1, 3 or 8 seconds (@sec-z3).
  - *Blocking, asynchronous.* Whether the model waits for each verdict before writing the next step, or keeps writing (@sec-sync).
  - *Truncation, masking.* The two ways of removing a refuted step and its dependents: delete everything after it, or delete only those steps (@sec-policies).
])

= Background <sec-background>

== The task <sec-task>

Each problem in ProverQA-Hard #c(1) is a list of premises about a person followed by a statement, and the answer is whether the statement is true, false or uncertain given the premises. The benchmark was generated by a symbolic prover, so every premise comes with its logic formula and the labels are correct; Z3 reproduces the published label on 498 of the 500 problems. @fig-example shows one, with what the model wrote.

#figure(
  kind: image, placement: auto,
  block(width: 100%, inset: 8pt, stroke: 0.5pt + luma(150), radius: 3pt, [
    #set text(size: 8.5pt)
    #set align(left)
    #set par(spacing: 0.45em)
    *Premises (problem 342).* Each comes with its logic formula; two are shown.
    #v(0.15em)
    #let P(n, body) = (text(weight: "bold", fill: luma(90))[P#n], body)
    #grid(columns: (auto, 1fr, auto, 1fr), column-gutter: (4pt, 12pt, 4pt), row-gutter: 2.5pt,
      ..P(1)[Everyone who values critique either embraces debate or is open-minded (or both).],
      ..P(7)[Raphael is either a respected authority or a doubted expert, but not both.],
      ..P(2)[Anyone who considers alternatives and questions assumptions can challenge the status quo.],
      ..P(8)[Raphael does not embrace debate.],
      ..P(3)[Raphael has extensive knowledge.],
      ..P(9)[Raphael does not gain recognition.],
      ..P(4)[Raphael does not write influential books.],
      ..P(10)[If Raphael challenges the status quo, then he either writes influential books or speaks authoritatively (or both).],
      ..P(5)[Raphael is either a respected authority or has unconventional views, but not both.\ #mono[respected_authority(Raphael) ⊕ has_unconventional_views(Raphael)]],
      ..P(11)[If someone is open-minded and has unconventional views, then they challenge the status quo.\ #mono[∀x ((is_open_minded(x) ∧ has_unconventional_views(x)) → challenges_status_quo(x))]],
      ..P(6)[Anyone who has extensive knowledge and speaks authoritatively gains recognition.],
      ..P(12)[Raphael values critique.],
    )
    #v(0.25em)
    *Statement.* Raphael is a doubted expert. #h(1em) *Gold label:* False.

    #v(0.3em)
    *What the 14B model wrote, with the checker's verdicts* (asynchronous run, 8-second checker, masking):
    #v(0.2em)
    #table(columns: (auto, auto, 1fr, auto, auto), align: (left, left, left, left, left), inset: (x: 4pt, y: 2.5pt),
      [Step], [uses], [Claim, and the formula the model wrote for it], [Verdict], [What happened],
      [S1], [P12, P1], [Raphael either embraces debate or is open-minded.\ #mono[embraces_debate(Raphael) ∨ is_open_minded(Raphael)]], [not a fact], [kept, unchecked],
      [S2], [S1, P8], [Raphael is open-minded.\ #mono[is_open_minded(Raphael)]], [entailed], [kept],
      table.cell(fill: C-bad)[S3], table.cell(fill: C-bad)[S2, P5], table.cell(fill: C-bad)[Raphael has unconventional views.\ #mono[has_unconventional_views(Raphael)]], table.cell(fill: C-bad)[*refuted*], table.cell(fill: C-bad)[removed],
      table.cell(fill: C-dep)[S4], table.cell(fill: C-dep)[S2, *S3*, P11], table.cell(fill: C-dep)[Raphael challenges the status quo.], table.cell(fill: C-dep)[(pending)], table.cell(fill: C-dep)[removed: built on S3],
      table.cell(fill: C-dep)[S5], table.cell(fill: C-dep)[*S4*, P10], table.cell(fill: C-dep)[Raphael either writes influential books or speaks authoritatively.], table.cell(fill: C-dep)[(pending)], table.cell(fill: C-dep)[removed: built on S4],
      table.cell(fill: C-dep)[S6], table.cell(fill: C-dep)[*S5*, P4], table.cell(fill: C-dep)[Raphael speaks authoritatively.], table.cell(fill: C-dep)[(pending)], table.cell(fill: C-dep)[removed: built on S5],
      table.cell(fill: C-dep)[S7], table.cell(fill: C-dep)[*S6*, P3, P6], table.cell(fill: C-dep)[Raphael gains recognition.], table.cell(fill: C-dep)[(pending)], table.cell(fill: C-dep)[removed: built on S6],
    )
    #v(0.2em)
    S3 is wrong: P3, P9 and P6 give that Raphael does not speak authoritatively; with P4 and P10, he does not challenge the status quo; with P11 and S2, he cannot have unconventional views. The verdict arrived after the model had written S4 to S7, each of which uses the step before it, so all five were removed and a note was appended. The model continued from S2 and answered False, correctly.
  ]),
  caption: [A worked example. The third step contradicts the premises, and the four steps that declared a dependency on it are removed with it.],
) <fig-example>

== Reasoning in checked steps <sec-steps>

The model is asked to reason in numbered steps of the form

#align(center, box(inset: 0.4em, fill: luma(245), radius: 2pt, align(left, mono[Step k \[uses P2, S1\]: ⟨claim in English⟩\ FOL: ⟨the same claim as a formula⟩])))

ending with `Answer: A/B/C`. The `[uses]` list names the premises (`P`) and earlier steps (`S`) the step is derived from, so the steps form a dependency graph; in @fig-example it is the chain S3 → S4 → S5 → S6 → S7. The model writes the list itself, and we take it at face value.

== What Z3 does, and why its delay is the variable <sec-z3>

Z3 is an SMT solver: given a set of formulas, it decides whether they can all be true at once. For a step's formula $phi$ and the premises $Gamma$ we ask it two questions. If $Gamma$ together with $not phi$ cannot all be true, the premises *entail* $phi$. If $Gamma$ together with $phi$ cannot all be true, they *refute* $phi$. Otherwise the verdict is *unknown*. Only refuted steps are removed. A formula that is not a plain fact (S1 in @fig-example, an "or") is kept unchecked. Z3 sees only the formula, never the English, so a step with a correct claim and a wrong formula is judged on the formula; this is one reason the checker does not improve accuracy (@sec-acc).

On this benchmark Z3 answers in milliseconds, so a pipeline deployed as built would lose almost nothing by waiting for it. A realistic pipeline is slower in front of Z3: the English step has to be translated into logic by a separate model call, or the check is done by a proof assistant such as Lean, or the checker shares the GPU with generation. We therefore treat the checker's delay (latency) $L$ as the variable and simulate a checker that returns each verdict $L$ seconds after the step was written, for $L$ = 1, 3 and 8 s. The 8-second setting stands for a proof assistant or a loaded GPU; 1 second is close to a fast translation model.

= Prior work <sec-prior>

Three findings frame this report. Checking reasoning steps with a formal prover catches real errors, whether after the chain is complete #c(2, 4) or during generation by regenerating from the last verified step #c(3); benchmarks with gold formulas make it possible #c(1), and dependency graphs over steps have been used to trace how a wrong step corrupts later ones #c(5). Deleting reasoning tokens from the KV cache during generation saves memory and can improve accuracy when the deleted tokens are chosen by a budget or a learned signal #c(6, 7, 8). And deleting a span from the cache does not erase its influence, because later tokens were computed while it was visible; exact erasure requires recomputing everything after the span #c(9, 10, 11). Retracting a conclusion together with everything derived from it is an old idea in artificial intelligence and databases #c(12, 13). Not previously measured: a prover's verdict as the trigger, the model's own dependency list as the scope, a live KV cache as the target, and checker delay as the variable.

= The pipeline <sec-method>

#figure(
  kind: image,
  box(width: 15cm, height: 5cm, {
    let (y0, bh) = (0.3cm, 1.3cm)
    fbox(0cm, y0, 2.8cm, bh)[*Prompt*\ premises, formulas,\ statement]
    fbox(3.4cm, y0, 3.1cm, bh)[*Model writes step $k$*\ claim, `[uses]`, formula]
    fbox(7.1cm, y0, 3.9cm, bh, fill: C-ok)[*Checker (Z3) checks step $k$*\ while the model writes\ steps $k+1$, $k+2$, …]
    fbox(11.6cm, y0, 3.4cm, bh)[*Answer A / B / C*\ once the last\ verdict is in]
    arr(2.8cm, 0.95cm, 3.4cm, 0.95cm)
    arr(6.5cm, 0.95cm, 7.1cm, 0.95cm)
    arr(11.0cm, 0.95cm, 11.6cm, 0.95cm)
    // verdict branch under the checker
    fbox(4.6cm, 2.9cm, 7.4cm, 1.8cm, fill: luma(252))[*Verdict for step $k$*\ entailed or unknown: nothing to do.\ #text(fill: rgb("#8f1f1f"))[*refuted:* remove step $k$ and every step whose `[uses]` chain reaches it, by *truncation* or *masking*; append a note.]]
    arr(9.05cm, 1.6cm, 9.05cm, 2.9cm)
    // feedback: continue from the last kept step
    place(line(start: (4.6cm, 3.8cm), end: (3.9cm, 3.8cm), stroke: 0.7pt))
    arr(3.9cm, 3.8cm, 3.9cm, 1.6cm)
    place(dx: 0cm, dy: 2.5cm, box(width: 3.6cm, align(right, text(7.5pt, fill: luma(80))[the model continues\ from the last kept step])))
  }),
  caption: [The pipeline. The checker runs beside generation; a refuted verdict removes the step and its dependents and the model continues from the last kept step.],
) <fig-pipeline>

== Blocking or asynchronous <sec-sync>

Under blocking ("sync") the model waits for each verdict, so every step costs $L$ seconds of idle time. Under asynchronous checking it keeps writing; a verdict is applied when it arrives, usually one or two steps later, and only the final answer waits for outstanding verdicts (@fig-timeline). The cost of not waiting is that a refuted step may already have steps built on it, as in @fig-example.

#figure(
  box(inset: (left: 2.9cm, top: 0.2cm), width: 100%, height: 3.3cm, {
    lane(0, [*blocking*])
    seg(0, 0, 1.2, [S1], C-keep); seg(0, 1.2, 0.8, [wait], luma(225))
    seg(0, 2.0, 1.2, [S2], C-keep); seg(0, 3.2, 0.8, [wait], luma(225))
    seg(0, 4.0, 1.2, [S3], C-bad); seg(0, 5.2, 0.8, [wait ✗], luma(225))
    seg(0, 6.0, 1.2, [S3′], C-keep); seg(0, 7.2, 0.8, [wait], luma(225))
    seg(0, 8.0, 1.0, [answer], luma(200))
    lane(1.5, [*asynchronous*: model])
    lane(2.5, [checker])
    seg(1.5, 0, 1.2, [S1], C-keep); seg(1.5, 1.2, 1.2, [S2], C-keep); seg(1.5, 2.4, 1.2, [S3], C-bad)
    seg(1.5, 3.6, 1.2, [S4], C-keep); seg(1.5, 4.8, 1.2, [S3′ / S5], C-keep); seg(1.5, 6.0, 1.0, [answer], luma(200))
    seg(2.5, 1.2, 0.8, [check S1], luma(235)); seg(2.5, 2.4, 0.8, [check S2], luma(235))
    seg(2.5, 3.6, 0.8, [check S3 ✗], C-dep)
    place(dx: 4.4 * U, dy: 1.05cm, line(length: 1.7cm, angle: 90deg, stroke: (paint: red, thickness: 0.9pt, dash: "dashed")))
    place(dx: 4.4 * U + 3pt, dy: 2.55cm, text(7pt, fill: red)[refuted: truncate or mask])
  }),
  caption: [Blocking pays the checker's delay after every step. Asynchronous checking pays only when a step is refuted, and then only to rewrite the steps that have to go.],
) <fig-timeline>

== Truncation or masking <sec-policies>

When step $S_k$ is refuted, the steps to remove are $S_k$ and every later step whose `[uses]` chain leads back to it. *Truncation* deletes the cache from the start of $S_k$ onward, and the model rewrites everything after it, including later steps that never used $S_k$. *Masking* deletes only the entries of $S_k$ and its dependents, with llama.cpp's `kv_cache_seq_rm`, and the model continues after the last kept step (@fig-cache).#footnote[Masking sets the attention weight of the deleted positions to zero for every later token. The remaining entries keep their positions; llama.cpp tolerates a gap in the middle of the cache but not at its end, so a removal that reaches the end is done as a truncation.] Masking saves the rewriting. Its risk is that the kept steps' cache entries were computed while the deleted step was still visible, so they can carry its content #c(9, 10, 11); @sec-acc measures whether that matters. Under either policy, three refutations in a row make the harness back up to the last accepted step.

#figure(
  {
    set align(left)
    let row(label, cells, note) = (align(right + horizon, text(8pt, label)), ..cells, align(horizon, text(8pt, note)))
    grid(columns: (2.6cm,) + (1.15cm,) * 7 + (auto,), column-gutter: 2pt, row-gutter: 5pt,
      ..row([S3 refuted],(cell[P], cell[S1], cell[S2], cell([S3 ✗], fill: C-bad), cell[S4], cell([S5→S3], fill: C-dep), cell[S6]), []),
      ..row([*truncation*], (cell[P], cell[S1], cell[S2], gone[S3], gone[S4], gone[S5], gone[S6]), [rewrite from S3]),
      ..row([*masking*], (cell[P], cell[S1], cell[S2], gone[S3], cell[S4], gone[S5], cell[S6]), [continue at S7]),
    )
    v(0.3em)
    align(center, text(8pt)[#swatch(C-keep) kept #h(1em) #swatch(C-bad) refuted #h(1em) #swatch(C-dep) uses a refuted step #h(1em) #dashed-swatch deleted from the cache])
  },
  caption: [The two policies on the same cache. S5 declared `[uses S3]`, so it goes too; S4 and S6 are independent and survive masking.],
) <fig-cache>

== Loop cropping <sec-method-loops>

In every condition, including runs with no checker, the model sometimes repeats one formula step after step until it hits the step limit. The detector compares each new step's formula with the earlier live steps'; a repeat is deleted and replaced by a note, and after three repeats the model is made to answer (@fig-crop).

#figure(
  {
    set align(left)
    let row(label, cells, note) = (align(right + horizon, text(8pt, label)), ..cells, align(horizon, text(8pt, note)))
    grid(columns: (2.6cm,) + (1.15cm,) * 7 + (auto,), column-gutter: 2pt, row-gutter: 5pt,
      ..row([S5 repeats S3], (cell[P], cell[S1], cell[S2], cell[S3: φ], cell[S4], gone[S5: φ], cell([note], fill: luma(235))), [delete S5; three repeats → answer]),
    )
  },
  caption: [Loop cropping: a step whose formula repeats an earlier step's is deleted and noted.],
) <fig-crop>

== Simulating the delay <sec-clock>

The delay is simulated on a token clock. The 8B model wrote about 14 tokens per second on the reference machine (72.4 ms per token), so a verdict due $L$ seconds after a step arrives once the model has written another $14 L$ tokens. Time per problem is then computed from the transcript as

$ T = 8.6 "s" + 0.0724 "s" times "generated tokens" + "time waiting for verdicts," $

where 8.6 s is the measured fixed cost per problem (prompt, Z3). Under blocking the wait is $L$ per check; under asynchronous checking it is whatever is still outstanding at the answer. We call $T$ *modeled time*. Using one formula for every model keeps the policies comparable across models and machines; GPU wall time is also reported and moves the same way.

= Experimental setup <sec-setup>

*Benchmark.* ProverQA-Hard #c(1), the 500-problem hard split: 6 to 9 reasoning steps per problem, distractor premises, three labels. Always answering Uncertain scores about 40%. Problems are sampled with a fixed seed: 30 for the Qwen3-8B and the five later models, 100 for the Qwen3-14B and 30B. The loop-cropping run uses a 30-problem sample of which 28 are among the 100; its comparisons use those 28.

*Models.* Qwen3-8B, Qwen3-14B and Qwen3-30B-A3B (a mixture of experts with 3B parameters active per token), 4-bit quantized, run with llama.cpp in non-thinking mode, greedy decoding, temperature 0.7 after a rejection. The 8B ran on an Apple M4 laptop (24 GB); everything else on a Colab L4 GPU (24 GB), about 18 GPU-hours in all. A later sweep added Qwen3-4B, Llama 3.1 8B, Phi-4 (14B), Mistral Small 24B and the dense Qwen3-32B, same quantization and harness with each model's own chat template, on a Colab A100 for 3.3 GPU-hours (@fig-acc6, @fig-maskgain).

*Conditions.* `sync`: blocking. `trunc`, `mask`: asynchronous with the named policy, at $L in {1, 3, 8}$ s. The loop-cropping run repeats `trunc` and `mask` on the 14B at $L$ = 8 s with the detector on.#footnote[That run also let the final answer wait only for the verdicts of the steps it depends on. On problems where nothing was cropped this changed nothing: transcripts and times are identical. On the cropped problems it saved about one second of waiting, which is included in the reported total.]

*Metrics.* Accuracy; generated tokens per problem; modeled time (@sec-clock); L4 wall time.

*Statistics.* Every comparison is between two runs on the same problems. For each problem we record which run was faster (for accuracy, which run alone was right). If the runs were equivalent each problem would be a coin flip, so a split such as 25 faster against 11 slower is unlikely by chance: the probability of a split at least that uneven, $p$, is 0.03. We report the split as wins/losses with $p$ from the two-sided exact sign test (McNemar's test for accuracy) and call $p < 0.05$ significant. With 30 problems the smallest significant split is 6 to 0, so the 30-problem runs can show the speed effects, which are large, but could miss an accuracy change of a few problems.

= Results <sec-results>

The figures below show the comparisons that were significant. Every comparison not mentioned was not: the checked policies' accuracies differ by at most a few problems on every model at every delay ($p >= 0.06$), and the checked pipeline is not significantly different from the same step format with no checker ($p >= 0.11$). The full tables are in the companion report.

== Accuracy: the format or the checker helps, by family; masking hurts one model <sec-acc>

#figure(
  barchart(
    (([8B ($n$ = 30)], (46.7, 56.7, 53.3, 63.3, 36.7)), ([14B ($n$ = 100)], (58, 66, 65, 70, 71)), ([30B-A3B ($n$ = 100)], (57, 67, 73, 73, 71))),
    ([plain chain-of-thought], [step format, unchecked], [checked, blocking], [checked, async, truncation], [checked, async, masking]),
    (luma(200), rgb("#9dbbe0"), C-sync, C-trunc, C-mask),
    ymax: 100, step: 20, w: 14cm, h: 3.6cm, unit: "%", ylabel: [problems answered correctly],
  ),
  caption: [Accuracy; the checked conditions use the 8-second checker. Two differences are significant: the step format over plain chain-of-thought (pooled across the three models, 55 wins / 34 losses, $p$ = 0.03), and masking against truncation on the 8B (0 wins / 8 losses, $p$ = 0.008). At 1 and 3 s the checked bars are within 3 points of these, except 8B masking (60.0 and 53.3, not significant).],
) <fig-acc>

#figure(
  barchart(
    (([Qwen3-4B], (30.0, 50.0, 63.3, 63.3, 56.7)), ([Llama 3.1 8B], (33.3, 33.3, 46.7, 43.3, 40.0)), ([Phi-4 14B], (43.3, 50.0, 66.7, 66.7, 73.3)),
     ([Mistral Small 24B], (56.7, 56.7, 73.3, 76.7, 73.3)), ([Qwen3-32B], (43.3, 63.3, 70.0, 70.0, 70.0))),
    ([plain chain-of-thought], [step format, unchecked], [checked, blocking], [checked, async, truncation], [checked, async, masking]),
    (luma(200), rgb("#9dbbe0"), C-sync, C-trunc, C-mask),
    ymax: 100, step: 20, w: 14cm, h: 3.6cm, unit: "%", ylabel: [problems answered correctly],
  ),
  caption: [Accuracy on the five later models, 30 problems each, checked conditions at 8 s. On the two Qwen sizes the step format carries the gain (pooled 19/7 over plain chain-of-thought, $p$ = 0.03) and the checker adds nothing significant. On the three other families the format alone does nothing (18/16) and the checker carries the gain instead (blocking checker over unchecked format, pooled 17/3, $p$ = 0.003; async policies at 8 s, 22/8, $p$ = 0.02).],
) <fig-acc6>

Two things in @fig-acc are significant. First, the step format alone, with no checker, raises accuracy over ProverQA's own chain-of-thought prompt by 10, 8 and 10 points on the three models (6/3, 25/17 and 24/14 wins/losses; pooled 55/34, $p$ = 0.03; on the 30B with the step cap removed, 27/13, $p$ = 0.04). The prompt also shows the formula of every premise, which may account for part of this. Adding the checker to the format changes nothing: the checked policies get the same problems right as the unchecked format and as each other. Second, the one exception among the checked policies: masking on the 8B with the 8-second checker loses 8 problems to truncation and wins none. That model does not recover from a span cut out of the middle of its context; the seven others do (@sec-mask).

The five later models (@fig-acc6) split the first finding by family. The two new Qwen3 sizes repeat the Qwen pattern: the format alone gains 20 points on both (pooled 19/7, $p$ = 0.03) and the checker adds nothing significant. Llama 3.1 8B, Phi-4 and Mistral Small 24B do the opposite: the format alone gains nothing (18/16 pooled), and the checker on top of it gains 14 to 24 points (blocking checker over unchecked format 6/2, 6/1 and 5/0; pooled 17/3, $p$ = 0.003; the asynchronous policies keep most of it, 22/8 at 8 s). Where the checker helps, it helps on problems where it refuted something: of the 22 problems those three models get right only with the checker, 17 had at least one refuted step. Thirty problems per model is too few to rank the five, so the claim is the pooled one: every family ends up ahead of plain chain-of-thought (masking at 8 s over plain, pooled across the five, 49/17, $p$ < 0.001), and a model that already follows the step format well has little left for the checker to fix. Everything below is cost at equal accuracy.

== Asynchronous checking against blocking <sec-async>

#figure(
  grid(columns: 3, column-gutter: 0.4cm,
    linechart([8B ($n$ = 30)], (40.3, 58.0, 102.2), (34.6, 39.0, 51.7), (34.4, 34.8, 43.8), ymax: 120, step: 40),
    linechart([14B], (51.8, 74.4, 130.9), (46.4, 50.6, 62.2), (45.6, 49.0, 55.8), ymax: 150),
    linechart([30B-A3B], (74.7, 107.8, 190.4), (61.0, 63.6, 69.5), (58.7, 59.8, 63.3), ymax: 200),
  ) + align(center, text(8pt)[#swatch(C-sync) blocking #box(width: 1.2em) #swatch(C-trunc) asynchronous, truncation #box(width: 1.2em) #swatch(C-mask) asynchronous, masking]),
  caption: [Modeled seconds per problem against the checker's delay. Every asynchronous point is below the blocking point above it at $p$ < 0.001.],
) <fig-time>

Not waiting is faster on every model at every delay: faster on 27 to 29 of 30 problems on the 8B and on 77 to 99 of 100 on the 14B and 30B. The saving grows with the delay, from 12 to 21% at 1 s to 49 to 67% at 8 s, because blocking pays the delay after every step while asynchronous checking pays only to rewrite refuted steps.

== Masking against truncation <sec-mask>

#figure(
  {
    let labels = ([Qwen3-8B #text(fill: luma(120))[$n$ = 30]], [Llama 3.1 8B #text(fill: luma(120))[$n$ = 30]], [Qwen3-14B #text(fill: luma(120))[$n$ = 100]], [Phi-4 14B #text(fill: luma(120))[$n$ = 30]], [Mistral Small 24B #text(fill: luma(120))[$n$ = 30]], [Qwen3-30B-A3B #text(fill: luma(120))[$n$ = 100]], [Qwen3-32B #text(fill: luma(120))[$n$ = 30]], [Qwen3-4B #text(fill: luma(120))[$n$ = 30]])
    let time = (((0.6, 1.000), (10.8, 0.180), (15.2, 0.146)),
      ((1.9, 1.000), (4.1, 0.227), (11.8, 0.302)),
      ((1.8, 0.180), (3.1, 0.230), (10.4, 0.003)),
      ((4.6, 0.227), (4.3, 0.388), (13.3, 0.096)),
      ((5.8, 0.453), (7.6, 0.508), (8.1, 1.000)),
      ((3.8, 0.043), (5.9, 0.035), (8.9, 0.029)),
      ((1.6, 0.250), (3.7, 0.062), (0.9, 1.000)),
      ((-1.5, 0.344), (1.8, 0.302), (19.7, 0.454)))
    let acc = (((-3.3, 1.000), (-10.0, 0.250), (-26.7, 0.008)),
      ((0.0, 1.000), (3.3, 1.000), (-3.3, 1.000)),
      ((0.0, 1.000), (1.0, 1.000), (1.0, 1.000)),
      ((10.0, 0.250), (10.0, 0.375), (6.7, 0.727)),
      ((0.0, 1.000), (-3.3, 1.000), (-3.3, 1.000)),
      ((2.0, 0.625), (-1.0, 1.000), (-2.0, 0.754)),
      ((-3.3, 1.000), (-3.3, 1.000), (0.0, 1.000)),
      ((3.3, 1.000), (3.3, 1.000), (-6.7, 0.625)))
    align(center, heat(labels, time, acc))
    v(0.3em)
    align(center, text(8pt)[columns: checker delay #h(1.2em) colour depth = significance ($p$ in each cell), scaled to each block's strongest cell #h(1.2em) *bold* = $p$ < 0.05 #h(1.2em) rows by parameter count])
  },
  kind: image,
  caption: [Masking against truncation, per model and checker delay: time saved (left) and the change in accuracy (right). Time saved grows with the delay on every model but the Qwen3-32B, which has little to keep: a mask salvages 9 tokens per problem there against 30 to 89 on the other models. Accuracy is unchanged on every model but the Qwen3-8B, where the loss grows with the delay. The savings are significant on the Qwen3-30B at every delay and on the 14B at 8 s ($n$ = 100); the 30-problem runs cannot confirm savings of this size.],
) <fig-maskgain>

With asynchronous checking in place, masking saves a further 4 to 10% of time on the Qwen3-14B and 30B, and the saving grows with the delay because a later verdict leaves more independent work to keep (@fig-maskgain). On the Qwen3-8B, and on the 14B at 1 and 3 s, the two policies are not distinguishable on time. The accuracy cost of masking is −27 points on the Qwen3-8B at 8 s and within ±7 points everywhere else, including the smaller Qwen3-4B (−6.7, 1 win, 3 losses) and an 8B of another family (Llama 3.1, −3.3, 2 wins, 3 losses). So the failure is not a matter of parameter count. For the 30-problem rows, that sample is enough to rule out a collapse like the Qwen3-8B's but not to confirm a 5 to 13% time saving, so those cells are not bold.

== Loop cropping <sec-loops>

#figure(
  barchart(
    (([truncation], (862, 574, 481)), ([masking], (896, 645, 382))),
    ([looping problems, without cropping], [looping problems, with cropping], [other problems, with or without]),
    (luma(170), C-trunc, rgb("#9dbbe0")),
    ymax: 1000, step: 200, w: 10cm, h: 3.2cm, ylabel: [generated tokens per problem],
  ),
  caption: [Generated tokens per problem on the 14B at $L$ = 8 s, split by whether the detector fired (12 of 28 problems under truncation, 13 under masking). On the other problems the transcripts are identical with and without cropping.],
) <fig-loops>

Cropping repeated steps saves 16% of modeled time and 19% of generated tokens under both policies (truncation 62.1 → 52.1 s, masking 60.3 → 51.5 s), faster on 11 of 12 and 12 of 13 differing problems ($p$ = 0.01 and 0.003). Answers did not change (1 win, 1 loss per policy), so the cropped tokens were waste.

= Where this applies <sec-uses>

The savings apply wherever a verifier is slower than generation and can run beside it: an autoformalizer that turns each step into logic before an SMT check, a proof assistant such as Lean, unit tests run on each generated function, a tool or API call whose result confirms or refutes a step, or a second model acting as a critic. In each case asynchronous checking lets generation continue and charges only for refuted steps. Dependency-scoped removal keeps the work that did not depend on the refuted step, which pays once the model is 14B or larger and the verifier is slow; below that, truncation. Loop cropping applies to any step-structured output. The pipeline needs two things from the task: steps that can be checked one at a time, and a dependency list the model can be trusted to write. We tested only the Z3 case; the others share its structure but were not measured here.

= Limitations <sec-limits>

- The delay is simulated. A real slow checker, such as a translation model sharing the GPU, would also slow generation itself.
- One benchmark, with gold premise formulas: the checker verifies only the formulas the model writes for its steps.
- The Qwen3-8B, the five later models and the loop-cropping run use 30 problems, enough for the speed effects and for a collapse but not for a small accuracy change or a 5 to 15% masking saving. The 14B and 30B main results use 100.
- The dependency lists are the model's own and were not verified independently here.
- All models are 4-bit quantized, with one decoding setting and one seed.

= Conclusion <sec-conc>

Three changes make a prover-checked reasoning pipeline cheaper at the same accuracy: asynchronous checking (12 to 67% faster than blocking, on every model and delay), masking a refuted step's dependents instead of truncating (4 to 10% faster on the 14B and 30B with a slow checker, harmful on the Qwen3-8B only among eight models), and cropping repeated steps (16% faster on the 14B). The checked pipeline beat plain chain-of-thought on every model; on Qwen3 the step format did the work, on three other families the checker did. Next: replace the simulated delay with a real slow checker and repeat the comparison on at least 100 problems; make masking safe for small models by letting each step attend only to the prompt and the steps it declares, which removes the leakage described in @sec-policies by construction; and, since the checker's accuracy gain on the non-Qwen families rests on 30 problems per model, repeat that comparison on a few hundred.

#v(0.6em)
#line(length: 100%, stroke: 0.4pt)
#text(8.5pt)[*Artifacts.* Harness: `run.py`, `logic.py`, `analyze.py`, `analyze_eff5.py`; cloud driver: `cloud/colab.sh`, `cloud/vm.sh`; raw runs: `results/v2/` (8B), `results_cloud/Qwen3-14B/`, `results_cloud/Qwen3-30B-A3B/`, `results_cloud/Qwen3-14B_eff/`, `results_cloud/{Qwen3-4B,Llama-3.1-8B,Phi-4,Mistral-Small-24B,Qwen3-32B}/` (`analyze_r6.py`); every experiment including the null results and full tables: `results/RESULTS.md`, `results/paper_full.pdf`.]

= References

#set text(size: 8.5pt)
#set par(justify: false)
#set enum(numbering: "[1]", spacing: 0.35em)
+ C. Qi, R. Ma, B. Li, H. Du, B. Hui, J. Wu, Y. Laili and C. He. _Large Language Models Meet Symbolic Provers for Logical Reasoning Evaluation_ (ProverQA). ICLR 2025. arXiv:2502.06563.
+ Y. Feng, N. Weir, K. Bostrom, S. Bayless, D. Cassel, S. Chaudhary, B. Kiesl-Reiter and H. Rangwala. _VeriCoT: Neuro-symbolic Chain-of-Thought Validation via Logical Consistency Checks._ arXiv:2511.04662, 2025.
+ J. Hu, S. Yang, W. Liu and D. Wang. _LogicTrack: Auditing Reasoning Trajectories of Large Language Models with Formal Logic Solvers._ arXiv:2609.21492, 2026.
+ C. Liu et al. _Safe: Enhancing Mathematical Reasoning in Large Language Models via Retrospective Step-aware Formal Verification._ ACL 2025. arXiv:2506.04592.
+ S. Mukherjee, A. Chinta, T. Kim, T. A. Sharma and D. Hakkani-Tür. _Premise-Augmented Reasoning Chains Improve Error Identification in Math Reasoning with LLMs_ (PARC). ICML 2025. arXiv:2502.02362.
+ T. Jin. _Self-Orchestrating Language Models: Leveraging Semantic Dependence for Efficient Inference_ (chapter 4, "Thinking in Place"). arXiv:2609.14850, 2026.
+ D. Choi et al. _Think Clearly: Improving Reasoning via Redundant Token Pruning._ arXiv:2507.08806, 2025.
+ B. Feng et al. _StepKV: Step-Aware KV Cache Compression for LLM Agents._ arXiv:2609.22158, 2026.
+ C. Zhou et al. _Positions Are Not Facts: The Mismatch Between KV Caches and Memory._ arXiv:2609.33759, 2026.
+ G. Zhang and H. Yang. _Aborted but Not Forgotten: KV-Cache Retention Breaks Rollback Consistency in Language Agents._ arXiv:2608.15939, 2026.
+ M. Li et al. _KVEraser: Learning to Steer KV Cache for Efficient Localized Context Erasing._ ICML 2026 Workshop on the Impact of Memorization on Trustworthy Foundation Models. arXiv:2606.17034.
+ J. Doyle. _A Truth Maintenance System._ Artificial Intelligence 12(3), 1979. doi:10.1016/0004-3702(79)90008-0.
+ A. Gupta, I. S. Mumick and V. S. Subrahmanian. _Maintaining Views Incrementally._ SIGMOD 1993. doi:10.1145/170035.170066.
