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

GPU throughput scales with page size — at 49 KB pages the MLX path hits **461.22 MB/s**, 22.11x faster than the CPU baseline. Even the 9 KB case clears **93.22 MB/s** on the warm path. Graph compilation is amortized across pages of the same bucket size.

Run the benchmark yourself:

```bash
xcodebuild -scheme micro-swift-bench -configuration Release -destination 'platform=macOS'
# find the binary in DerivedData and run it, or:
# .build/release/micro-swift-bench  (after swift build -c release)
```

## How the pipeline works

The lexer is **artifact-driven**: a compile-time step (`MicroSwiftLexerGen`) produces a `LexerArtifact` containing byte-class tables, class sets, rule specs, and keyword maps. The runtime (`MicroSwiftTensorCore`) never hard-codes language knowledge — it reads the artifact.

At a high level, each page flows through these phases:

| Phase | What it does |
|-------|-------------|
| **A. Byte classification** | Map each byte to a class ID via lookup table |
| **B. Candidate generation** | Per-rule candidate lengths for four families: literal, classRun, headTail, prefixed |
| **C. Winner reduction** | Pick the best candidate at each position: longest match, then smaller priority rank, then smaller rule ID |
| **D. Greedy selection** | Select non-overlapping tokens left-to-right |
| **E. Keyword remap** | Reclassify selected identifiers as keywords when they match the keyword table |
| **F. Coverage mask** | Mark covered bytes and derive unknown/error spans |
| **G. Transport emission** | Pack kept tokens into compact rows, optionally filtering skip-mode tokens |

## Runtime today

The runtime is centered on an MLX-compiled page graph in `MicroSwiftTensorCore/FastPathGraph.swift`, but there are important caveats:

- The compiled graph consumes `byteTensor`, `classIDTensor`, and `validMaskTensor`; byte classification is not currently proved in Lean and is not modeled as part of the capstone theorem.
- Literal, prefixed, keyword-remap, and coverage logic have MLX implementations in the fast path.
- The repo still includes a dedicated Metal executor for host-facing `classRun` and `headTail` evaluation.
- The tensor transport path still materializes some data on the host to build final `PageLexResult` values.
- The current compiled graph has fallback merge machinery, but it captures an empty fallback-rule list in the main fast path today.

## Lean 4 formal verification

The `LeanProofs/` directory contains a Lean 4 + Mathlib v4.24.0 formalization of the page-local lexer pipeline. Each proof module introduces a scalar reference function and a vector-style model, then proves equivalence for that phase or sub-phase.

The current top-level theorem is `pipeline_equiv` in `Pipeline.lean`. It proves equivalence between the Lean scalar pipeline and the Lean vectorized pipeline under explicit preconditions, but its scope is narrower than "the full Swift lexer from raw bytes":

- It assumes `classIDs` are already provided, so byte classification is outside the theorem.
- Its candidate-generation stage currently reuses the scalar generator in the capstone pipeline while the remaining candidate-generation proofs are being finished.
- The remaining proof gaps are concentrated in head-tail/prefixed candidate generation and keyword remap preconditions.

### Proof status

| Module | Phase | Status |
|--------|-------|--------|
| `Reduction.lean` | Winner reduction | Fully proven |
| `Selection.lean` | Greedy selection model | Fully proven |
| `Emission.lean` | Coverage mask + error spans | Fully proven |
| `FallbackIntegration.lean` | Fallback merge | Fully proven |
| `CandidateGen.lean` | Literal, classRun (proven); headTail, prefixed | 2 sorry's |
| `KeywordRemap.lean` | Keyword remap | 1 sorry |
| `Pipeline.lean` | Full composition | 2 sorry's (preconditions for remap) |

**5 `sorry` occurrences remain** across the current formalization. The core combinatorial machinery — run-length equivalence (`foldr_break_eq`, `vec_runLength_at`), reduction tie-breaking, selection correctness, and coverage bridging — is proven. The remaining gaps are:

- `CandidateGen.lean`: head-tail equivalence
- `CandidateGen.lean`: prefixed equivalence
- `KeywordRemap.lean`: remap equivalence
- `Pipeline.lean`: two proof obligations passed into remap equivalence

One additional caveat: the prefixed proof currently covers the `stopSetID = none` case, while the Swift runtime supports stop-aware prefixed rules.

### How the proofs work at a glance

Each proof module defines a **scalar reference function** and a **vector-style model** and shows they agree on all inputs in that model:

- **Reduction**: `isBetter` lexicographic comparison is reflexive/transitive; tree fold equals linear fold.
- **Selection**: The Lean model proves a fixed-point/cummax selection algorithm equivalent to the scalar greedy scan.
- **CandidateGen / classRun**: `cumminRev`-based vectorized run length equals `runLenFrom` (recursive scalar). Core lemma: `foldr_break_eq` — a foldr over break positions equals `i + runLenFrom i`.
- **Emission**: `buildCoverageMask` via delta-array + prefix-sum equals pointwise "is this byte covered?" check.

## Swift ↔ Lean correspondence

The Lean files are intentionally named after the Swift runtime phases, but the correspondence is "same semantics at a useful abstraction boundary", not "theorem over the exact production code AST":

| Lean module | Main Swift counterpart | Notes |
|------------|------------------------|-------|
| `CandidateGen.lean` | `LiteralExecution.swift`, `ClassRunExecution.swift`, `HeadTailExecution.swift`, `PrefixedExecution.swift` | Lean models the four candidate families. Literal and class-run are proved; head-tail and prefixed still have proof gaps. |
| `Reduction.lean` | `WinnerReduction.swift` | Matches the shipped tie-break order exactly: longer length, then smaller priority rank, then smaller rule ID. |
| `Selection.lean` | `GreedySelector.swift` | Same semantic target, different current vector algorithm: Lean models fixed-point/cummax selection, while Swift uses successor links and pointer jumping. |
| `KeywordRemap.lean` | `KeywordRemap.swift`, `TransportEmitter.applyKeywordRemap` | Lean models both sparse scalar remap and page-aligned vector remap. One proof gap remains. |
| `Emission.lean` | `CoverageMask.swift`, `TransportEmitter.swift` | Covers coverage, unknown-byte detection, and error-span construction. |
| `FallbackIntegration.lean` | `WinnerReduction.integrateWithFallback`, `FastPathGraph.mergeFastAndFallback` | The merge logic is proved, although the main fast-path graph currently wires in zero fallback rules. |
| `Pipeline.lean` | `LexPageAPI.swift`, `FastPathGraph.swift`, `TransportEmitter.swift` | Capstone composition theorem over the Lean models, not a proof of the exact shipping end-to-end Swift entry point. |

## Current caveats

- The README should be read as "MLX-centered fast path", not "every byte of the runtime is MLX".
- The Lean capstone theorem does not currently prove byte classification.
- The Lean selection proof targets the same greedy semantics as Swift, but not the exact successor-link/pointer-jumping algorithm currently shipped.
- The Lean prefixed proof currently covers the no-stop-boundary case only.
- The compiled fast-path graph includes keyword remap, but the public `materialize` call passes empty remap tables because the selected token kinds have already been remapped inside the graph.
- The current fast-path graph allocates no fallback rules, so the proved fallback merge logic is present but not meaningfully exercised in that path yet.

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
