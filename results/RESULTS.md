# First results: solver-checked reasoning with KV-cache invalidation

> **Correction (2026-10-16, round 2 below):**
> - Every round-1 condition that had a checker contains a harness artifact. The model copied the checker note instead of writing a step, the copy had no formula, so it was rejected, which appended another note.
> - In `lag_trunc` this loop was ~930 of 1074 generated tokens per problem.
> - So round-1 finding 3 is confounded: "masking uses 47% fewer tokens than truncation" came mostly from this loop.
> - The round-1 checked conditions also answered "uncertain" (C) far more often.
> - Round 2 fixes the loop and re-measures. **Use the round-2 v2 numbers for any systems claim.**
> - Round-1 numbers for `base` and `fmt` are unaffected, since they have no checker.

2026-10-15 · n=30 ProverQA-Hard · Qwen3-8B Q4_K_M via llama.cpp (Metal, M4 24 GB), non-thinking, greedy (temp 0.7 after a rejection) · Z3 5.3
Raw data: `results/*.jsonl` · tables: `python run.py --summary`, `python analyze.py`

## Setup

- **Problems:** 30 random ProverQA-Hard dev items (seed 0). Items 411 and 473 are excluded because Z3 on their gold logic disagrees with the gold label.
- **Gold answers:** A=9, B=9, C=12. Always answering "C" scores 40%.
- **How steps are checked:**
  - The model writes `Step k [uses P#, S#]: <fact>` followed by `FOL: <formula>`.
  - Z3 checks whether the gold premise formulas entail the step's formula.
  - A step must be a fact: one or more possibly negated predicates joined by ∧. Rules and disjunctions are rejected as "not a fact", because they can restate a premise and pass vacuously.
- **The checked conditions (C, D, lag_trunc, lag_refresh) share three rules:**
  - every rejection appends a one-line checker note (LogicTrack regenerates with feedback);
  - at most 8 rejections per problem;
  - a forced answer is the most likely of A/B/C.

| Condition | What it does |
|---|---|
| A `base` | ProverQA's own 2-shot chain-of-thought prompt (opendatalab/ProverGen), no tools |
| B `fmt` | Step format with logic formulas, no checker |
| C `sync` | Checks each step right away; rejection → regenerate (≤2 times), then force the best candidate forward (LogicTrack policy) |
| `lag_trunc` | Checking runs 2 steps behind; rejection → cut the cache back to the rejected step |
| **D `lag_mask`** | Checking runs 2 steps behind; rejection → remove the step and its dependent steps from the cache (`seq_rm`, the same as -inf attention for future tokens); keep the independent later steps; 3 rejections in a row → back up to the last accepted step |
| `lag_refresh` | D, plus recomputing the cache entries of the kept later steps (exact rollback, DRed-style) |

## Results

| Condition | Accuracy | Tokens generated per problem | Thrown away | Kept after rejections | Recomputed | Rejections per problem | Wrong prunes* | Forced answers | Seconds per problem | Leakage TV** |
|---|---|---|---|---|---|---|---|---|---|---|
| A base | 46.7 | 265 | – | – | – | – | – | 0 | 36.5 | – |
| B fmt | **56.7** | 351 | – | – | – | – | – | 3 | 44.7 | – |
| C sync | **56.7** | 398 | 278 | – | 52 | 4.47 | 6 | 10 | 47.5 | – |
| lag_trunc | 50.0 | 1074 | 1081 | – | – | 4.13 | 5 | 16 | 85.0 | 0.0004 |
| **D lag_mask** | 53.3 | **573** | 494 | 287 | 0 | 3.40 | 6 | 12 | **51.2** | 0.040 (max 0.49) |
| lag_refresh | 50.0 | 683 | 677 | 406 | 488 | 4.07 | 6 | 12 | 62.3 | 0.0010 |

\* Wrong prunes: rejected steps whose English claim matches a context sentence or gold conclusion. This is a fuzzy-match estimate.
\** Leakage TV: total-variation distance between p(A/B/C) from the live cache and from a clean re-prefill of the visible transcript, at answer time. lag_mask is reported over the 25 problems where kept cache entries had seen a masked step; the other two over all 30. lag_trunc and lag_refresh are exact by construction, so their values (≤0.001) are the measurement's noise floor.

Paired exact McNemar tests on accuracy found no significant difference:

| Comparison | Wins / losses | p |
|---|---|---|
| fmt vs base | 6 / 3 | 0.51 |
| sync vs fmt | 6 / 6 | 1.0 |
| lag_mask vs sync | 2 / 3 | 1.0 |
| lag_mask vs lag_trunc | 1 / 0 | 1.0 |

## Findings

1. **Checking did not improve accuracy.**
   - The step format alone gained 10 points over the baseline (not significant). Its prompt also shows the logic formula for every premise, which may account for much of that.
   - Adding the Z3 check (C) gained nothing over the format (B): both scored 56.7%.
2. **The checker mostly catches translation errors, not reasoning errors.**
   - In C, 78 of 134 rejections (58%) were format failures: 61 non-fact formulas and 17 missing or unparseable ones.
   - About 6 correct steps per run were pruned.
   - This matches the literature: VeriCoT verified only 45% of chains, and FaithformBench found 21% of broken steps translated into provable statements.
   - **Translation into logic is the bottleneck** (the proposal's open problem 2).
3. **With checking running behind generation, masking dependent steps clearly beats truncating.** This is the systems result.
   - lag_mask against lag_trunc, at the same lag, budget and feedback: **47% fewer generated tokens and 40% less wall time**, with equal or better accuracy.
   - Problem by problem, masking was cheaper on 20, tied on 6 and more expensive on 4 (sign test p ≈ 0.002).
   - On average 287 tokens per problem were kept instead of regenerated.
4. **When checking is free, checking immediately is still cheapest.**
   - C (398 tokens, 47.5 s) beats D (573 tokens, 51.2 s).
   - In this setup the model writes each step's formula inline and Z3 answers in milliseconds, so running behind buys nothing.
   - **The proposal's efficiency claim holds only where checking has real latency** (a separate translation pass, a heavier solver, or checking off the critical path).
5. **Masking alone is not exact, but it is close.**
   - Mean leakage was 0.04, against a noise floor of 0.0004–0.001. The maximum was 0.49, with 1 answer flip in 25 problems.
   - **In both large-leakage cases (258 and 425), the masked cache gave the *correct* answer and a clean rerun drifted away from it.** The trace of the refuted step helped, consistent with open problem 1 ("useful mistakes"). With n=2 this is anecdotal.
   - Recomputing the kept steps makes it exact for 22% more time. It gave no accuracy gain here (50.0 vs 53.3, 0 wins and 1 loss).
6. **Kill test (from B's unchecked steps): conditions met.**
   - 28% of steps are reasoning errors (62 refuted, 15 not entailed).
   - 24 of 30 problems contain at least one.
   - After the first error, 60% of later steps are independent of it, according to the model's own `[uses]` links.

## Caveats

- **Sample size and scope:** n=30, one model (4-bit), one benchmark, one seed. Every accuracy difference is within noise.
- **The verifier uses the gold premise formulas,** which is an upper bound on how well premises are translated. Only step conclusions are translated by the model.
- **The dependency graph is self-declared** through `[uses]` and was not validated. Under-declaration is likely: PARC found 7B models list only about 64% of the premises they use. Missed links mean masking keeps steps it should have removed.
- **"Wrong prunes" is a fuzzy-match estimate** against gold sentences.
- **The lag is simulated,** since Z3 latency is about 0 here. Seconds per problem include prompt prefill and Z3 time.
- **The leakage probe only measures the final answer distribution.** The clean re-prefill also removes the position gaps left by masking.
- **Policies were fixed before the n=30 run, after a 3-problem smoke test:** feedback notes, budgets, back-ups, and the fact-only rule. They were not tuned on these results.
- **"Uncertain" problems trigger rejection loops.** The model keeps trying to prove an unprovable goal, which drives most forced answers.

## Verdict and next steps

- **The mechanism works, and it is the right tool for one regime: checking that lags behind generation.** There it saves about half the compute of truncation, at near-identical behaviour.
- **It does not improve accuracy, and it loses to immediate checking when checking is free.** The paper is a *systems* paper about verification latency, not an accuracy paper.

Highest-value next experiments:

1. **Latency sweep (the core systems plot).** Add real or simulated checker latency (0, 0.5, 1, 2 s per step) and measure end-to-end time for sync, lag_trunc and lag_mask, with decoding continuing while checking runs. Prediction: sync time grows linearly with latency, while lag_mask stays nearly flat.
2. **Remove format failures with constrained decoding.** A llama.cpp GBNF grammar can restrict the FOL line to ∧-joined literals over the problem's own predicates and constants. Expect most of the 58% format rejections to disappear; then re-measure accuracy.
3. **Check the dependency graph.** Use Z3 unsat cores to find which premises and steps each accepted step actually needs, measure how much the model under-declares, and test masking with the inferred graph.
4. **Scale up:** n=100+, plus `llama3.1:8b` as a second model family.
5. **Test the "useful mistakes" lead:** compare lag_mask against lag_refresh, and with and without checker notes, at larger n.

---

# Round 2 (2026-10-16): checker-latency sweep, constrained formulas, and harness fixes

Same 30 problems, model, prompt and seeds as round 1. Tables: `python analyze.py [dir]`. Raw data in `results/<dir>/*.jsonl`. Log: `results/run3.log`.

## What changed, and why

| Change | Env var | Why |
|---|---|---|
| **Token clock** for checker latency | `LATENCY=<s>` | A verdict arrives L seconds after its step is submitted, and decoding continues meanwhile. Time is measured as decoded tokens × 72.4 ms (round-1 idle speed) plus waits. Laptop load varied 6–13 tok/s during the night, and with wall-clock latency a slower machine also shrinks the effective lag. **Validated against a real-time run** (`realtime_lat3/`): 47.4 vs 47.8 s per problem modeled, 522 vs 523 tokens, same answer on 29/30. |
| **Reject only refuted steps** | `MASK_ON=refuted` | Round-1 masking fired on any step Z3 couldn't prove: only ~27% of masks were real refutations, ~65% were malformed formulas. "A safe prune needs a refutation" was the round-1 verdict. Unverifiable steps now stay visible as *kept*. In v2 this also applies to `sync`, so all three conditions use the same rule. |
| **Format guard** | `GUARD=1` | Fixes the copied-note loop (see the correction above). A chunk starting with neither "Step" nor "Answer" is cut after a few characters, cropped, and regenerated with "Step" forced. Its tokens count as generated and wasted. After the fix it fires for ~1 token per problem. |
| **Grammar-constrained formulas** | `GRAMMAR=1` | GBNF: 1–3 (¬)pred(const) literals joined by ∧, using only the problem's own symbols. First version had a **token-boundary bug**: the forced prefix `FOL: ` split Qwen's ` ¬` token, and the model dropped or added ¬ at random. Fixed by forcing `FOL:` and letting the grammar generate the space. The buggy partial run is kept in `grammar_bug_tokenboundary/`, marked invalid. |
| **Checker-note wording** | `NOTE=specific` | Note says "the premises prove it false" instead of "it does not follow from the premises" (see finding 3). |

Sync is not re-run per latency. Its tokens don't depend on L, so its time at L is its modeled time + (number of checks × L), which is exact.

## Results

### 1. Accuracy: the checker does not help, even with well-formed formulas

| Condition | Accuracy | Tokens per problem | Forced answers | Answers A/B/C |
|---|---|---|---|---|
| base (round 1) | 46.7 | 265 | 0 | – |
| fmt (round 1) | 56.7 | 351 | 3 | 12/10/8 |
| fmt + grammar | 56.7 | 282 | 1 | – |
| sync + grammar (pre-guard) | 53.3 | 377 | 13 | – |
| **v2 sync** (guard, refute-only) | 53.3 | 316 | 4 | 10/8/12 |
| **v2 lag_mask, L=3** | 53.3 | 337 | 3 | 9/7/14 |
| **v2 lag_trunc, L=3** | **63.3** | 396 | 6 | – |

- **The grammar removes malformed formulas but moves the errors rather than fixing them.**
  - Unchecked steps contained 0 malformed formulas, but 100/253 refuted, against 62/278 without the grammar.
  - Claims that are not plain facts ("either A or B") get forced into a single false fact.
  - With the grammar, the checker fixed 7 problems and broke 8 relative to fmt + grammar.
  - The model also games entailment-only checking by restating proven formulas: 28% of accepted steps in sync + grammar.
- **No checked condition beats fmt significantly.**
  - v2 sync vs fmt: 2 wins / 3 losses.
  - v2 lag_trunc vs fmt: 3 / 1 (p=0.62).
  - lag_trunc's 63.3% is the best checked result, but at n=30 it is not significant.

### 2. Systems: the win comes from checking asynchronously; masking adds little and costs accuracy at high latency

v2, n=30, modeled seconds per problem at idle-machine speed:

| Checker latency L | sync | lag_mask | lag_trunc | mask vs sync (per-problem W/L) | mask vs trunc (per-problem tokens W/L) |
|---|---|---|---|---|---|
| 1 s | 40.3 | 34.4 | 34.6 | 26/4, p<0.0001 | 4/3, p=1.0 |
| 3 s | 58.0 | **34.8** | 39.0 | 28/2, p<0.0001 | 7/2, p=0.18 (21 ties: nothing refuted) |
| 8 s | 102.2 | **43.8** | 51.7 | 29/1, p<0.0001 | 9/3, p=0.15 |

lag_trunc is also faster than sync on 27/30, 28/30 and 29/30 problems at L=1, 3 and 8.

- **Checking asynchronously beats blocking on the checker, at every latency tested.**
  - sync's cost grows ~8.8 s per problem for every second of checker latency (one wait per check, 8.8 checks per problem).
  - lag_trunc grows ~2.4 s per second (34.6 → 51.7 s from L=1 to L=8).
  - lag_trunc vs sync: 14% faster at L=1, 33% at L=3, 49% at L=8.
- **Masking dependents instead of truncating saves little:** 0% at L=1, 11% at L=3, 15% at L=8. It is never significant per problem, because on most problems nothing is refuted and the two runs are identical.
- **But masking loses accuracy as the checker gets slower, and truncation does not.** This is the one statistically significant accuracy result in this study.

  | Accuracy | L=1 | L=3 | L=8 |
  |---|---|---|---|
  | lag_mask | 60.0 | 53.3 | **36.7** |
  | lag_trunc | 63.3 | 63.3 | **63.3** (the identical 19 problems right at all three L) |
  | mask vs trunc, W/L | 0/1 | 0/3 | **0/8, p=0.008** |

  - At L=8, truncation beats masking on all 8 problems where they disagree (exact McNemar **p=0.008**). Masking's cost saving at L=8 is only 15% (43.8 vs 51.7 s) and not significant per problem.
  - Mechanism: with a later verdict, more later steps are written while the refuted step is still visible. Masking keeps the independent ones (19 kept at L=3 → 60 at L=8), but their cache entries already attended to the refuted step. Leakage TV, averaged over problems where a kept step had seen a masked one, rises 0.013 → 0.069.
  - Some "independent" steps may also have used the refuted fact without declaring it in `[uses]`.
  - **Exact rollback recovers most, not all, of the loss.** `lag_refresh` at L=8 masks and then recomputes the kept steps' cache entries.

    | L=8 | lag_mask | lag_refresh | lag_trunc |
    |---|---|---|---|
    | Accuracy | 36.7 | **53.3** | 63.3 |
    | Leakage TV (mean over all 30) | 0.030 | 0.0007 | 0.0004 |
    | Modeled s/problem | 43.8 | 46.0 (+~0.3 s recompute of ~95 tok) | 51.7 |

    - refresh vs mask: 5 wins / 0 losses (p=0.06). So stale cache entries explain ~5 of the 8 problems masking lost.
    - refresh vs trunc: 0 / 3 (p=0.25). The rest is *content* leakage: kept steps written while the refuted step was visible, which plausibly relied on it without declaring it. Recomputing the cache cannot fix that.
  - **Answer to the proposal's open problem 3, "when is it safe to prune a reasoning branch?"** Masking a refuted branch while keeping later steps is safe only if all three hold:
    - the step is refuted, not merely unverified;
    - the kept steps are recomputed;
    - the kept steps truly did not depend on it.
  - Self-declared `[uses]` does not guarantee the third. Truncation satisfies all three by construction, at ~11% more time than mask + refresh at L=8.
- **Masking's leakage on the final answer is small at low latency:** TV 0.021 at L=1, 0.013 at L=3 (averaged over problems where a kept step had seen a masked one; 0.005 / 0.011 over all 30), against a truncation noise floor of 0.0004. It is not small at L=8 (0.069; 0.030 over all 30), and even small TV coexists with lost problems, because the damage happens in what is *generated* after the mask, not only in the final-answer distribution.

### 3. The checker biased answers toward "uncertain" (pre-guard runs)

| Condition | Answers A/B/C | Correct on gold A | Correct on gold C |
|---|---|---|---|
| fmt (no checker) | 12/10/8 | 7/9 | 4/12 |
| sync, round 1 | 3/8/19 | 2/9 | 9/12 |
| lag_mask, round 1 (mask any non-entailed step) | 2/4/24 | 1/9 | 11/12 |
| lag_mask, refute-only (no guard) | 8/7/15 | 3/9 | 6/12 |
| v2 sync | 10/8/12 | – | – |

- Round-1 checked accuracies (~53%) were propped up by answering C, the majority class (40%).
- Three causes, all reduced in v2:
  - rejecting unverifiable steps;
  - the copied-note loop;
  - a note that reads like the definition of "uncertain" ("does not follow from the premises… write the Answer line if nothing more can be derived").
- **The wording test rules out the note text as the cause** (`v2/note_lat3`, lag_mask at L=3 under v2, with only the note changed):
  - The "the premises prove it false" note still gave **14/30 C answers**, the same as the generic note.
  - It scored 46.7% vs 53.3% (0 wins / 2 losses, p=0.5) and used 36% more tokens (457 vs 337). Forced answers rose from 3 to 8, because the model keeps working after a "false" verdict instead of moving on.
  - So the residual lean toward C under v2 masking (14 C answers vs fmt's 8) comes from the checking itself, not from the note's wording. The generic note stays.

### 4. Masking policy (pre-guard, L=3, token clock)

| Policy | Masks per problem | Tokens per problem | Seconds per problem | Forced answers | Leakage TV (stale cases) | Accuracy |
|---|---|---|---|---|---|---|
| Mask any non-entailed step | 3.8 | 523 | 47.8 | 13 | 0.061 (2 flips) | 53.3 |
| Mask only refuted steps | 1.0 | 375 | 37.8 | 1 | 0.010 (0 flips) | 50.0 |

Refute-only is 28% cheaper, nearly exact, and nearly never forces an answer, with no accuracy change. It is the default from v2 on.

### 5. Why lag_mask and lag_trunc disagree (v2, L=3)

They disagree on 3 problems (433, 388, 207), all in truncation's favor. Traces of 433 and 388 show divergence after a rejection, not leakage:

- **433: the visible transcript is identical at the moment of rejection.** Only the masked position gap differs. The run is sampling at temperature 0.7 after a rejection, so the gap tips the next token: mask answered C at once, while trunc kept deriving and reached A.
- **388: truncation got lucky.** It regenerated the same refuted step 6 times, never got past step 1, and its forced answer happened to be correct. Masking kept the independent steps 2–3, derived further, and answered A (wrong). Because the masked step is invisible, it also restated the refuted claim once.

## Caveats (in addition to round 1's)

- n=30, one model, one benchmark. Every accuracy difference above is within noise.
- **Checker latency is simulated** on a token clock with a parallel checker pool. A real LLM-based autoformalizer would share the GPU.
- **Policies changed during round 2,** each in response to a measured failure: token clock, refute-only, guard, grammar fix. Only the v2 runs share one fixed policy, and they were not tuned on their own results.
- The dependency graph is still self-declared through `[uses]`.

## Verdict after round 2

- **Accuracy: don't pitch it.** At 8B on ProverQA-Hard, a step-level Z3 checker does not improve accuracy, with or without constrained formulas.
  - The best checked condition (lag_trunc, 63.3%) vs fmt: 3 wins / 1 loss, p=0.62.
  - What the checker mostly catches are translation errors: malformed formulas, or facts forced from non-fact claims.
  - Its feedback biases the model toward "uncertain".
- **Systems: the robust result is asynchronous checking with truncation on refutation.**
  - Saves 14 / 33 / 49% vs blocking (sync) at L = 1 / 3 / 8 s; faster on 27–29 of 30 problems at every L.
  - Gets the identical set of problems right at every latency.
  - It is simple and exact by construction.
- **In-place masking of dependent steps (the proposal's novel mechanism) is not worth it as is.**
  - It saves at most 15% over truncation, never significantly.
  - It loses accuracy as checker latency grows (36.7% vs 63.3% at L=8, p=0.008).
  - Recomputing the kept steps (`lag_refresh`) recovers 5 of those 8 problems.
  - The rest is content leakage through steps that undeclared-ly relied on the refuted one.
- **Answer to open problem 3, "when is it safe to prune?"** Only when all three hold:
  - the step is *refuted*;
  - kept steps are *recomputed*;
  - kept steps are *truly independent*.
  - Self-declared `[uses]` doesn't establish the third.
  - This matches the round-1 literature verdict: exact masking needs steps that attend only to their declared premises.
- **Answer to open problem 1, "useful mistakes":** not supported here.
  - Keeping a refuted step's influence (lag_mask) did worse than removing it (trunc / refresh).
  - The two round-1 anecdotes did not generalize.
- **Answer to open problem 2, translation:** it remains the bottleneck.
  - A grammar fixes the syntax.
  - It does not fix faithfulness: claims are forced into the wrong fact, and the model restates proven facts to pass.

### Where a paper could still be

1. **Systems paper on verification latency:** "async checking with refute-only truncation", with the latency sweep as the core plot. The plot exists here at n=30. Needs:
   - n ≥ 100;
   - a real slow checker instead of simulated latency (an LLM autoformalizer sharing the GPU, or Lean);
   - a second model.
2. **Make masking exact, then re-test:** force each step to attend only to the prompt and its declared parents (a block-sparse attention mask at decode time). Masking is then exact by construction. That is the version of the original idea that could beat truncation at high latency, and it needs a custom attention mask (not available through llama-cpp-python's API).
3. **Fix faithfulness before accuracy claims:** a "new fact" check (reject restated formulas), and an English↔FOL consistency check (VeriCoT-style).

# Round 3 (2026-10-16/17): n=100 on a cloud GPU, Qwen3-14B and Qwen3-30B-A3B

**Setup**
- Colab L4 (24 GB), llama-cpp-python 0.3.36 built with CUDA, Q4_K_M GGUFs from Qwen's Hugging Face repos.
- 100 ProverQA-Hard problems: seed 0, with 411 and 473 excluded as before.
- Same v2 policy as round 2: format guard, and only *refuted* steps are rejected, in sync too.
- Checker latency is simulated on round 2's token clock (72.4 ms per token). Modeled times are therefore comparable across models; raw L4 wall time is shown separately.
- Cost: 22.5 of 300 compute units (L4 at 1.54 units/h).
- Driver scripts: `cloud/colab.sh` (Mac side) and `cloud/vm.sh` (on the VM).

**Why the 30B-A3B became the main model**
- It structures proofs better: 15.3 steps per problem in `fmt`, against 10.1 for the 14B, so a refutation has finer steps to cut.
- It has the highest checked accuracy: 73% sync, against 65% for the 14B.
- It is a mixture of experts with 3B active parameters, so it is about 2.5× faster than the dense 14B on the L4 (about 9 s vs 22 s per problem).

## Results

### Accuracy (correct of 100)

| Condition | 14B | 30B v2 | 30B v3 |
|---|---|---|---|
| `base` (ProverQA CoT) | 58 | 57 | 57 |
| `fmt` (steps, unchecked) | 66 | 67 | 71 |
| `sync` | 65 | 73 | 71 |
| `lag_trunc` L=1 / 3 / 8 | 70 / 70 / 70 | 72 / 73 / 73 | 71 / 71 / 71 |
| `lag_mask` L=1 / 3 / 8 | 70 / 71 / 71 | 74 / 72 / 71 | 76 / 72 / 73 |
| `lag_refresh` L=8 | 73 | 71 | 72 |

Paired tests below are wins/losses on the same problems, with exact sign test p-values.

- **The checker still doesn't raise accuracy, at any scale.**
  - sync minus fmt: 8B −3 points (n=30), 14B −1 (8/9, p=1.0), 30B v2 +6 (8/2, p=0.11), 30B v3 0 (9/9, p=1.0).
- **The step format helps over plain CoT.**
  - fmt vs base: 14B 25/17 (p=0.28), 30B v2 24/14 (p=0.14), 30B v3 27/13 (p=0.04).
- **At 14B and 30B, masking no longer costs accuracy** (round 2's 8B lost 27 points at L=8).
  - mask vs trunc: every latency on every model has p ≥ 0.18; the best is 7/2 for mask at 30B v3, L=1.
  - `lag_refresh` adds nothing over `lag_mask` at this scale: 5/3, 4/4, 3/4.

### Systems (modeled seconds per problem, token clock)

| Model | L s | sync | lag_mask | lag_trunc | mask vs sync | mask vs trunc | mask fewer tokens W/L, p |
|---|---|---|---|---|---|---|---|
| 14B | 1 | 51.8 | 45.6 | 46.4 | −12% | −2% | 10/4, p=0.18 |
| 14B | 3 | 74.4 | 49.0 | 50.6 | −34% | −3% | 16/9, p=0.23 |
| 14B | 8 | 130.9 | 55.8 | 62.2 | −57% | −10% | 32/10, p=0.001 |
| 30B v2 | 1 | 74.7 | 58.7 | 61.0 | −21% | −4% | 21/9, p=0.043 |
| 30B v2 | 3 | 107.8 | 59.8 | 63.6 | −45% | −6% | 24/9, p=0.014 |
| 30B v2 | 8 | 190.4 | 63.3 | 69.5 | −67% | −9% | 26/10, p=0.011 |
| 30B v3 | 1 | 126.7 | 96.9 | 109.4 | −24% | −11% | 24/11, p=0.041 |
| 30B v3 | 3 | 158.7 | 95.0 | 112.0 | −40% | −15% | 23/15, p=0.26 |
| 30B v3 | 8 | 238.8 | 106.6 | 114.0 | −55% | −7% | 21/21, p=1.0 |

- **Asynchronous checking is the robust win:** 12–67% faster than sync, growing with latency, on every model.
- **With the 20-step cap (v2), masking uses significantly fewer tokens than truncation:**
  - at 14B, only at L=8;
  - at 30B, at every latency;
  - the time saved grows with latency, from 2–4% at L=1 to 9–10% at L=8.
- **v3 (no cap):** mean tokens are 8–17% lower for mask, but the effect is in the tail.
  - Excluding problems where either condition hit a cap, mask and trunc don't differ (p ≥ 0.21, n = 66–70).
  - Mask hits a cap less often: 27 / 26 / 20 problems against trunc's 28 / 29 / 25 at L=1 / 3 / 8.

### What v3 changed, and what it showed

**Changes**
- `CHECK_ALL=1`: the checker verifies any formula. A formula that restates a premise gets a `restated` verdict; it is kept but doesn't count as a derivation.
- `CACHE=1`: an identical formula reuses its earlier verdict and skips the simulated wait.
- Caps raised so nothing is cut: steps 20 → 60, generated tokens 2500 → 5000, base 1500 → 4000.
- `PROBE=0`: the consistency probe was 5–10% of wall time.
- Context usage is logged per problem.

**Findings**
- **Removing the step cap didn't raise accuracy.**
  - v3 vs v2 on the same problems: every condition has p ≥ 0.39.
  - In v2, 48 fmt problems reached 20 steps. In v3, 28 of them finish without a cap, getting 18 right vs 14 on those problems in v2. The other 20 run on to 60 steps.
- **20–29% of problems still end on a cap, almost always the step cap. These are loops, not long proofs.**
  - Example: id 7 repeats `perfectionist(Wyatt) ∨ thinks_carefully(Wyatt)` up to step 60, and every repeat checks as entailed.
  - Forced answers are 52–75% correct, against 70–84% for unforced ones.
  - Loops happen in unchecked `fmt` too (20/100), so the model causes them, not the checker.
- **Cost of the loops**
  - Mean tokens nearly double: fmt 617 → 1179, sync 685 → 1410.
  - The median barely moves: fmt 720 → 767.
  - Per condition, 984–1150 steps are `restated`, and 1111–1341 formulas hit the verdict cache. Most of the extra steps are repeats.
- **Context usage**
  - Peak live KV cells per problem are 2235–2502 for the checked conditions.
  - Mask holds fewer cells at peak than trunc (2294 vs 2435 at L=1, 2242 vs 2440 at L=3, 2337 vs 2388 at L=8), but the masked spans themselves are small: mask's peak position minus its peak live cells is only 19–38 tokens.
  - So masking saves by regenerating less after a refutation, not by keeping a smaller cache.

## Verdict after round 3

- **Accuracy: still no.** A step checker doesn't improve accuracy at 8B, 14B or 30B. The step format itself is worth +8 to +14 points over plain CoT.
- **Systems: async checking is the paper-grade result.** It is 12–67% faster than blocking on three models at n=100, at no accuracy cost.
- **The original masking idea scales better than it looked at 8B.**
  - At 14B and 30B it doesn't cost accuracy.
  - Under v2 it uses significantly fewer tokens than truncation, a saving that grows with checker latency (up to −10% time at L=8).
  - It is a modest gain over truncation, not a headline one.
- **Next**
  1. A loop detector: reject a formula repeated k times, with a nudge, or force the answer. This removes most of v3's tail and should make the mask vs trunc comparison cleaner.
  2. A real slow checker in place of the simulated latency.
  3. Exact block-sparse masking (round 2, item 2).

# Round 4 (2026-10-18): why does masking lose at 8B? Two cheap fixes, both null

Qwen3-8B (Qwen's Q4_K_M GGUF) on a Colab L4, the same 30 problems, L = 8 s, v2 policy. About 1 unit.

**Diagnostics on the existing logs first**
- *Hidden logical dependents* (a kept step the premises do not prove, but that would follow if the refuted step were believed; `Problem.supports`, which avoids ex falso by starting from the rules) are rare: 2/30 problems at 8B, 3–5/100 at 14B, 6–9/100 at 30B, and mask and trunc tie on them. The model's `[uses]` lists are faithful at the logic level, so this is not the mechanism.
- *Quitting*: after a mask the 8B wrote no further step in 16/20 masked problems and answered "Uncertain" in 16/20 (trunc: 13/20 and 13/20); True problems 1/9 right vs 6/9.

**Run**

| Condition | Accuracy | Tokens | Masks / truncations | Answers A/B/C | True problems right |
|---|---|---|---|---|---|
| trunc | 22/30 | 558 | 0 / 91 | 11/7/12 | 8/9 |
| mask | 18/30 | 364 | 48 / 4 | 8/6/16 | 5/9 |
| mask + RETRY (next chunk after a mask forced to be a step) | 19/30 | 616 | 80 / 9 | 11/6/13 | 7/9 |
| mask + INFER (solver-inferred dependents also masked) | 18/30 | 366 | 48 / 4 | 8/6/16 | 5/9 |

- mask vs trunc: 2/6, p = 0.29 (the Mac run was 0/8, p = 0.008; same direction, smaller gap on this build).
- INFER masked 7 extra steps and changed no answer (0/0 vs mask). Closed: declared dependencies are good enough.
- RETRY recovered True problems (7/9) but only +1 overall (2/1 vs mask), and the forced retries loop: 80 masks, 616 tokens, more than truncation. Not a win.
- What is left is round 2's mechanism, stale cache entries of the kept steps (refresh recovered 5/8), plus the model giving up. Neither cheap policy fix closes the gap; at 8B, truncation stays the right policy. The remaining lever is exact masking (each step attends only to the prompt and its declared parents).

# Round 5 (2026-10-19): efficiency fixes at 14B. Loop cropping pays; dependency-scoped waiting and the hybrid do not

**Setup.** Qwen3-14B, L=8 s, n=30 on an L4, v2 policy (GUARD=1, MASK_ON=refuted), paired against round 3's n=100 runs of the same policy on the 28 shared problems. Two fixes applied to every condition: `DEPWAIT=1` (the final answer waits only for verdicts of steps it transitively depends on, not for every pending step) and `LOOP=2` (a step whose formula repeats an earlier live step is cropped and noted; after 3 crops the answer is forced). Third condition: `lag_refresh` with `HYBRID=50` (if fewer than 50 kept tokens would survive a mask, truncate instead of recomputing).

| Condition (L=8, 28 paired problems) | Accuracy | Gen tokens | Wasted | Wait s | Modeled s | Wall s (L4) |
|---|---|---|---|---|---|---|
| round 3 trunc | 21/28 | 644 | 322 | 6.9 | 62.1 | 25.6 |
| round 3 mask | 20/28 | 621 | 243 | 6.8 | 60.3 | 24.9 |
| round 3 refresh | 20/28 | 644 | 316 | 7.0 | 62.2 | 25.6 |
| trunc + DEPWAIT + LOOP | 21/28 | 521 | 258 | 5.8 | 52.1 | 20.8 |
| mask + DEPWAIT + LOOP | 20/28 | 504 | 253 | 6.4 | 51.5 | 20.4 |
| hybrid (refresh, HYBRID=50) + DEPWAIT + LOOP | 20/28 | 536 | 276 | 5.6 | 53.0 | 21.5 |

Paired against the round 3 run of the same policy (sign tests, two-sided):

- trunc: fewer tokens 8/2 (p = 0.11), faster 11/1 (p = 0.01), −10.0 s modeled (−16%), −19% tokens; accuracy +1/−1.
- mask: fewer tokens 10/2 (p = 0.04), faster 12/1 (p = 0.003), −8.8 s (−15%), −19% tokens; accuracy +1/−1.
- refresh → hybrid: fewer tokens 8/4 (p = 0.39), faster 11/3 (p = 0.06), −9.2 s; accuracy +1/−1.

**Findings**

1. *All of the saving is the loop detector.* 12–14 of the 28 problems repeat a formula; on those the new runs generate 214–289 fewer tokens (about 880 → 600), and on the other problems the generations are identical (0 token difference: the fixes are inert until a loop or an avoidable wait occurs). 5–6 problems per condition hit the 3-crop limit and were forced to answer. Accuracy on the looped problems is the same as before (8/12, 7/13, 9/14 in both runs), so the loops were pure waste: cropping them changed no answer.
2. *DEPWAIT barely matters at 14B.* Wait time falls 6.9 → 5.8 s (trunc) and 6.8 → 6.4 s (mask), about 1 s per problem, because only 5–6 problems per condition had a pending step the answer did not depend on. Waiting is about 11% of modeled time at L=8; round 4's upper estimate (4–8 s per problem) was not reachable.
3. *HYBRID=50 turns refresh into truncation.* The kept-token rule fired 44 times against 3 recomputes (5.8 recomputed tokens per problem): the suffix after a refuted step is usually short. So hybrid ≈ trunc (tokens 0/2, p = 0.5). The threshold is too high, and at 14B there is nothing for refresh to recover anyway (round 3: same accuracy).
4. *mask vs trunc at 14B, with the fixes: still a tie* (tokens 5/6, time 4/6, accuracy 0/1).

**Verdict.** At 14B / L=8 the cheap fixes give −16% modeled time and −19% tokens at no accuracy cost, and the whole gain is the loop detector. Efficiency is done: waiting is small, the hybrid collapses to truncation, and mask ≈ trunc. Defaults going forward: `LOOP=2` on, `DEPWAIT=1` on (free), truncation as the policy below 30B.

# Round 6 (2026-10-19): five more models at n=30. Async holds everywhere; the Qwen3-8B masking collapse is that model's alone; the checker helps the non-Qwen families

**Setup.** The v2 condition set (base, fmt, sync, lag_trunc/lag_mask at L=1/3/8, lag_refresh at L=8; GUARD=1 MASK_ON=refuted) on 30 problems (same seed as the 8B runs) for Qwen3-4B, Llama 3.1 8B, Phi-4 (14B), Mistral Small 24B and Qwen3-32B (dense). All Q4_K_M, each with its own chat template (`run.py` TEMPLATES). One Colab A100 session, 3.3 GPU-hours, 17.3 units. Analysis: `analyze_r6.py`.

### Accuracy (correct of 30; checked conditions at L=8)

| Model | base | fmt | sync | trunc | mask | refresh | fmt vs base | sync vs fmt | mask vs fmt | mask vs base |
|---|---|---|---|---|---|---|---|---|---|---|
| Llama-3.1-8B | 33.3 | 33.3 | 46.7 | 43.3 | 40.0 | 46.7 | 6/6 p=1.00 | 6/2 p=0.29 | 6/4 p=0.75 | 7/5 p=0.77 |
| Phi-4 | 43.3 | 50.0 | 66.7 | 66.7 | 73.3 | 66.7 | 6/4 p=0.75 | 6/1 p=0.12 | 10/3 p=0.09 | 11/2 p=0.02 |
| Mistral-Small-24B | 56.7 | 56.7 | 73.3 | 76.7 | 73.3 | 66.7 | 6/6 p=1.00 | 5/0 p=0.06 | 6/1 p=0.12 | 9/4 p=0.27 |
| Qwen3-32B | 43.3 | 63.3 | 70.0 | 70.0 | 70.0 | 70.0 | 11/5 p=0.21 | 3/1 p=0.62 | 3/1 p=0.62 | 12/4 p=0.08 |
| Qwen3-4B | 30.0 | 50.0 | 63.3 | 63.3 | 56.7 | 60.0 | 8/2 p=0.11 | 7/3 p=0.34 | 5/3 p=0.73 | 10/2 p=0.04 |

Pooled (wins/losses, two-sided sign test):

- Llama + Phi-4 + Mistral: fmt vs base 18/16 p=0.864; sync vs fmt 17/3 p=0.003; mask vs fmt 22/8 p=0.016; mask vs base 27/11 p=0.014
- Qwen3-32B + Qwen3-4B: fmt vs base 19/7 p=0.029; sync vs fmt 10/4 p=0.180; mask vs fmt 8/4 p=0.388; mask vs base 22/6 p=0.004

### Systems (modeled seconds per problem; paired sign tests on per-problem time)

| Model | L | sync | trunc | mask | async saving (trunc vs sync) | mask vs trunc | mask acc − trunc acc |
|---|---|---|---|---|---|---|---|
| Llama-3.1-8B | 1 | 69.2 | 55.6 | 54.6 | −20% (22/8 p=0.016) | +1.9% (3/3 p=1.00) | +0.0 (1/1 p=1.00) |
| Llama-3.1-8B | 3 | 101.5 | 66.4 | 63.7 | −35% (26/4 p=0.000) | +4.1% (8/3 p=0.23) | +3.3 (3/2 p=1.00) |
| Llama-3.1-8B | 8 | 182.4 | 84.3 | 74.4 | −54% (28/2 p=0.000) | +11.8% (10/5 p=0.30) | -3.3 (2/3 p=1.00) |
| Phi-4 | 1 | 50.9 | 42.5 | 40.5 | −16% (25/5 p=0.000) | +4.6% (8/3 p=0.23) | +10.0 (3/0 p=0.25) |
| Phi-4 | 3 | 75.0 | 48.2 | 46.1 | −36% (29/1 p=0.000) | +4.3% (8/4 p=0.39) | +10.0 (4/1 p=0.38) |
| Phi-4 | 8 | 135.4 | 64.7 | 56.1 | −52% (30/0 p=0.000) | +13.3% (13/5 p=0.10) | +6.7 (5/3 p=0.73) |
| Mistral-Small-24B | 1 | 38.8 | 35.8 | 33.8 | −8% (24/6 p=0.001) | +5.8% (5/2 p=0.45) | +0.0 (2/2 p=1.00) |
| Mistral-Small-24B | 3 | 56.5 | 42.0 | 38.8 | −26% (27/3 p=0.000) | +7.6% (6/3 p=0.51) | -3.3 (2/3 p=1.00) |
| Mistral-Small-24B | 8 | 100.6 | 53.2 | 48.9 | −47% (29/1 p=0.000) | +8.1% (7/8 p=1.00) | -3.3 (1/2 p=1.00) |
| Qwen3-32B | 1 | 41.9 | 36.7 | 36.2 | −12% (25/5 p=0.000) | +1.6% (3/0 p=0.25) | -3.3 (0/1 p=1.00) |
| Qwen3-32B | 3 | 59.7 | 40.1 | 38.6 | −33% (28/2 p=0.000) | +3.7% (5/0 p=0.06) | -3.3 (0/1 p=1.00) |
| Qwen3-32B | 8 | 104.2 | 48.9 | 48.4 | −53% (29/1 p=0.000) | +0.9% (4/5 p=1.00) | +0.0 (1/1 p=1.00) |
| Qwen3-4B | 1 | 48.4 | 42.3 | 42.9 | −13% (25/5 p=0.000) | -1.5% (3/7 p=0.34) | +3.3 (1/0 p=1.00) |
| Qwen3-4B | 3 | 71.0 | 46.5 | 45.6 | −35% (27/3 p=0.000) | +1.8% (5/10 p=0.30) | +3.3 (2/1 p=1.00) |
| Qwen3-4B | 8 | 127.5 | 59.0 | 47.4 | −54% (28/2 p=0.000) | +19.7% (10/6 p=0.45) | -6.7 (1/3 p=0.62) |


**Findings.**

- Asynchronous checking beats blocking on all five models at every delay (25/5 or better, p < 0.001 except Llama at 1 s, 22/8, p = 0.016): 8 to 54% of modeled time.
- Masking vs truncation at n=30 is not resolvable for savings of 2 to 20% (the 30B's 4 to 10% needed n=100). No model repeats the Qwen3-8B's accuracy collapse: the worst cell is Qwen3-4B at 8 s, −6.7 points, 1/3. So the 8B failure is one model's, not a size threshold.
- Qwen3-32B gains almost nothing from masking (0.9 to 3.7%) because a mask salvages only 9 tokens per problem there (30 to 89 on the other models): when one of its steps is refuted, nearly everything after it depends on it.
- Accuracy splits by family. The two new Qwen3 sizes repeat the Qwen pattern (format alone +20 points on both, pooled 19/7 p = 0.03; checker adds nothing). Llama, Phi-4 and Mistral do the opposite: format alone 18/16 (nothing), checker on top 17/3 at sync (p = 0.003), 22/8 at async L=8 (p = 0.016). Of the 22 problems those three get right only with the checker, 17 had at least one refuted step. Pooled over all five, masking at 8 s beats plain CoT 49/17 (p < 0.001).
- Phi-4 is the one model where masking beats truncation on accuracy in every cell (+10, +10, +6.7), none significant (3/0, 4/1, 5/3).

**Verdict.** The systems result (async) is family-independent. The masking accuracy failure is specific to Qwen3-8B. The accuracy story needs n=100 on at least one non-Qwen model before the "checker helps models that don't follow the format" claim is more than suggestive.

## Files

| Path | Contents |
|---|---|
| `results_cloud/{Qwen3-4B,Llama-3.1-8B,Phi-4,Mistral-Small-24B,Qwen3-32B}/` | Round 6: the v2 condition set at n=30 per model; log `results_cloud/run_vm6.log`, setup log `results_cloud/setup6.log` |
| `results_cloud/Qwen3-14B_eff/` | Round 5: `lat8/lag_{trunc,mask,refresh}` with DEPWAIT=1 LOOP=2 (refresh also HYBRID=50), n=30; log `results_cloud/run_vm5.log` |
| `results_cloud/Qwen3-8B_infer/` | Round 4: `lat8/lag_{trunc,mask}`, `lat8_retry/lag_mask`, `lat8_infer/lag_mask`, n=30 |
| `results_cloud/Qwen3-14B/`, `results_cloud/Qwen3-30B-A3B/` | Round 3, v2 policy, n=100: `base`, `fmt`, `sync`, `lat{1,3,8}/lag_{trunc,mask}`, `lat8/lag_refresh` |
| `results_cloud/Qwen3-30B-A3B_v3/` | Round 3, v3 settings (no cap, CHECK_ALL, cache, context usage), same layout |
| `results_cloud/run_vm1.log`, `run_vm2.log`, `run.log`, `base.log` | VM logs (14B, 30B v2, 30B v3, 14B base) |
| `cloud/colab.sh`, `cloud/vm.sh` | Cloud driver (Mac side, VM side) |
| `results/v2/` | Final, comparable runs: `sync.jsonl`; `lat{1,3,8}/lag_{mask,trunc}.jsonl`; `lat8/lag_refresh.jsonl`; `note_lat3/lag_mask.jsonl` |
| `results/grammar/` | Grammar runs (fixed token boundary) |
| `results/lat3/`, `results/refuted_lat3/`, `results/refuted_lat8/`, `results/realtime_lat3/` | Pre-guard runs, superseded |
| `results/grammar_bug_tokenboundary/`, `results/note_refuted_lat3_partial_noguard/` | Invalid / partial |
| `queue9.sh`, `results/run3.log` | Last run queue and full log |
