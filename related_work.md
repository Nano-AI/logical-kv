# Related work: solver-triggered KV invalidation (novelty check, 2026-10-15)

Compiled from five parallel searches. Titles, authors and dates were checked on arXiv/venue pages.
**Not yet done:** BibTeX checked against DBLP. Most 2026 entries are unreviewed arXiv preprints.
Numbers are as reported by each paper (table/section given); re-read the paper before citing a number.

## Coverage matrix

| Proposal component | Already done by | Status |
|---|---|---|
| Turn each step into logic + check with a solver | VeriCoT, Safe, ReasonDiag, VERGE, Loop-invariant feedback | Done (post-hoc) |
| Solver check *during* decoding + backtrack to last verified step | LogicTrack, SymStep, LogicGuide | Done |
| Dependency DAG over steps; errors propagate to dependents | PARC ("accumulation errors"), ReasonDiag, VeryTrace, Graph of Verification | Done (post-hoc) |
| Cascading invalidation via provenance | Doyle JTMS (1979); PACMI, MemTX, ReTree, Planfence | Done (external memory / rebuilt text context) |
| Removing whole reasoning steps from KV during decoding | TIP, Think Clearly, PENCIL, LightThinker, StepKV, ArborKV | Done (efficiency-triggered, not correctness) |
| Mask a span for all future queries | Selective Attention | Done (learned) |
| "Mask-only removes the branch's influence" | — | **Contradicted:** Positions Are Not Facts, Models Take Notes, Aborted but Not Forgotten, KVEraser |
| Solver-triggered, DAG-scoped invalidation of a *live* KV cache, choosing mask / recompute / truncate by cost, with systems eval | **none found** | **Gap (confidence MEDIUM)** |

## A. The three works named in the pitch

| Paper | Link | What it does | Overlap |
|---|---|---|---|
| PACMI: Provenance-Aware Cascading Memory Invalidation for Long-Term LLM Agents (Wang et al., Oct 2026) | arXiv:2610.05732 | Provenance DAG over agent memory records; a 4-state validity lattice cascades invalidation. Dependency edges are annotated, not inferred. Ablation: removing cascade raises errors 3→11, n.s. | Cascade logic; external memory, not KV |
| StepKV: Step-Aware KV Cache Compression for LLM Agents (Feng et al., Aug/Sep 2026) | arXiv:2609.22158 | Map from KV entries to steps; evicts by step utility under a budget. Qwen2.5-7B, Llama3.1-8B | Step-granular KV bookkeeping; efficiency only |
| Resource-Aware Neuro-Symbolic Reasoning for Local SLMs, "VFR-LLM" (Ramírez Ovalle & Alvarez, Jun 2026) | arXiv:2606.27281 | Small LM formalizes the whole problem; solver + local repair driven by solver diagnostics | Small model + solver loop; whole-problem, not per step, no KV |

## B. Solver/verifier-checked steps

| Paper | Venue | Link | Online? | Note |
|---|---|---|---|---|
| **LogicTrack** (Hu et al. 2026) | arXiv | 2609.21492 | **Online** | Z3 after each step; on failure re-prompts with the verified prefix. Llama-3.1-8B 0.4338→0.5765 (T3). No DAG, no KV, no systems eval. **Closest on correctness.** |
| VeriCoT (Feng et al. 2025) | ICLR 2026 | 2511.04662 | Post-hoc | Each step → SMT-LIB, Z3 against a growing premise set |
| SymStep (2026) | arXiv | 2607.23055 | Online | Checks one atomic claim at a time with constraint propagation (puzzles) |
| LogicGuide (Poesia et al. 2023) | TMLR 2024 | 2306.04031 | Online | Constrained decoding keeps steps sound |
| Safe (Liu et al. 2025) | ACL 2025 | 2506.04592 | Post-hoc | Each step → Lean 4; reranks best-of-N |
| VERGE (2026) | arXiv | 2601.20055 | Post-hoc | SMT + minimal correction subsets |
| ReasonDiag, "When the Chain Breaks" (2026) | EuroVis 2026 | 2603.21286 | Post-hoc | Z3 per step + PARC premise tree marks dependents |
| VeryTrace (2026) | arXiv | 2606.24124 | Post-hoc | CoT → DSL with explicit dependencies |
| Deductive Verification (Ling et al. 2023) | NeurIPS 2023 | 2306.03872 | Post-hoc | Steps cite premises (#k), checked by an LLM |
| Logic-LM / SatLM / LINC / Faithful CoT / Proof of Thought | 2023–24 | 2305.12295 / 2305.09656 / 2310.15164 / 2301.13379 / 2409.17270 | Post-hoc | Background: whole-problem formalization |
| Deductive Beam Search; GRACE; Self-Backtracking; Thought Rollback; Thought-ICS | 2023–26 | 2401.17686; 2305.14934; 2502.04404; 2412.19707; 2602.02416 | Online | Step search / rollback without a solver |
| Self-Step Rejection (2026) | arXiv | 2610.05976 | Online | LoRA gate rejects own steps, resamples from prefix |

## C. Step dependency graphs
- **PARC**, Premise-Augmented Reasoning Chains (Mukherjee et al. 2025, arXiv:2502.02362). Builds a premise DAG over steps and defines "accumulation errors": steps that are valid on their own but rest on a bad premise.
- **Graph of Verification** (AAAI 2025, arXiv:2506.12509). Checks claims in topological order of the DAG.
- **ReasonDiag** (above). Precision 0.306 / recall 0.801 on 13 samples (T1), i.e. errors are over-propagated to dependents.

## D. Removing reasoning steps from KV during decoding
| Paper | Venue | Link | Note |
|---|---|---|---|
| **TIP, "Thinking in Place"** (Tian Jin thesis ch. 4, 2026) | arXiv | 2609.14850 | **Closest on mechanism.** Model marks steps dead; runtime evicts their KV pages; trained on step-dependence DAGs. AIME24 20.8% at 1,586 live KV tokens vs dense 14.4% at 3,858 (§4.3–4.4). Per-token "dead-token suppression" cut throughput 305.5→196.1 tok/s, so it was turned off (§4.4.2). No solver, no transitive invalidation |
| Think Clearly | Findings EMNLP 2025 | 2507.08806 | Evicts low-attention chunks mid-generation; accuracy goes up |
| PENCIL | arXiv 2025 | 2503.14337 | Learned rule erases thoughts; recomputes the answer's KV (App. A) |
| LightThinker / InftyThink / ThinKV / R-KV | EMNLP'25 / ICLR'26 / ICLR'26 / NeurIPS'25 | 2502.15589 / 2503.06692 / 2510.01290 / 2505.24133 | Compressing or evicting the reasoning trace |
| ArborKV | ICML 2026 | 2605.22106 | KV for tree-of-thoughts search; lazy rehydration on backtrack |
| Selective Attention | ICLR 2025 | 2410.02703 | Learned masking of earlier tokens for all future queries |
| Multiverse | NeurIPS 2025 | 2506.09991 | Attention masks keep parallel branches isolated (needs training) |
| HEdit, "Correcting in Hindsight" | ICML 2026 poster | icml.cc/virtual/2026/poster/65864 | Edits past KV after a detected error |
| Latent Phase-Shift Rollback | arXiv 2026 | 2604.18567 | Residual-stream detector → KV rollback + steering |
| Declarative Attention | arXiv 2026 | 2609.02737 | KV block masking inside vLLM, relevance-driven |

## E. Does masking remove influence? (leakage / stale KV)
- **Positions Are Not Facts** (arXiv:2609.33759). With masking, answers still match the old record 74–82.3% of the time, against 33.5–60% with delete+recompute (T1). Position compaction alone moved accuracy only −0.2 to +1.2 points (T2).
- **Models Take Notes at Prefill** (arXiv:2606.17107). The span's own KV drives under 1% of the decision; downstream tokens already carry its conclusion.
- **Aborted but Not Forgotten** (arXiv:2608.15939). A rolled-back branch leaks through retained KV. Defines "rollback consistency."
- **KVEraser** (ICML 2026, arXiv:2606.17034). Exact erasure requires recomputing every token after the span (17.6× latency); learned replacement states avoid that.
- **CacheBlend** (EuroSys 2025, 2405.16444), **PatchKV** (2609.26219), **Contiguity, Not Importance** (2609.17983). Selective recompute of high-deviation / "dirty" tokens; scattered recompute inherits staleness from neighbours.
- **Contextual Drag** (2602.04288). Failed attempts left in context cause 10–20% drops; evidence for hiding failures (open problem 1).
- RoPE gaps: mixed evidence. Benign in Positions Are Not Facts T2; repetition loops in SelKV §3.7 (2607.16213); degeneration from non-contiguous compaction in 2511.04686.

## F. Provenance & truth maintenance
Classic (DOIs checked via Crossref):
- Stallman & Sussman 1977, dependency-directed backtracking. AIJ 9(2). doi:10.1016/0004-3702(77)90029-7
- Doyle 1979, A Truth Maintenance System. AIJ 12(3). doi:10.1016/0004-3702(79)90008-0
- de Kleer 1986, An Assumption-Based TMS. AIJ 28(2). doi:10.1016/0004-3702(86)90080-9 (nogoods ≈ "repeatedly failing branch")
- Alchourrón, Gärdenfors & Makinson 1985, AGM revision. JSL 50(2). doi:10.2307/2274239
- Green, Karvounarakis & Tannen 2007, Provenance semirings. PODS. doi:10.1145/1265530.1265535
- Gupta, Mumick & Subrahmanian 1993, DRed / incremental view maintenance. SIGMOD. doi:10.1145/170035.170066
- Buneman, Khanna & Tan 2001, Why and Where provenance. ICDT. doi:10.1007/3-540-44503-X_20

LLM-era: MemTX (2607.23929), ReTree (2608.10676), Planfence (2609.03340), Matrix (2608.12761), Zep (2501.13956), NeuSymMS (2605.17596), agent provenance survey (2606.04990). Belief revision in LMs: Belief-R (EMNLP'24, 2406.19764), AGM-Bench (ICLR'26 workshop), DeltaLogic (2604.02733), DeReLab (EMNLP'26, 2608.30413), Yang & Jia on retraction (2505.16170).

## G. How often translation to logic goes wrong
- VeriCoT T1: only 45.2% of ProofWriter CoTs verified (task accuracy 75.8%); precision 94.1%. Most correct chains are *unverified*, not refuted.
- FaithformBench (2608.10916, Fig. 5): the best autoformalizer turns 21.4% of deliberately broken GSM8K steps into provable statements (false accepts).
- Safe: 72.2% of steps yield valid Lean; 18.6% rated "Poor" (T5).
- Fixing FOLIO/MALLS (EMNLP'26, 2606.02837): ~42% of gold FOL is wrong. Don't use FOLIO as ground truth.
- Logic-LM T3: executable ≠ correct. AR-LSAT executable rate is only 32.6→39.8%.

## H. Benchmarks
- **ProverQA** (2502.06563). 1,500 items; gold `reasoning` + `nl2fol`. Llama-3.1-8B CoT on Hard: 33.6 (T2). **Primary.**
- ProofWriter / CLUTRR. Datalog-friendly secondary sets.
- PrOntoQA. Saturated; steps are rarely wrong (errors are in planning), so there would be little to refute.
- ProcessBench (2412.06559). Expert labels for the first wrong step; math, so hard to formalize. Offline stress test only.

## Recommended reading order
1. TIP (2609.14850): closest mechanism
2. LogicTrack (2609.21492): closest correctness loop; your main baseline
3. Positions Are Not Facts (2609.33759) + Aborted but Not Forgotten (2608.15939): why mask-only is unsound
4. PARC (2502.02362): step DAGs and accumulation errors
5. VeriCoT (2511.04662): per-step SMT formalization recipe
6. CacheBlend (2405.16444) + KVEraser (2606.17034): the recompute middle ground
7. Doyle 1979 + Gupta et al. 1993 (DRed): the framing
8. FaithformBench (2608.10916): formalizer error budget
