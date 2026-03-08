# micro-swift

MicroSwift is a tensor-based lexer that runs entirely on Apple's [MLX](https://github.com/ml-explore/mlx-swift) framework. Instead of the traditional byte-at-a-time loop, every phase of lexing — candidate generation, winner reduction, greedy selection, keyword remapping, and error detection — is expressed as array operations over fixed-size pages of source bytes. A companion Lean 4 formalization proves that the vectorized pipeline produces the same token stream as a simple scalar reference implementation.

## Performance

Benchmarked on Apple Silicon (xcodebuild Release, M3 Max). MLX compiled graph, warm path (5 warmup + 50 measured iterations):

```
Input         CPU (v0)       GPU (MLX)      Speedup
----------------------------------------------------
247 B         198 KB/s       204 KB/s       1.03x
494 B         311 KB/s       387 KB/s       1.24x
988 B         874 KB/s       770 KB/s       0.88x
2.4 KB        1.57 MB/s      1.92 MB/s      1.22x
4.9 KB        2.86 MB/s      3.73 MB/s      1.31x
9.8 KB        5.41 MB/s      7.68 MB/s      1.42x
24 KB         20.8 MB/s      18.7 MB/s      0.90x
49 KB         21.1 MB/s      33.0 MB/s      1.57x
```

GPU throughput scales with page size — at 49 KB pages the MLX path hits **33 MB/s**, 1.57x faster than the CPU baseline. Graph compilation is amortized across pages of the same bucket size.

Run the benchmark yourself:

```bash
xcodebuild -scheme micro-swift-bench -configuration Release -destination 'platform=macOS'
# find the binary in DerivedData and run it, or:
# .build/release/micro-swift-bench  (after swift build -c release)
```

## How the pipeline works

The lexer is **artifact-driven**: a compile-time step (`MicroSwiftLexerGen`) produces a `LexerArtifact` containing byte-class tables, class sets, rule specs, and keyword maps. The runtime (`MicroSwiftTensorCore`) never hard-codes language knowledge — it reads the artifact.

Each page of source bytes flows through seven phases, all expressed as MLX tensor ops:

| Phase | What it does |
|-------|-------------|
| **A. Byte classification** | Map each byte to a class ID via lookup table |
| **B. Candidate generation** | Per-rule candidate lengths for four families: literal, classRun, headTail, prefixed |
| **C. Winner reduction** | Binary-tree reduction picks the best candidate at each position (longest match, then priority, then rule ID) |
| **D. Greedy selection** | Fixed-point iteration selects non-overlapping tokens left-to-right |
| **E. Keyword remap** | Reclassify selected identifiers as keywords when they match the keyword table |
| **F. Coverage mask** | Delta-array + prefix-sum finds uncovered (error) bytes |
| **G. Transport emission** | Pack tokens into a compact row format, filtering whitespace/comments |

## Lean 4 formal verification

The `LeanProofs/` directory contains a Lean 4 + Mathlib v4.24.0 formalization proving that each vectorized phase produces the same result as a straightforward scalar reference. The top-level theorem (`pipeline_equiv` in `Pipeline.lean`) composes phase-level equivalences into a full-pipeline guarantee.

### Proof status

| Module | Phase | Status |
|--------|-------|--------|
| `Reduction.lean` | Winner reduction | Fully proven |
| `Selection.lean` | Greedy selection + fixed-point convergence | Fully proven |
| `Emission.lean` | Coverage mask + error spans | Fully proven |
| `FallbackIntegration.lean` | Fallback merge | Fully proven |
| `CandidateGen.lean` | Literal, classRun (proven); headTail, prefixed | 2 sorry's |
| `KeywordRemap.lean` | Keyword remap | 1 sorry |
| `Pipeline.lean` | Full composition | 2 sorry's (preconditions for remap) |

**5 sorry's remain** across the entire formalization. The core combinatorial machinery — run-length equivalence (`foldr_break_eq`, `vec_runLength_at`), wave-front convergence, coverage bridging — is fully proven. The remaining gaps are in headTail/prefixed candidate generation (which follow the proven classRun pattern) and keyword remap (shift-and-compare mechanics).

### How the proofs work at a glance

Each proof module defines a **scalar reference function** (simple loop) and a **vectorized function** (the tensor-op version) and shows they agree on all inputs:

- **Reduction**: `isBetter` lexicographic comparison is reflexive/transitive; tree fold equals linear fold.
- **Selection**: The mask fixed-point iteration converges (monotone on a finite lattice) and its limit equals the greedy left-to-right scan. Proved via `fixpoint_unique_pointwise` and wave-front locality (`iterStep_prefix_eq`).
- **CandidateGen / classRun**: `cumminRev`-based vectorized run length equals `runLenFrom` (recursive scalar). Core lemma: `foldr_break_eq` — a foldr over break positions equals `i + runLenFrom i`.
- **Emission**: `buildCoverageMask` via delta-array + prefix-sum equals pointwise "is this byte covered?" check.

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
