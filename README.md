# micro-swift

MicroSwift is a page-oriented lexer built around Apple's [MLX](https://github.com/ml-explore/mlx-swift) framework. The fast path evaluates rule candidates, reduces winners, selects non-overlapping tokens, applies keyword remaps, and computes coverage with page-shaped array operations. The repository also contains a Lean 4 formalization of the core page-local algorithms and their scalar reference models.

The implementation is not "MLX only" end to end today. The repo still contains host-side byte classification/materialization code and a dedicated Metal executor for some run families. The Lean proofs are also scoped: they cover the main reduction/selection/remap/coverage machinery and large parts of candidate generation, but they do not yet prove every implementation detail of the shipping Swift pipeline.

## Performance

Benchmarked on Apple Silicon (xcodebuild Release, M3 Max). MLX compiled graph, warm path (5 warmup + 50 measured iterations):

```
Input         CPU (v0)       GPU (MLX)      Speedup
----------------------------------------------------
247 B         196.72 KB/s    2.53 MB/s      12.85x
494 B         433.86 KB/s    5.41 MB/s      12.47x
988 B         960.00 KB/s    11.19 MB/s     11.65x
2 KB          1.57 MB/s      26.78 MB/s     17.04x
4 KB          4.37 MB/s      50.12 MB/s     11.48x
9 KB          8.68 MB/s      93.22 MB/s     10.74x
24 KB         18.55 MB/s     239.75 MB/s    12.92x
49 KB         20.86 MB/s     461.22 MB/s    22.11x
```

GPU throughput scales with page size — at 49 KB pages the MLX path hits **461.22 MB/s**, 22.11x faster than the CPU baseline. Graph compilation is amortized across pages of the same bucket size.

Run the benchmark yourself:

```bash
xcodebuild -scheme micro-swift-bench -configuration Release -destination 'platform=macOS'
# find the binary in DerivedData and run it, or:
# .build/release/micro-swift-bench  (after swift build -c release)
```

## How the pipeline works

The lexer is **artifact-driven**: a compile-time step (`MicroSwiftLexerGen`) produces a `LexerArtifact` containing byte-class tables, class sets, rule specs, and keyword maps. The runtime (`MicroSwiftTensorCore`) never hard-codes language knowledge — it reads the artifact.

At a high level, each page flows through these phases:

| Phase                       | What it does                                                                                              |
| --------------------------- | --------------------------------------------------------------------------------------------------------- |
| **A. Byte classification**  | Map each byte to a class ID via lookup table                                                              |
| **B. Candidate generation** | Per-rule candidate lengths for four families: literal, classRun, headTail, prefixed                       |
| **C. Winner reduction**     | Pick the best candidate at each position: longest match, then smaller priority rank, then smaller rule ID |
| **D. Greedy selection**     | Select non-overlapping tokens left-to-right                                                               |
| **E. Keyword remap**        | Reclassify selected identifiers as keywords when they match the keyword table                             |
| **F. Coverage mask**        | Mark covered bytes and derive unknown/error spans                                                         |
| **G. Transport emission**   | Pack kept tokens into compact rows, optionally filtering skip-mode tokens                                 |

## Runtime today

The runtime is centered on an MLX-compiled page graph in `MicroSwiftTensorCore/FastPathGraph.swift`, but there are important caveats:

- The compiled graph consumes `byteTensor`, `classIDTensor`, and `validMaskTensor`; byte classification is not currently proved in Lean and is not modeled as part of the capstone theorem.
- Literal, prefixed, keyword-remap, and coverage logic have MLX implementations in the fast path.
- The repo still includes a dedicated Metal executor for host-facing `classRun` and `headTail` evaluation.
- The tensor transport path still materializes some data on the host to build final `PageLexResult` values.
- The current compiled graph has fallback merge machinery, but it captures an empty fallback-rule list in the main fast path today.

## Lean 4 formal verification

The `LeanProofs/` directory contains a Lean 4 + Mathlib v4.24.0 formalization (~6,000 lines) of the page-local lexer pipeline. Each proof module defines a **scalar reference function** and a **vector-style model**, then proves they produce the same output. The scalar models mirror the loop-based logic in the Swift runtime; the vector models mirror the MLX tensor operations.

The capstone theorem is `pipeline_equiv` in `Pipeline.lean`. It composes the phase-level equivalences into an end-to-end statement: the vectorized pipeline equals the scalar pipeline for reduction → selection → keyword remap → coverage emission. It assumes `classIDs` are already provided, so byte classification is outside the theorem boundary.

### Swift ↔ Lean correspondence

The diagram below shows how each pipeline phase maps between Swift and Lean. Phases marked **proven** have no `sorry`; phases marked with a sorry count still have proof gaps.

```
               Swift runtime                          Lean formalization
               ─────────────                          ──────────────────

  bytes ──→ [A] Byte classification                   (not modeled)
             │  ByteClasses, classID tables
             ▼
           [B] Candidate generation                   CandidateGen.lean
             │  LiteralExecution.swift        ←──→    literal_eval_equiv     ✓ proven
             │  ClassRunExecution.swift        ←──→    classrun_eval_equiv    ✓ proven
             │  HeadTailExecution.swift        ←──→    headtail_eval_equiv   ✓ proven
             │  PrefixedExecution.swift        ←──→    prefixed_semantic      1 sorry
             ▼                                        RunLenHelpers.lean      ✓ (shared lemmas)
           [C] Winner reduction                       Reduction.lean
             │  WinnerReduction.swift          ←──→    reduction_equiv        ✓ proven
             ▼
           [·] Fallback merge                         FallbackIntegration.lean
             │  WinnerReduction                ←──→    merge_equiv            ✓ proven
             │   .integrateWithFallback
             ▼
           [D] Greedy selection                       Selection.lean
             │  GreedySelector.swift           ←──→    selection_equiv        ✓ proven
             ▼
           [E] Keyword remap                          KeywordRemap.lean
             │  KeywordRemap.swift             ←──→    remap_equiv            1 sorry
             ▼
           [F/G] Coverage + emission                  Emission.lean
             │  CoverageMask.swift             ←──→    coverage_equiv         ✓ proven
             │  TransportEmitter.swift
             ▼
           tokens + errorSpans                        Pipeline.lean
                                                       pipeline_equiv         2 sorry's
                                                       (remap preconditions)
```

The correspondence is "same semantics at a useful abstraction boundary", not "theorem over the exact Swift AST". Key differences between the Lean models and shipped Swift:

- **Selection**: Lean proves a fixed-point/cummax algorithm; Swift uses successor links and pointer jumping. Same greedy semantics, different vectorization strategy.
- **Prefixed**: The Lean model covers the `stopSetID = none` case; the Swift runtime also supports stop-aware prefixed rules.
- **Fallback merge**: Proved in Lean, but the current fast-path graph wires in zero fallback rules, so this code path is not exercised yet.

### Proof status

| Module                     | Swift counterpart                                   | Status           | What it proves                                                                                                                                             |
| -------------------------- | --------------------------------------------------- | ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `RunLenHelpers.lean`       | _(shared by CandidateGen)_                          | **Fully proven** | `foldr_break_eq`, `vec_runLength_at` — vectorized run-length equals recursive scalar                                                                       |
| `CandidateGen.lean`        | `Literal/ClassRun/HeadTail/PrefixedExecution.swift` | **1 sorry**      | Literal, classRun, headTail equivalences proven. Prefixed (`prefixed_semantic`) still open — needs prefix mask + cumminRev body/invalid boundary alignment |
| `Reduction.lean`           | `WinnerReduction.swift`                             | **Fully proven** | `isBetter` lexicographic comparison; tree fold = linear fold over candidates                                                                               |
| `FallbackIntegration.lean` | `WinnerReduction.integrateWithFallback`             | **Fully proven** | Vectorized merge of fast-path + fallback DFA results                                                                                                       |
| `Selection.lean`           | `GreedySelector.swift`                              | **Fully proven** | Fixed-point convergence; `extractSelected_pairs` preserves start/length                                                                                    |
| `KeywordRemap.lean`        | `KeywordRemap.swift`                                | **1 sorry**      | `scalarRemap_preserves_pairs` proven; full `remap_equiv` (vectorized byte matching) still open                                                             |
| `Emission.lean`            | `CoverageMask.swift`, `TransportEmitter.swift`      | **Fully proven** | Delta-array + prefix-sum coverage = pointwise "is this byte covered?"                                                                                      |
| `Pipeline.lean`            | `FastPathGraph.swift`, `LexPageAPI.swift`           | **2 sorry's**    | Composes all phases; two preconditions assumed (`h_bounds`, `h_valid_bytes` — semantic properties that candidates are bounded by page size)                |

**4 `sorry` occurrences remain.** Five of the eight proof modules are fully proven, covering reduction, fallback merge, selection, coverage/emission, and the run-length helper library. The remaining gaps:

1. **`prefixed_semantic`** (CandidateGen) — the most complex candidate family, requiring prefix mask + cumminRev body boundary + shiftLeft lookup equivalence
2. **`remap_equiv`** (KeywordRemap) — vectorized vs. scalar byte matching through shifted tensors
3. **`h_bounds` + `h_valid_bytes`** (Pipeline) — preconditions asserting candidate lengths stay within page bounds; these are semantic properties that are hard to derive from the pipeline structure alone

Build the proofs:

```bash
cd LeanProofs && devenv shell -- lake build
```

## Repository layout

```
Sources/
  MicroSwiftLexerGen/      # Artifact compiler (spec → tables)
  MicroSwiftTensorCore/    # MLX runtime (phases A–G, benchmark harness)
  MicroSwiftFrontend/      # Source preparation, paging
  MicroSwiftCLI/           # CLI entry point
  MicroSwiftBenchRunner/   # Benchmark binary
Tests/                     # Unit, golden, property, differential tests
LeanProofs/                # Lean 4 formalization
Docs/                      # ADRs and milestone specs
Scripts/                   # dev CLI (doctor, verify, seed, mlx-smoke)
```

## Local commands

```bash
./dev doctor       # print toolchain/runtime diagnostics
./dev verify       # format, lint, build, test
./dev mlx-smoke    # run the MLX smoke path
./dev seed dump    # show deterministic seed manifest
```
