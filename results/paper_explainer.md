# The paper in plain language (companion to results/paper.pdf)

## 1. What the project is

- The model solves logic puzzles (ProverQA-Hard). Each puzzle is a list of facts and rules, then a statement. The answer is True, False or Uncertain.
- We make the model write its reasoning as numbered steps. Every step says which earlier facts or steps it uses (`[uses P2, S1]`) and gives its claim as a logic formula.
- A program called Z3 (an "SMT solver", basically an automatic logic checker) checks every formula against the puzzle's facts. If the formula contradicts the facts, the step is **refuted**.
- When a step is refuted, we remove it, and also every later step that was built on it, and the model carries on.

## 2. The three ideas that were measured

1. **Asynchronous checking.** Don't make the model wait for the checker. Let it keep writing; when a verdict arrives a step or two later, deal with it then. Analogy: an editor reviews your previous paragraph while you write the next one, instead of you stopping after every paragraph.
2. **Masking instead of truncating.** When a step is refuted, "truncate" throws away everything written after it and regenerates. "Mask" deletes only the bad step and the steps that used it from the model's working memory, and keeps the independent steps.
3. **Loop cropping.** The model sometimes writes the same formula over and over until it hits the step limit. Detect the repeat, cut it out, and after three repeats force an answer.

## 3. Terms that come up

- **KV cache**: the model's working memory of everything in the context. Deleting a span from it means the model can no longer see those tokens.
- **Checker latency (L)**: how long the checker takes. Z3 is instant, so we simulate 1, 3 and 8 seconds per check. This stands in for slower checkers we would use in practice (a second model that translates English into logic, or a proof assistant like Lean).
- **Modeled time**: a formula, 8.6 s + 72 ms per generated token + waiting time. It makes runs on different machines comparable. Real wall time on the GPU is also reported and moves the same way.
- **Paired sign test / p-value**: we run two versions on the same problems and count on how many problems version A was faster (or more accurate) than B. The p-value is the chance of seeing a split that lopsided by luck alone. p below 0.05 is the usual bar for "significant".

## 4. The results (all statistically significant)

1. **Async beats blocking on every model at every latency.** Faster on 27–29 of 30 problems at 8B and on 77–99 of 100 at 14B and 30B. Every p-value is below 0.001. Time saved: 12% with a 1-second checker, up to 67% with an 8-second checker. Accuracy is the same.
2. **Masking beats truncating when the model is big enough and the checker is slow.** At 30B at all three latencies (21/9, 23/10, 25/11 problems faster; p = 0.04, 0.04, 0.03) and at 14B with the 8-second checker (31/11; p = 0.003). Saves 4–10% of time.
3. **Masking hurts at 8B with a slow checker.** Accuracy drops from 63% to 37%: masking lost 8 problems to truncation and won none (p = 0.008). So masking is only for models of 14B and up.
4. **Loop cropping saves 16% of time and 19% of tokens at 14B.** Faster on 11 of 12 and 12 of 13 differing problems (p = 0.01 and 0.003). Answers unchanged (1 win, 1 loss). On problems with no loop, the output was identical byte for byte.

## 4b. The five extra models (added later, 30 problems each)

- Qwen3-4B, Llama 3.1 8B, Phi-4 (14B), Mistral Small 24B, Qwen3-32B, same harness, each with its own prompt format.
- Not waiting for the checker is faster on all five at every delay (p < 0.001 nearly everywhere). That result does not depend on the model family.
- None of them repeats the Qwen3-8B's masking collapse. The worst is the 4B at 8 s, −6.7 points, 1 win to 3 losses. So "masking breaks small models" is wrong; it broke one model.
- Masking's time saving can't be confirmed at 30 problems (it needed 100 on the 30B). The 32B gets almost nothing from it because when one of its steps is refuted, nearly everything after depends on it, so there is nothing to keep.
- The accuracy story split by family. On the two new Qwen sizes the step format alone adds 20 points and the checker adds nothing, like the first three Qwens. On Llama, Phi-4 and Mistral the format alone adds nothing and the checker adds 14 to 24 points (pooled 17 wins to 3 losses, p = 0.003). Where the checker helped, it had refuted a step on 17 of the 22 problems it fixed. Read it as: a model that already follows the step format well has little left for the checker to fix. It rests on 30 problems per model, so it is suggestive, not settled.

## 5. What was left out of this version, and why

- **The step format helps; the checker on top of it does not.** Making the model write numbered steps with formulas raised accuracy by 8 to 14 points over the benchmark's own chain-of-thought prompt on every model (pooled 55 wins / 34 losses, p = 0.03). Adding Z3 checking to that format changed nothing (p ≥ 0.11). Both facts are in the accuracy section, because the speed claims are "faster at the same accuracy" and the reader needs to know what that accuracy is.
- **Everything that tested null:** recomputing kept steps after a mask, letting the answer wait only for the verdicts it depends on, a mask/truncate hybrid, and two diagnostics of the 8B failure. All were run, none reached significance. They are in the long version, results/paper_full.pdf, and in results/RESULTS.md.

## 6. The findings list in the introduction, decoded

- "Blocking" = the model stops after every step and waits for Z3's verdict. "Asynchronous" = it keeps writing and the verdict arrives a step or two later.
- "On every model" = the 8B, 14B and 30B models. "At every latency" = whether we pretend the checker takes 1, 3 or 8 seconds.
- "Modeled time" = the time formula (fixed cost + per-token cost + waiting), so machines compare fairly.
- "Masking" = delete only the refuted step and the steps that used it. "Truncation" = delete everything after the refuted step and regenerate it.
- "Slow checker" = the simulated 8-second checker.
- "63.3% → 36.7%" = the fraction of puzzles answered correctly under truncation versus under masking, for the 8B model with the slow checker. "p = 0.008" = under 1% chance that gap is luck.
- "Tokens" = the pieces of text the model generates; fewer tokens means less GPU time and cost.

## 7. "What is an 8-second checker, and why are we timing the checker?"

We are not timing Z3. Z3 answers in milliseconds, so if we deployed the pipeline exactly as built, waiting for it would cost nothing and there would be nothing to study. In a real system the check is slow for reasons that sit in front of Z3: the model's English step has to be translated into logic, which in practice is a separate model call taking seconds; or the check is done by a proof assistant like Lean instead of Z3; or the checker shares the GPU with generation and slows it down. So the experiment asks: as the checker gets slower, how much does each design choice cost? We simulate a checker that returns each verdict 1, 3 or 8 seconds after the step was written. "An 8-second checker" is the slowest of those settings. Because the model writes about 14 tokens per second, "8 seconds" is implemented as "the verdict arrives after the model has written another 110 tokens or so."

## 8. If the manager asks

- *Why no accuracy gain from the checker?* The gain came from the step format (8 to 14 points); the checker on top of it mostly catches translation mistakes (the English claim turned into the wrong formula), not reasoning mistakes. Translating into logic faithfully is the bottleneck.
- *Where would this be used?* Anywhere a verifier is slower than generation and can run alongside it: a model that translates steps into logic before a solver check, a proof assistant like Lean, unit tests on generated code, a tool call that confirms or refutes a step, or a critic model. Only the Z3 case was measured.
- *Why only 30 problems in some runs?* GPU cost. The main 14B and 30B results use 100. With 30, a speed effect this large is easy to detect, but only a large accuracy change would be.
- *Is the latency real?* No, it is simulated on a token clock. The next step is a real slow checker.
- *Why does masking fail at 8B?* The kept steps' cache entries were computed while the refuted step was still visible, so they carry stale information, and the small model tends to give up after part of its context disappears. Fixing that properly needs a change to the attention pattern (each step attends only to the prompt and its declared parents), which llama.cpp does not expose.
- *What's next?* A real slow checker; exact masking via a block-sparse attention mask; a few hundred problems and a second model family if the accuracy question matters.
