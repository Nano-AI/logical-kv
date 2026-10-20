# Paper summaries for the logical-KV MVP

**Setup:** Qwen3-8B (non-thinking) on ProverQA-Hard. There are four conditions:

- **A:** CoT.
- **B:** Structured steps plus FOL, with no checker.
- **C:** A per-step Z3 check, with regeneration from the verified prefix.
- **D:** Lagged check plus KV/attention invalidation of the rejected step and its dependency-DAG descendants.

**How this was produced:**

- The PDFs come from arxiv.org/pdf/<id>. Text was extracted with `pdftotext -layout`, and the sources are in the arXiv PDFs (not included).
- Only content that was actually read is reported here. "§" means section, "T" means table, "App." means appendix.
- Items marked **[obs]** are my own observations or computations, not claims made by the papers.

**Code status:**

- **Found:** ProverGen (`opendatalab/ProverGen` @ `1d8abd2`), PARC (`SagnikMukherjee/PARC` @ `7082dbd`) and KVEraser (`Graph-COM/KVEraser`, URL taken from the paper; repo not cloned).
- **Not found:**
  - **LogicTrack and VeriCoT:** neither paper links to code, and searching GitHub found no official repo. The GitHub repo search API returned only unrelated hits, and `amazon-science/vericot` does not exist.
  - **Aborted but Not Forgotten:** an "anonymized artifact" only.

---

## 1. ProverQA / ProverGen — arXiv 2502.06563 (ICLR 2025)

### How the data is built

- **Construction (§3.2.2):** logic skeletons are built **top-down** from the goal's truth value. A rule is sampled for each node, and Prover9 assigns truth values to its children. Every instance is then Prover9-validated with its distractors included (App. H).
- **Distractors (§3.2.2, §3.3):** each problem has two kinds.
  - **Type 1:** same-domain facts and rules about a *different subject name*.
  - **Type 2:** logically related rules that resolve to Uncertain, e.g. `(d1 ⊕ d2) → f1` with d2 = Uncertain.
  - The premise order is shuffled.
- **Splits (§3.3):** 1,500 instances in total, 500 each of easy (1–2 steps), medium (3–5) and hard (6–9). Hard additionally involves "more diverse reasoning directions", e.g. modus tollens: from f2 = False and f1 → f2, infer f1 = False.

### Published results

- **Main results (T2, 2-shot):**
  - **Hard CoT:** GPT-4o 50.0, Claude-3.5-Sonnet 56.4, Llama3.1-70B 46.8, **Llama3.1-8B 33.6**, Mistral-7B 41.8.
  - **Hard Standard:** Llama3.1-8B 39.0. On hard, CoT gains only +3.86 on average and *hurts* the 8B models.
  - The README adds o1-preview at 66.2 and DeepSeek-R1 at 66.6 on hard.
- **Ablation (T3, GPT-4o CoT on hard):**

  | Setting | Hard accuracy |
  |---|---|
  | Default | 50.0 |
  | No distractors | 57.4 |
  | No distractors and premises in chain order | 62.4 |

  Distractor handling and premise ordering are therefore major error sources.
- **Shortcut check (App. C, T6):** removing universal rules drops accuracy by 11–23 points, so the models are not relying on world knowledge.
- **5-shot (App. G, T7):** this does not consistently help. Llama3.1-8B CoT on hard goes 31.2 (−2.4).
- **Fine-tuning (T4):** Llama3.1-8B fine-tuned on ProverQA-train reaches 68.2 on hard (+34.6).
- **Quality (App. H):** a manual audit of 60 items found no errors, so they estimate an error rate under 2%.

### Dataset (HF `opendatalab/ProverQA`)

- **Files:** `dev/easy.json`, `dev/medium.json`, `dev/hard.json` (500 each) and `train/provergen-5000.json`.
  - There are **no HF configs or splits**. Load with `load_dataset("opendatalab/ProverQA", data_files="dev/hard.json")`, which yields a single `train` split.
  - The train file is Alpaca-style (`system`, `instruction`, `input`, `output`) and has **no** `nl2fol`.
- **Dev fields (verified on `dev/hard.json`):** `id`, `context`, `question`, `options`, `answer`, `reasoning`, `nl2fol`, `conclusion_fol`.
  - `options` is always `["A) True", "B) False", "C) Uncertain"]`.
  - `answer` is in {A, B, C}. **[obs]** Hard label counts are A 143, B 183, C 174, so the majority-class baseline is 36.6%.
  - `nl2fol` is a dict mapping each context sentence (exact string) to its FOL.
- **FOL syntax [obs, counted over all 1,500 dev items]:**
  - Symbols used: `¬ ∧ ∨ → ⊕ ∀`, plus parentheses.
  - **There are zero `∃` and zero `↔`.** The README's "all seven" claim includes ∃, but it does not occur in dev.
  - All predicates are **unary**, the only quantifier form is `∀x (...)`, and constants are capitalised names.
  - Example: `∀x (is_large_breed(x) → has_strong_muscles(x))`, `(has_strong_muscles(Legend) ⊕ has_athletic_build(Legend)) → is_competitive(Legend)`.
  - Predicate names are **inconsistent across distractor subjects**, e.g. `well_trained(Loyal)` vs `is_well_trained(Legend)`.
  - `conclusion_fol` may use a different surface form from the question. For example, the question "Legend has a distinctive marking" has `conclusion_fol` `¬has_no_distinctive_marking(Legend)`.
- **Gold `reasoning` format:** blocks of `fact1: …\nfact2: …\nrule: …\nconclusion: …`, separated by blank lines, ending in `Therefore, it is true/false that … The correct option is: X.` For Uncertain items the ending is `According to the context and the conclusions that have already been drawn, we can deduce that it is uncertain that … The correct option is: C.`
  - **[obs]** Hard has 3–9 `conclusion:` blocks, mean 6.56.
  - **[obs]** The gold NL steps are not error-free. In hard id 411 the last block concludes "Zora is not skilled with tools" from "not inept" plus a XOR rule, which is wrong, although the label is right.

### Z3 sanity check [obs]

- **Method:** a 70-line parser from the dataset's FOL to Z3. It uses an uninterpreted sort, an unary `Function(..., Bool)` per predicate, and `ForAll`. The label rule is A iff `P ⊨ c`, B iff `P ⊨ ¬c`, else C.
- **Result:** this reproduces gold on **hard 498/500**, medium 489/500 and easy 498/500. The hard mismatches are ids 411 and 473 (gold B, Z3 C).
- **Script:** `scripts/z3_label_check.py`.

### Eval harness (repo `evaluation.py`, `result/metrics.py`)

- **Prompt:** 2-shot, split-specific in-context examples taken from `logic_data/icl_examples/ProverGen.json["hard_CoT"]`, plus a system message (verbatim copy in `proverqa_prompt.txt`).
- **Decoding:** `temperature=0`; `max_new_tokens=1024` for CoT and 128 for Direct.
- **Repo pitfalls:**
  - The README says `--dataset_name ProverQA`, but the in-context loader only special-cases `ProverGen` (there is no `ProverQA.json` in `icl_examples`). The data path is `logic_data/<dataset_name>/<split>.json`, so HF `dev/hard.json` has to be copied to `logic_data/ProverGen/hard.json`.
  - **[obs]** The 2nd hard in-context example contains a reasoning slip: it derives "Kinsley is not thriving", then says "Therefore, it is false that Kinsley is not thriving". This is kept verbatim.
- **Answer extraction (`evaluate_QA`):**
  - **No regex.** It snaps endings such as `…"answer": "A"\n}` to a canonical form, then runs `eval(text.replace('```json','').replace('```','').split("\n\n")[0])['answer']`. That is **Python `eval` on model output, which is unsafe and must not be copied.**
  - Any parse failure counts as **wrong**; it stays in the denominator and is reported as "Parse Error".
  - There are model-specific variants. The Claude one uses `endswith('\n  "answer": "X"\n}')`. The Mistral one splits at `\n\n` and `\n------\n`, then substring-matches `"answer": "X"` or `A) True`/`B) False`/`C) Uncertain`.

## 2. LogicTrack — arXiv 2609.21492 (Hu, Yang, Liu, Wang; Bristol/KAUST)

### Method

- **Idea (§1–2):** a generation-time, step-wise solver audit. When a step fails, it backtracks and regenerates from the failed step using the verified prefix plus feedback. The paper contrasts this with post-hoc VeriCoT and LogicReward.
- **Step format (§2.1):**
  - Each step is s_i = (C_i, E_i, q_i): Context C_i ⊆ P ∪ K_{i−1}, Explanation E_i (implicit bridges such as "a father is a parent"), and Conclusion q_i.
  - K_i is the set of verified conclusions.
  - The prompt renders these as `##Premises:##` / `##Explanation:##` / `##Derived Fact:##` (App. D).
- **Z3 check (§2.1):**
  - An LLM formalizer turns (C_i, E_i, q_i) into SMT-LIB F_i = (Φ_i, q_i), where Φ_i encodes C_i ∪ E_i.
  - The solver first checks syntax. A malformed spec triggers re-formalization **up to M times; the value of M is not reported**.
  - Validity is tested by refutation: **Φ_i ∪ {¬q_i} is UNSAT ⇒ valid**. The solver also logs contradiction and undecidability.
- **Reward (§2.2):** SBR(s_i) = λ·R_fid + (1−λ)·R_verify.
  - **R_verify:**
    - 1 if the spec is valid and Φ ⊨ q.
    - 0 if the spec is still syntactically invalid after M attempts, or if the step is **refuted (Φ ⊨ ¬q)**.
    - **α ∈ (0,1)** if the solver is undecided.
  - **R_fid ∈ {0,1}:** an LLM judge (gpt-4o-mini) checks that Φ_i is grounded in P and not taken from Q, that any commonsense is acceptable, and that Φ_i is jointly SAT.
  - **λ and α values are not reported.**
- **Search (App. A.1):**
  - Accept if SBR(s_t) ≥ **θ_step = 0.8** and the running mean is ≥ **θ_avg = 0.5**.
  - Allow at most **k = 2 regeneration attempts per step position**. If all fail, force-forward the candidate with the highest SBR.
  - Greedy search beats beam search (prune < 0.75) and MCTS on VWA/UR (T2b). For example, Llama-8B UR is 9.89 vs 12.88 vs 13.54.
- **Implementation (App. B):**
  - The formalizer and judge are gpt-4o-mini, and Z3 is the solver.
  - Reasoner decoding: temperature 0.7, max 10,240 tokens.
  - BASE is zero-shot with the same reasoning prompt.
  - **The formalization prompt is not published.** App. D gives only the reasoning, consistency-check and answer-extraction prompts.

### Metrics and results

- **Metrics (App. B.3):** ρ_x = K_x/T_x, the share of a problem's steps that are verified.
  - OA is the fraction of correct answers.
  - VR = mean ρ, and UR = mean (1 − ρ).
  - **VU** = (1/N) Σ 1[ŷ = y]·1[ρ = 1].
  - **VWA** = (1/N) Σ ρ_x·1[ŷ = y].
- **Results:** there is **no ProverQA**. Datasets are e-SNLI, FOLIO, LogiQA, ProntoQA, ProofWriter, QASC, SARA and SemEval.
  - Qwen2.5-7B averages (T4): OA 66.29→70.60, VU 16.33→35.54, VWA 35.07→49.42, UR 47.37→30.68.
  - ProofWriter, Qwen2.5-7B (T1): OA 63.32→66.83, UR 38.19→22.35.
  - Ablation (T2a): the solver-only reward drives VWA/UR, while fidelity-only mostly drives OA.
- **Answer extraction (App. D):** take the innermost `\boxed{…}` and strip `\text{}`. Fall back to `<answer>…</answer>`, then to "the answer is X" in the final sentences. Otherwise the answer is marked unanswered.

## 3. VeriCoT — arXiv 2511.04662 (Feng et al.; UPenn / AWS)

### Method

- **Mode:** **post-hoc** validation of a finished CoT (Alg. 1). Each step C_i is autoformalized to F_i in SMT-LIB and checked with Z3 against the accumulated knowledge ℱ_{i−1}.
- **Three-way relation (§2):**
  - entailed: ℱ ⊨ F;
  - contradicted: ℱ ⊨ ¬F;
  - consistent but not entailed.
- **Algorithm 1 order:**
  1. Untranslatable check.
  2. **Contradiction** (ℱ_{i−1} ⊨ ¬F_i), which logs an error and *continues*.
  3. **Entailment**, which accepts.
  4. Otherwise **premise generation**: LLM-proposed NL premises from the context or commonsense, each formalized and kept only if consistent (ℱ_{i−1} ∧ p is SAT). If ℱ_{i−1} ∪ {P_i} ⊭ F_i, the step is marked **ungrounded**.
- **Error types (§2):** ungrounded, contradiction, untranslatable.
- **Autoformalization (§2.2):** two stages.
  - The first stage translates the step using the existing vocabulary (declarations).
  - The second extends the vocabulary with `declare-fun`/`declare-sort` and retries the first stage, **up to 3 times**, before marking the step untranslatable.
  - The syntax-error retry count is given only as "multiple attempts".
- **Setup (§3):** the executor is Claude-3.5-Sonnet-v2. Datasets are ProofWriter (the 400-item test set has **no Unknown labels**, App. T5), BioASQ and LegalBench-SARA. There is **no ProverQA**.
- **Metrics (§3.3, T1):** pass rate, precision (accuracy among verified CoTs), VCAR (verified *and* correct) and task accuracy.
  - ProofWriter: VeriCoT pass 45.2, precision 94.1, VCAR 42.5, accuracy 75.8. VeriCoT-NoPrem passes only 3.3, so premise generation is essential.
  - **Self-reflection (§3.4, T3):** one revision round with all per-step diagnostics. ProofWriter pass rate 60.1, VCAR 54.1.
  - Ungrounded is the dominant failure (Fig. 2).
- **Fine-tuning (T4):** SFT and DPO on Qwen2.5-7B with verified CoTs. ProofWriter accuracy goes 47.5→51.8.
- **Prompts and code:** the **prompts are not published** (the appendix has only data stats and three worked failure cases), and **no code was found**.
- **[obs] Vacuity pitfall, visible in App. A.2.1:** "Step logic" is often formalized as `(=> (and A Rule) C)`, e.g. step 3, `(=> (and (animal_visits tiger mouse) (forall …)) (animal_is_big mouse))`. That is a valid formula, so it is "entailed" whether or not A was established. The step goal must be the bare conclusion, with premises asserted only if they are already in the knowledge base.

## 4. PARC — Premise-Augmented Reasoning Chains, arXiv 2502.02362 (ICML 2025)

### Method

- **Steps (Alg. 1, §3):**
  1. Extract each step's premises P_k from the earlier steps, with Step 0 being the question. This turns the linear chain into a DAG.
  2. Detect *native* errors. A math error is judged on the step alone. A **logical inconsistency** is judged against *the question plus P_k only*.
  3. Run a DFS. A step is an **accumulation error** if it is valid in itself but has at least one incorrect premise.
- **Premise definition (§3.1, Eq. 1):** P_i must satisfy two conditions.
  - **Verifiability:** F(s_i | P_i) = 1.
  - **Minimality:** removing any premise makes s_i unverifiable.
  - **[obs]** With Z3, this is exactly an **unsat core** of P_i ∧ ¬s_i.
- **Two ways to map premises (§3.2, T2):**
  - **Aggregative**, one call per step with the full prefix, is recommended.
  - **Dyadic**, pairwise and O(n²), wrongly marks ancestors two or more steps back as premises. GPT-4o GSM8K F1 drops 91.47→85.55 on positives and 88.72→72.84 on synthetic negatives.

### Results

- **Premise-ID metric (§5.1):** precision, recall and F1, averaged per datapoint. **Recall is "the most important"**: extra premises do little harm, but a missing premise breaks verifiability downstream.
  - **T1, Aggregative, GSM8K:**
    - Qwen2.5-7B: precision 67.42, recall **63.53**, F1 65.36.
    - Llama3.1-8B: recall 89.33.
    - Qwen2.5-32B: recall 95.35.
    - GPT-4o: recall 94.42.
- **Error-ID metric (§5.2):** step-level accuracy, normalized per chain first and then over the dataset. "Math" and "logical" errors are merged into a single "Error" class.
  - **T3, GSM8K, full context → model premises:**

    | Model | Full context | Model premises | Accuracy on correct chains |
    |---|---|---|---|
    | Qwen2.5-7B | 54.94 | 69.73 | 100 → **90.37** |
    | Llama3.1-8B | 58.6 | 64.53 | 91.9 → 65.44 |
    | GPT-4o | 68.52 | 79.82 | — |

    Judging with premises only costs small models accuracy on *correct* steps.
  - **T5, accumulation-error class, full context → premises:** Llama-70B 12→57.54; GPT-4o 13.2→44.91.
  - **T4:** oracle and model premises perform about the same when recall exceeds 90%.
- **PERL dataset (§4):** 607 math chains from Llama-3.1-8B. Mean depth 6.02 and branching factor 1.37. Labels come from o1-preview; a 71-item audit found 4 premise issues.
- **Failure modes:** LLMs are biased toward "correct", accumulation errors are hard to detect, and synthetic negatives over-estimate performance.
- **Scope:** math only. There is no FOL or solver.
- **Code:** `github.com/SagnikMukherjee/PARC`. The premise prompt in `src/premise_eval/premise_eval.py` matches paper T18, run with vLLM at temperature 0 and max_tokens 512. Premise IDs are parsed with `re.findall(r"Step \d+", line)`.

## 5. FaithformBench — arXiv 2608.10916 (Cornish, Ghinassi, Yeh et al.)

### Method

- **Approach (§3–4):** faithfulness of step autoformalization is judged **by a prover, not an LLM judge**.
  - Each NL step x is formalized as AF(x), a sequent ϕ1..ϕn ⊢ ψ in Lean, using its parent steps as context.
  - The step and a perturbed (invalid) version of it are both proved.
- **Failure taxonomy (§3, verbatim):**
  1. **"Error induction":** x is valid, but AF(x) is false.
  2. **"Silent correction":** x is invalid, but AF(x) is true.
  3. **"Semantic drift":** "neither of the previous two cases holds, but the output still does not correspond semantically to x in some way". This one is undetectable by the method, which is sound but incomplete (Limitations).
- **Metrics (§4):** Prove returns ⊤ (proved), ⊥ (negation proved) or ∅.

  ```
  FNR  := #{i | z_i = ⊥} / N                      (error induction)
  FPR  := #{i | z̄_i = ⊤} / N                      (silent correction; z̄ = proof result on Pert(x))
  AFFR := (#{i | AF(x_i)=∅} + #{i | AF(x̄_i)=∅}) / 2N
  UFLB := ½·FNR + ½·FPR + AFFR                    ("Unfaithfulness Lower Bound")
  ```

  - The (z, z̄) pairs are classed as Faithfulness (⊤,⊥), Sycophancy (⊤,⊤), Abstention (⊥,⊥), Inversion (⊥,⊤) or Inconclusive.
  - "A failure of the prover can only decrease UFLB."

### Data and results

- **Data (§5):** ProcessBench error-free chains → GPT-5.2 DAG parse → 12,784 verifiable steps plus 12,784 perturbed steps.
  - Perturbations were effective in 97.8% of cases, with 95.9% human agreement on 219 items.
  - The DAG parse was 94–100% correct on 210 nodes.
- **UFLB results (Fig. 3/4), GSM8K → OmniMATH:**
  - Claude Opus 4.7: 0.09→0.14
  - Gemini 3.1 Pro: 0.08→0.18
  - Goedel: 0.14→0.21
  - Qwen Plus: 0.17→0.35
  - Herald: 0.35→0.50
- **Sycophancy:** the most validity-preserving fine-tuned formalizers are also the most sycophantic. Goedel on GSM8K is 71.2% faithful and 21.4% sycophantic (Fig. 5).
- **Concrete failure modes that make a false step "provable" (App. H.1):**
  - Silently correcting the value.
  - A tautology such as `12 = 12`.
  - Type-coercion collapse.
  - **Hypothesis smuggling**, either through an inconsistent premise set (ex falso) or by putting the claim itself in as a hypothesis.
  - An impossible constraint.
  - Quantifier weakening.
  - **[obs]** All of these except type coercion transfer directly to Z3/FOL.
- **Setup (App. F):** greedy decoding. A formalization that does not compile counts as an autoformalization failure. The prover is DeepSeek-Prover-V2-7B at pass@2, run on both the statement and its negation.
- **Negation rule (App. F.2), verbatim:** "If the theorem includes parameters (e.g., ∀x, P(x)), we construct the negation as ¬(∀x, P(x)); if it is parameter-free, we simply negate the body."
- **Code:** `github.com/Ighina/FaithformBench`.

## 6. TIP / Thinking in Place — thesis arXiv 2609.14850, Ch. 4 (Jin)

### Method

- **Mechanism (§4.2.1):**
  - N special `<reg_i>` "thought register" tokens are added. Each reasoning step starts with one.
  - Reusing a register marks the earlier step that used it as **dead**. Prompt tokens are always live, and N = 16.
  - TIP drops steps the *model* deems no longer needed. **It does not verify or reject steps, re-prefill, or measure leakage.**
- **Masking semantics (§4.1, Fig. 4.3b):** "the runtime evicts the dead step's KV cache blocks: it removes them from the attention kernel, so subsequent tokens never attend over the discarded reasoning".
  - Tokens generated *before* eviction keep KV that was computed while the step was visible.
  - Nothing is recomputed.
- **Implementation (§4.1, §4.2.2):**
  - A custom PyTorch **FlexAttention** runtime with vLLM-style paged KV and a page size of 64.
  - A thought-register table records each step's start and end. A page is kept if any token on it is still live.
  - An "incremental mask cache" means the block mask is rebuilt only when the set of kept pages changes.
  - **Dead tokens on mixed pages stay visible.** Per-token suppression was dropped because throughput fell 305.5→196.1 tok/s (−35.8%).
- **Positions:** **not stated** in Ch. 4. The page-alignment ablation ("a gap of unused positions") implies absolute positions with gaps and no re-indexing.
- **Training (§4.2.3–4.2.4):**
  - A dependency DAG comes from Gemini Flash annotation (prompts in App. B.1). Register assignment is greedy, with Bélády-style eviction.
  - Qwen3-4B is trained with SFT on 5K DeepMath, then 50 GRPO steps on DeepScaleR.
  - Reward: 1 / 0.1 / 0, multiplied by (1 − k̄/L), where k̄ is the mean number of live KV tokens.

### Results

- **Evaluation (§4.3):** AIME24 and AIME25 (60 problems), 16 samples each, temperature 0.6, top-p 0.95.
  - Metrics: accuracy, **live KV** ("mean number of live KV tokens visible to attention during decoding"), throughput, and decode time.
  - TIP vs Dense on AIME24: **20.8% @ 1,586** live tokens vs 14.4% @ 3,858; 308 vs 237 tok/s.
  - StreamingLLM-2048 and Paged-H2O-2048 trail TIP by about 10 points on AIME24.
- **Ablations:** a dependency-based eviction policy beats a rolling policy (17.1 vs 14.6). Using transitive dependents at depth 1–8 gives no consistent gain.
- **Code:** no URL is given.

## 7. Positions Are Not Facts — arXiv 2609.33759 (Zhou et al.)

### Operations and metric

- **Operations (§2, App. A.1/A.3):**
  - **Mask:** a −inf 4-D additive bias on the source positions during question processing and generation. Stored K/V, sequence length and absolute positions are unchanged, and each arm runs on a cloned cache.
  - **Text recompute:** delete the source text and re-prefill.
  - **Rebuild states (selective refresh):** reuse the prefix up to the hidden record, then recompute all later states with it hidden and positions fixed.
  - **Compact rows:** remove the rows "and rotates every later key back by the gap".
  - **Online mask:** the mask is applied after the replacement record has been processed.
  - **K/V zeroing.**
- **Setup:** HF Transformers 5.x with eager attention, bf16, on an H200. Qwen3 is run **with thinking disabled**.
- **Metric (§2, Eq. 1), verbatim:**

  ```
  m(c) = log p(y_current | c) − log p(y_old | c)
  Δm   = m(source mask) − m(control mask)
  ```

  - "Scores sum teacher-forced token log probabilities in nats, without length normalization or EOS."
  - The control mask hides an equal number of tokens at the start of a neutral note.
  - Confidence intervals come from a paired bootstrap with 10,000 draws.

### Findings

- **Key finding (§4, T58/T59): the leakage is stale *later states*, not positions.** Changes are in points relative to the source mask.

  | Model | Rebuild states: historical | Rebuild states: current | Compact rows: historical | Compact rows: current |
  |---|---|---|---|---|
  | Qwen3-4B | −41.3 [−45.7, −37.0] | +7.3 | 0.0 [−2.0, 1.8] | −1.5 |
  | Llama-3.2-3B | −19.8 | +3.3 | +1.2 | +0.5 |
  | Qwen3-32B | −37.5 | +11.5 | −0.2 | −1.7 |

  Compacting rows (fixing the RoPE gap) does nothing, while rebuilding later states removes most of the old information. Recomputing only the first 10–30% of later rows behaves like the plain mask (T60).
- **Leakage probes:**
  - **Masked-only stratum (App. C.4, T55):** the old fact appears only in the masked span. Accuracy drops to near floor; Qwen3-4B goes 53.8%→6.3%.
  - **Retained stratum:** the mask keeps 439/520 historical answers vs 192/520 under recompute, so relations computed while the record was visible persist.
  - **Quotation rule (App. C.5), verbatim:** "A response quotes a masked record when one line cites a superseded record's fact number together with that record's subject and old value." Masking roughly halves quotation (297→148 of 373). Only recompute removes it.
- **Failure modes:**
  - Masking causes **search loops** and token-limit stops. A search loop, verbatim: "reaches the 1,024-token limit without a boxed answer, contains at least three re-check phrases such as 'let me check' or 'wait', and cites one fact number at least three times".
  - Whole-source masks lose complete answers in 6 of 8 models. **Qwen3-8B**: margin +22.81 nats, but only 73.3% complete answers.
  - Control masks can do damage too.
  - Hybrid or recurrent models cannot be masked.
- **Cost (App. D.7/D.8):** for Qwen3-8B at 1K–8K tokens, prefix-reusing recompute costs **2.17–52.89×** a logical mask. On the derived-note task: mask 0.01 ms, selective refresh 25.64 ms, full recompute 41.66 ms (T90).
- **Recommendation:** when the old content must not influence output, "only recomputation removes it".
- **Code:** an anonymized supplement; no URL.

## 8. Aborted but Not Forgotten — arXiv 2608.15939 (Zhang & Yang, HKUST)

### Definitions and procedure

- **Definitions (App. A, verbatim):** the session is (L, K), where L is the committed transcript and K is the attended KV. κ(L) is the state a cold pass re-derives from L. f(K, x) ∈ E is the typed protected effect under greedy decoding.

  ```
  Def 1 (Attended-state rollback integrity): post-abort (L′, K′) has integrity if K′ ≡state κ(L⋆):
    the state the model attends after the abort is the state a cold pass over L⋆ would produce.
  Def 2 (Effect-level rollback consistency): an abort is effect-level rollback-consistent over X if
    f(K′, x) = f(κ(L⋆), x) for every x ∈ X; i.e. the post-abort typed effect equals that of a cold
    restart from the committed transcript on the whole protected-decision domain.
  Prop 1: integrity ⇒ effect consistency.   Prop 2: effect consistency on finite tested D ⊆ X ⇏ integrity.
  ```

- **Audit (§2, Procedure 1, App. B):**
  1. Split each arm's chat-templated tokens at the longest common prefix.
  2. Prefill the prefix and feed only the finalize delta.
  3. **Assert** that the rejected content is absent from the fed delta and that the stale and fresh deltas are **token-identical**.
  4. Compare the typed effect across arms.
- **Arms:**
  - stale: the retained `DynamicCache`.
  - fresh: re-prefill.
  - truncate: `DynamicCache.crop`.
  - checkpoint: a KV snapshot.
  - cold.
  - text-present.
  - **No masking arm, and no interior-span erasure.** The paper calls the latter "the harder problem" (§5).

### Results

- **Results (T1):**
  - The stale KV flips the protected decision in **25/63** cells (7 models × 3 vehicles × 3 strengths).
  - fresh = truncate = checkpoint = cold = **0/63**.
  - stale matches text-present in 63/63 cells.
  - **Length-matched control (T5):** overwriting the carrier with an equal count of neutral tokens (via fast-tokenizer offsets) drops flips 25/25 → **0/25**.
  - **Sampling (App. L):** T = 0.3 gives 180/180 flips, T = 0.7 gives 178/180, and fresh gives 0.
  - **Prompt guard (T2):** "distrust rejected content" only cuts flips from 25/45 to 14/45.
- **Setup (App. H):** HF transformers 4.51.3 / 5.x, explicit `position_ids` and attention mask on the partial-input + `past_key_values` path, fp16 on an H100.
  - The stack survey (T7) finds vLLM APC and SGLang "self-healing" because they are content-addressed, while an HF `DynamicCache` used across turns is exposed.
- **Cost model:** prefill t(n) = 16.17 + 0.0127·n ms.
- **Code:** anonymized artifact; no URL.

## 9. KVEraser — arXiv 2606.17034 (Li et al., Georgia Tech / Meta)

### Method

- **Problem (§1–2):** x = p ⊕ e ⊕ s. The goal is to make decoding behave as if the span e had never appeared.
  - The **suffix KV is contaminated**, because it was computed while attending to e.
  - Exact erasure means re-prefilling s, which costs O(|s|), not O(|e|).
  - Only a *single contiguous span* is handled. Multiple disjoint spans are unstudied, and the span location is assumed to be given (§6).
- **Method (§4.1, Eq. 4):** KV̂ = KV_{1:m−1} ⊕ **KV_steer(x; m, n)** ⊕ KV_{n+1:T}.
  - A length-preserving steering block produced by a LoRA (r16, α32) forward pass over e, conditioned on the prefix.
  - The positions of the retained states stay unchanged.
- **Baselines (§5.3):**
  - **full recompute** (the reference);
  - **delete-and-shift** (drop the span's KV and re-rotate the suffix's RoPE);
  - instruction-only forgetting;
  - suffix repair (recompute 15% of the suffix).
  - **There is no attention-masking baseline.**
- **Leakage measure:** behavioral exact match on tasks where leakage shows up as an error.
  - On NIAH, outputting "A, B" means the erased value A leaked.
  - QA failures are classified as "corrupted-context reliance" (T6), and tool-call failures as "attacker-specified tool" (T7).

### Results

- **Llama-3.1-8B NIAH exact match (T11), 1K→32K:**

  | Method | Exact match |
  |---|---|
  | Delete-and-shift | **0.00→0.03** |
  | Instruction-only | 0.05→0.51 |
  | Suffix repair | 0.22–0.31 |
  | KVEraser | 1.00 |
  | Full recompute | 1.00 |

- **QA (2Wiki / MuSiQue / IIRC):** KVEraser 0.938/0.895/0.942; delete-and-shift 0.789/0.632/0.725.
- **Qwen3-8B:** KVEraser gets NIAH 1.00 and BFCL 0.86 (T10). QA failures out of 822 (T6): delete-and-shift 329, instruction-only 625, KVEraser 94.
- **Cost:** full recompute takes 2.9–4.4× KVEraser's latency on QA and 10.7× on BFCL. Llama NIAH at 32K: 663.79 s vs 31.90 s (T12).
- **Code:** `github.com/Graph-COM/KVEraser`.

---

# Implementation checklist

## A. Data and oracle

- **Loading:** `load_dataset("opendatalab/ProverQA", data_files="dev/hard.json")["train"]` gives 500 items. Fields are `id, context, question, options, answer, reasoning, nl2fol, conclusion_fol`.
- **FOL fragment:** `¬ ∧ ∨ → ⊕ ∀x`, with unary predicates and constant names. ∃ and ↔ are never used.
- **Encoding:** an uninterpreted sort U, a `Function(name, U, Bool)` per predicate, `Xor` for ⊕, and `ForAll` for ∀. A working parser is in `scripts/z3_label_check.py`.
- **Oracle:** use **Z3 over `nl2fol` as the gold oracle**. It agrees with the label on 498/500; flag ids 411 and 473 (gold B, Z3 C).
  - Z3 returned no `unknown` on any of the 1,500 items. Unary predicates with only ∀ form the monadic fragment, which is decidable.
  - **[obs]** So in this setup "unknown" means *not entailed*, not that the solver gave up.

## B. Condition A (baseline) — copy ProverGen exactly

- **Prompt:** use `papers/proverqa_prompt.txt` verbatim: the system message plus the 2-shot `hard_CoT` user template. Fill `[[CONTEXT]]` with `context.strip()`, `[[QUESTION]]` with `question.strip()`, and `[[OPTIONS]]` with `"\n".join(options)`.
- **Decoding:** the repo uses temperature 0 and max_new_tokens 1024.
- **Qwen3 non-thinking (not from the papers):** pass `enable_thinking=False` to the chat template. Log the truncation rate at 1024.
- **Extraction:** the repo method is Python `eval` on the text before the first `\n\n`. That is unsafe, so use a safe equivalent:

  ```python
  # strip ```json fences, try json.loads on the outermost {...}; fallback: last match of
  ANS = re.compile(r'"answer"\s*:\s*"([ABC])"')
  # parse failure => counted wrong (repo behaviour); report parse-error count separately
  ```

- **Reference points (2-shot CoT, hard, ProverQA T2):**

  | Model | Hard accuracy |
  |---|---|
  | Llama3.1-8B | 33.6 |
  | Mistral-7B | 41.8 |
  | GPT-4o | 50.0 |
  | Majority class (B) | 36.6 |

## C. Step format (Conditions B, C, D)

- **Reasoning prompt:** start from the LogicTrack App. D prompt, verbatim:

  ```
  You are a meticulous logician.
  Read the user's given premise and hypothesis carefully, then reason step by step explicitly in a Natural Language Inference (NLI) style, and conclude with \boxed{LABEL}.
  Do not stop reasoning just because the current facts do not prove the claim. Stop only when the claim is settled, or when no unresolved inference path can still settle it.

  Each step in the response stage must follow the format below, which contains three sections: Premises, Assumptions, and Derived Fact:

  **Response Format**
  Step X:
  ##Premises:##
  - [Facts from the input premises or prior derived facts.]
  - [Don't include any user query or hypothesis here.]
  ##Explanation:##
  - [Add linguistic bridges only (e.g., synonyms, lexical equivalences, definitional mappings)]
  - [Never use Assumptions to fill logical gaps. Write None if no assumption is needed]
  ##Derived Fact:##
  - [The derived fact must be fully supported by that step's premises and assumptions.]
  - [Do not speculate about other facts.]

  After your final step, output exactly your answer with \boxed{LABEL}.
  ```

  The paper's own prompt names the middle section both "Assumptions" and "Explanation"; that inconsistency is the paper's and is kept verbatim. The paper says the system prompt also includes a demonstration, but the demonstration text is not given.
- **Recommended adaptation [obs]:** number the context sentences `[P1]…[Pn]` in `nl2fol` order and the steps `[S1]…`. Each step then **cites premises by ID** and adds one line `FOL: <conclusion>` written in ProverQA syntax.
  - This mirrors ProverQA's gold `fact1/fact2/rule/conclusion` blocks.
  - It gives the DAG edges directly, i.e. PARC's Aggregative mapping with no extra LLM call.
- **Vocabulary:** put the problem's predicate and constant list, extracted from `nl2fol`, into the prompt. Otherwise surface-form mismatches such as `well_trained` vs `is_well_trained` produce spurious "unknown" verdicts.
- **Answer format:** LogicTrack's `\boxed{}`. Extraction order: innermost `\boxed{…}` with `\text{}` stripped; then `<answer>…</answer>`; then "the answer is X" in the final sentences; otherwise mark as unanswered.

## D. Per-step Z3 check (C and D)

- **Base theory:** Φ = the gold FOL of the cited `[Pk]` (no formalization needed) ∪ the *verified* FOL of the cited `[Sj]`. Only the step conclusion q is LLM-formalized.
  - **[obs]** This is deterministic, so it replaces LogicTrack's LLM fidelity judge.
- **Checks, in this order:**
  1. **Parse and vocabulary check.** On failure, re-formalize, up to **M = 3** attempts (VeriCoT's vocabulary-retry count, §2.2; LogicTrack does not report its M). Still failing means **untranslatable**.
  2. **Citation check.** Every cited ID must exist, and every cited `[Sj]` must already be verified.
  3. **SAT(Φ):** this guards against ex falso / hypothesis smuggling (FaithformBench H.1).
  4. **Non-vacuity:** reject if ∅ ⊨ q (a tautology). Also reject implication-wrapped goals such as `(A ∧ R) → q`; the goal must be the bare q (the VeriCoT App. A.2.1 pitfall).
  5. **Verdict:** UNSAT(Φ ∧ ¬q) means **entailed** (accept). UNSAT(Φ ∧ q) means **contradicted**. Otherwise **unknown** (not entailed).
- **Mapping to the papers:** this is LogicTrack's R_verify (1 / 0 / α) and VeriCoT's entailed / contradicted / ungrounded. With binary acceptance, θ_step and θ_avg are moot.
- **Secondary log:** also check P ∪ K_verified ⊨ q. It separates citation errors from logic errors, and an unsat core over the full knowledge base gives minimal premises (PARC's minimality condition), which recover edges the model failed to cite.
- **Final answer:**
  - A requires P ⊨ c.
  - B requires P ⊨ ¬c.
  - **C requires that neither holds** (two Z3 calls). Uncertain is about 35% of hard items.
  - FaithformBench's "Inconclusive" is not a failure here.

## E. Retry budget (C)

- **LogicTrack App. A.1:** on a rejected step, re-prompt with the **verified prefix and concise failure feedback** taken from the error log, and regenerate from step t.
  - At most **k = 2 regeneration attempts per step position**. If all fail, **force-forward the candidate with the highest SBR**; for us that means accept it but mark it unverified so it counts in UR.
  - LogicTrack sets no global cap ("repeats until a viable solution is found"). **[obs]** Set one, e.g. at most 12 steps and at most 2×12 regenerations, and log how often it is hit.
- **VeriCoT comparison point:** one post-hoc self-reflection round.

## F. Condition D: KV invalidation

- **Mask:** a 4-D additive −inf bias from every later query to the rejected step's tokens and to all of its **transitive** DAG descendants.
  - Keep the KV tensors, sequence length and **absolute positions, leaving the gap**.
  - Use HF eager/SDPA and a cloned cache per arm (Positions App. A.3; TIP Fig. 4.3b semantics).
  - **Do not compact or re-rotate positions:** compaction changes accuracy by ≤ ±1.7 points (Positions T58).
  - Mask per token. TIP's page-granular eviction leaves dead tokens visible, and TIP is a trained model.
- **Known risk:**
  - Any **non-descendant** step generated during the lag has KV computed while the rejected step was visible. Those stale states carry the content: rebuilding them changes historical answers by −20 to −41 points (Positions T58).
  - KVEraser shows delete-and-shift fails, at 0.00–0.03 NIAH exact match.
  - Aborted's exactness guarantees cover suffix rollback only.
- **Arms to include:**
  1. C: full re-prefill or `crop` from the verified prefix. This is exact; crop, checkpoint and fresh are all 0/63 in Aborted.
  2. D-mask.
  3. **D + selective refresh:** re-prefill the surviving non-descendant steps with the rejected span hidden and positions fixed.
  4. No invalidation (the rejected step stays visible).
  5. Matched control mask: an equal number of neutral tokens.

## G. Leakage and rollback metrics

- **Rollback consistency (Aborted Def. 2), adapted:**
  - Use greedy decoding.
  - The typed effect f is the next step's Z3-verdict-plus-conclusion and the final answer.
  - **Flip** = f(K_D, x) ≠ f(κ(L⋆), x), where κ(L⋆) is a cold prefill of the verified transcript. Feed token-identical deltas and assert that the rejected tokens are absent from them (Procedure 1).
  - Report flips/N. Report Def. 1 (state identity) only as a diagnostic, e.g. the KV L2 distance of the surviving rows against cold.
- **Δm (Positions Eq. 1):** y_old = the rejected step's text or claim; y_current = the accepted replacement step.
  - Compute Δm = m(D-mask) − m(control mask), as summed teacher-forced log-probs in nats with no length normalization and no EOS.
  - Use a paired bootstrap with 10,000 resamples.
- **Quotation leakage, adapted from Positions App. C.5:** a later step **cites or restates the rejected conclusion**, meaning its FOL q is Z3-equivalent to the rejected q, or the rejected q appears among its premises. This is a counted event.
  - The **masked-only** variant counts only claims not entailed by P ∪ K_verified.
- **Termination:** report the rate of EOS vs token-limit stops, the length ratio against C, and the search-loop rule (Positions).
- **Lag:** report all leakage metrics as a function of the lag, measured in tokens or steps between the rejected step and its invalidation.
- **Process metrics (LogicTrack App. B.3):**
  - OA.
  - VR = mean ρ, and UR = 1 − VR.
  - VU = mean(1[correct]·1[ρ = 1]).
  - VWA = mean(ρ·1[correct]).
  - VeriCoT's pass rate, precision and VCAR.
  - PARC's native vs accumulation errors, where an accumulation error is a descendant of a rejected step.
  - TIP-style live KV tokens and throughput for D vs C.

## H. Pre-experiment worth running first [obs]

- **Purpose:** check how faithful the Qwen3-8B formalizer is before trusting the C/D verdicts.
- **Method (FaithformBench protocol on ProverQA):**
  1. Take the gold `reasoning` blocks.
  2. Formalize each `conclusion:`. Its premises are its `fact`/`rule` lines, mapped to `nl2fol` by exact string match. Facts that were derived in earlier blocks have no gold FOL, so use the FOL of the earlier formalized conclusion instead. The conclusion should be entailed.
  3. Formalize a negated perturbation of each conclusion. It should be refuted or not entailed.
- **Report:** FNR, FPR, AFFR and UFLB.
