Here is the full document with those changes applied.

---

# Micro-Swift MLX-Swift Compiler

## Engineering Architecture and Milestone Plan

**Swift-only, regex-generated lexer, deterministic pipeline, span-precise diagnostics, WASM backend, Point-Free-style CLI/tooling, local-first verification**

**Document status:** Draft v0.3

## 1. Executive summary

This project builds a Swift-only prototype compiler for Micro-Swift on top of MLX-Swift, with the compiler core expressed as bulk array and tensor operations rather than pointer-heavy recursive structures. The design remains intentionally narrow: the language subset is constrained so lexing, structural indexing, parsing, semantic analysis, optimization, and WebAssembly emission can be represented as scans, segmented reductions, gathers, compaction, and a small number of custom Metal kernels when stock MLX operations are not enough.

The performance claim remains deliberately narrow and scientifically defensible. The goal is not to beat `swiftc` on all of Swift. The goal is to show that, on very large subset-conforming single-file workloads, the prototype can achieve a clear **steady-state front-end throughput** win for lexing, parsing, name/type analysis, and Wasm emission relative to a fixed `swiftc` baseline on equivalent source.

The lexer is declarative. A regular-expression specification is compiled ahead of time into a deterministic tensor-lexing plan: byte-class tables, run matchers, literal matchers, and optional DFA-style fallback kernels. Determinism and exact span attribution are first-class requirements across every phase.

One concrete change in this revision is the tooling and CLI philosophy for Milestone 0. The local developer lane now follows the Point-Free style used in `pfw`: the root CLI is an `AsyncParsableCommand`; environment interactions are modeled as injected dependencies; command tests parse the root command directly, capture stdout, and snapshot it; base test suites install default dependencies and snapshot policy; and the formatting/linting lane uses the toolchain formatter/linter rather than a SwiftLint plugin dependency. MLX still requires an Xcode/`xcodebuild` lane for Metal-capable command-line binaries, and the MLX examples repo uses an `mlx-run` wrapper for that execution path. ([GitHub][1])

---

## 2. Research basis and design lineage

The conceptual lineage remains the same.

The compiler architecture is inspired by data-parallel compiler construction: choose representations where the important transformations are naturally scans, reductions, segment operations, joins, and compactions rather than mutable tree walks. Structural parsing is treated as a prefix-scan problem before it is treated as an AST problem. Bracket structure, block regions, statement boundaries, and precedence relations are derived from dense tapes and relational tables. Regex generation is treated as an automata-compilation problem whose runtime evaluation is then specialized into bulk tensor kernels.

This document therefore keeps three commitments:

1. **Represent structure as dense data first.**
2. **Make semantic propagation table-driven and scan-friendly.**
3. **Design the benchmark around giant single-file inputs where bulk-parallel structure extraction has a fair chance to win.**

---

## 3. Scope, goals, non-goals, and success criteria

### 3.1 Primary goal

Build a Swift package and CLI that compile Micro-Swift source to WebAssembly, with the compiler core implemented in MLX-Swift, and demonstrate that on enormous single-file workloads the prototype can outperform a fixed `swiftc` baseline in steady-state throughput for the subset under test.

### 3.2 Concrete success criteria

The prototype is successful when all of the following are true:

1. A regex specification generates the lexer.
2. Lexing, structural indexing, parsing, name resolution, typechecking, and Wasm emission are driven by tensor or array kernels in MLX-Swift, with only thin host orchestration.
3. Outputs are deterministic across repeated runs.
4. Diagnostics for lexical, parse, and type errors are span-precise.
5. A benchmark suite includes at least one giant deterministic single source file specifically designed to stress the data-parallel front end.
6. The benchmark report separates cold-start, steady-state, and error-path performance.
7. The steady-state benchmark shows a clear speed advantage over the chosen `swiftc` baseline on at least one giant-file workload.

### 3.3 Non-goals

This prototype does not attempt to beat `swiftc` on general Swift, on small files, on semantic features outside Micro-Swift, or on whole-program optimization quality. The comparison is deliberately limited to a constrained subset and to workloads where giant-input data parallelism is a fair test.

### 3.4 Implementation constraints

The implementation is Swift-only. No Python prototype is part of the plan. MLX-Swift is the primary runtime. If a kernel is awkward in stock MLX ops but still naturally data-parallel, the allowed escape hatch is MLXFast custom Metal kernels embedded in Swift.

The non-MLX support stack is intentionally small and follows the same style as Point-Free’s `pfw` CLI: `swift-argument-parser` for CLI structure, `swift-dependencies` for effect injection, `swift-snapshot-testing` for CLI and golden snapshots, and `swift-custom-dump` for deterministic textual rendering of structured state. `pfw`’s package and tests use exactly that combination: `ArgumentParser`, `Dependencies`, `CustomDump`, and inline snapshot testing, with command tests running through `parseAsRoot` and suite-wide dependency injection. ([GitHub][2])

---

## 4. System overview

The system is organized into seven major modules.

**MicroSwiftSpec** contains the language subset specification, token regex specification, type rules, operator table, benchmark seed manifest, and diagnostic schema.

**MicroSwiftLexerGen** compiles the regex specification into deterministic lexer artifacts: byte equivalence classes, literal matcher tables, run-token rules, optional DFA fallback tables, skip-token policy, and priority metadata.

**MicroSwiftTensorCore** is the MLX-Swift kernel layer. It owns the source tape representation, scans, segmented compaction, prefix-summary operations, block summaries for chunked processing, compaction kernels, and custom Metal kernels where necessary.

**MicroSwiftFrontend** builds the token tape, structural indices, relational IR tables, symbol tables, expression parse structures, and type/proof tables.

**MicroSwiftWasm** lowers validated IR to deterministic WebAssembly binaries.

**MicroSwiftBench** owns deterministic corpus manifests, later benchmark generators, result schemas, and benchmark harness glue.

**MicroSwiftCLI** wraps everything as a command-line tool. In this revision, it is explicitly designed in a Point-Free style: an `AsyncParsableCommand` root, subcommands for tooling and compiler phases, dependencies injected through `swift-dependencies`, and command surfaces written so they can be parsed and executed directly inside tests without spawning subprocesses. This mirrors the structure used by `pfw`, whose root command is an `AsyncParsableCommand` and whose source tree isolates environment-facing dependencies into a dedicated `Dependencies` folder backed by `DependencyKey` / `DependencyValues`. ([GitHub][1])

---

## 5. Core data model

The compiler uses a struct-of-arrays representation throughout.

### 5.1 Source and spans

`SourceFile` is represented as:

- `fileID: UInt32`
- `bytes: MLXArray<UInt8>`
- `lineBreakMask: MLXArray<Bool>`
- `lineID: MLXArray<Int32>` from an exclusive cumulative sum
- `lineStartOffsets: MLXArray<Int64>` from compaction

Every span is stored as:

- `fileID: UInt32`
- `startByte: Int64`
- `endByte: Int64`

Line/column lookup is pure data:

- `line = lineID[startByte]`
- `column = startByte - lineStartOffsets[line]`

### 5.2 Token tape

Each token row stores:

- `kind: UInt16`
- `flags: UInt16`
- `startByte: Int64`
- `endByte: Int64`
- `payloadA: Int32`
- `payloadB: Int32`
- `primarySpanID: Int32`

For literals, payload fields hold parsed numeric value or a literal-class code. For identifiers, payload fields hold symbol hash fragments or later intern ids.

### 5.3 Structural indices

Derived arrays include:

- `parenDelta`, `braceDelta`
- `parenDepth`, `braceDepth`
- `stmtStartMask`, `stmtID`
- `scopeID`
- `pageID`
- `matchParen`, `matchBrace`

### 5.4 Relational IR

There is no pointer AST. Instead, there are tables for:

- functions
- declarations
- statements
- expressions
- call arguments
- symbols
- diagnostics
- codegen rows

Every IR row stores an origin span and, when useful, one or two related spans for notes or secondary highlights.

### 5.5 Diagnostics table

Diagnostics are rows, not ad hoc strings:

- `diagCode`
- `phase`
- `severity`
- `primarySpanID`
- `secondarySpanID`
- `payloadStart`
- `payloadLen`

The textual message is generated at the end from code plus payload. Diagnostics are stably sorted by `(fileID, startByte, endByte, diagCode)`.

---

## 6. Regex-generated tensor lexer

### 6.1 Declarative lexer specification

The lexer is defined by a prioritized regex specification over bytes and byte classes. The supported rule families are intentionally constrained:

- fixed literals and operators
- character-class runs such as identifiers and integers
- whitespace runs
- line comments
- bounded local-window patterns
- a fallback DFA fragment for residual permitted cases

Keywords such as `func`, `let`, `return`, `if`, `else`, `true`, and `false` are handled as a deterministic remap of identifier tokens, not as separate hot-path regexes.

### 6.2 Build-time regex compilation

The regex compiler runs at build time. Its pipeline is:

1. Parse regex rules into a canonical AST.
2. Normalize unions, concatenations, and classes.
3. Partition the alphabet into byte equivalence classes.
4. Lower each rule into one of:
   - literal matcher
   - run matcher
   - local-window matcher
   - fallback automaton

5. Assign stable rule ids and priority order.
6. Emit deterministic tables as Swift source or package resources.

### 6.3 Runtime lexer architecture

At runtime, lexing runs in four subphases.

**Phase A: byte classification.**
Every byte is mapped to a compact equivalence-class id.

**Phase B: rule-family kernels.**
Each rule family is evaluated with a specialized kernel:

- fixed literals/operators use shifted equality conjunctions
- character-class runs use boundary masks plus run-length kernels
- line comments use start detection plus next-newline search
- whitespace uses run segmentation
- fallback DFA rules use a block-local state machine if needed

**Phase C: longest-match / priority resolution.**
For every candidate token start, compute the best matching rule and match length.

**Phase D: token compaction.**
Selected token starts are compacted into the token tape, skip tokens are dropped, identifier keywords are remapped, and error tokens are emitted for unmatched bytes.

### 6.4 Determinism in the lexer

The lexer must be bitwise deterministic:

- canonical regex normalization
- stable rule numbering
- stable byte-class numbering
- stable tie-breaking: longest match, then rule priority, then earliest rule id
- stable compaction order by source position

### 6.5 Giant-file chunking

The lexer must support extremely large source files. The design therefore includes paged lexing, ideally newline-aligned. Since v0 excludes multiline strings and block comments, safe boundary management is much simpler than in a general language.

Each page produces:

- token count
- line count
- trailing lexer state summary
- byte offset delta

A prefix scan of page summaries yields the global base offsets used to concatenate per-page token outputs.

---

## 7. Parsing architecture

### 7.1 Structural indexing first

As in scan-based parsing, structure comes before tree shape. The first parse pass computes:

- brace depth
- paren depth
- statement starts
- scope ids
- top-level function boundaries
- `if` / `else` block boundaries

This pass is almost entirely scans, masks, and compaction. It also produces early parse diagnostics such as unmatched delimiters and malformed block boundaries.

### 7.2 Relational, not object-based

The parse product is a relational IR, not an object graph. Statements, declarations, functions, and expressions are rows in dense tables. Parent/child relations are integer ids.

### 7.3 Expression parsing: Option A

This document keeps Option A. Expressions are parsed with a precedence-driven tree-construction algorithm:

1. Extract the operator tape for each expression span.
2. Compute precedence and associativity ranks.
3. Use a previous-smaller-or-equal / nearest-dominating construction to build a Cartesian-tree-like parent relation over operators.
4. Attach operands between operators.
5. Emit expression rows with stable ids and exact spans.

### 7.4 Parse spans

Every expression row stores:

- full expression span
- operator span
- left child span
- right child span

That is necessary for precise diagnostics at operator sites and subexpressions.

---

## 8. Name resolution and type system

### 8.1 Symbol interning

Identifiers are interned deterministically. The stable key is:

1. hash of bytes
2. lexeme length
3. lexeme bytes
4. first occurrence position

### 8.2 SSA-friendly resolution

Because Micro-Swift is syntactically SSA via `let`-only declarations, name resolution is simpler than in general Swift. The compiler resolves:

- top-level functions
- parameters
- local lets inside blocks
- references in expressions and calls

### 8.3 Bidirectional typing as tensor propagation

The subset is engineered so inference is mostly contextual propagation plus local checking. Expected types originate at:

- explicit `let` annotations
- parameter types
- function return types
- `if` conditions
- built-in function signatures

Those expectations are propagated through expression regions and reconciled with actual operator/call results.

### 8.4 Literal concretization

Integer literals are initially untyped. They are concretized by context. For example:

- in `let x: UInt8 = 10 + 5`, both literals receive the expected `UInt8` context
- range checks ensure values lie in `0...255`
- operator rules validate `UInt8 + UInt8 -> UInt8`

### 8.5 Type rules as dense tables

The typechecker uses dense rule tables rather than ad hoc host code:

- arithmetic rules
- comparison rules
- call signature rules
- return rules
- conditional rules

Each expression row computes `actualType`, `expectedType`, and `typeOK`. Whole-program success is a reduction over `typeOK`.

---

## 9. Span-based error attribution

This remains a first-class architecture requirement.

### 9.1 Lexing errors

Lex errors produce:

- offending byte span
- surrounding line span
- expected rule-family summary
- optional note span if the error is due to an earlier malformed boundary

### 9.2 Parse errors

Parse errors produce:

- primary span at the malformed token or unmatched delimiter
- secondary span at the matching or expected structural partner if one exists
- payload naming the structural context

### 9.3 Type errors

Type errors produce:

- primary span at the smallest offending subtree
- secondary span at the declaration, parameter, or operator that induced the expected type
- payload naming actual and expected types

### 9.4 Backend errors

Backend errors should still be attributable to source spans when possible:

- unsupported construct reaching codegen
- impossible type lane in lowering
- determinism or consistency violation in IR

### 9.5 Deterministic diagnostics

Diagnostics are emitted in stable source order and formatted deterministically. Later golden tests will assert both the structured rows and the rendered text.

---

## 10. Determinism policy

Determinism is a formal requirement.

The following must be deterministic:

- regex normalization and state numbering
- byte equivalence-class numbering
- symbol interning
- row compaction order
- parser parent selection on precedence ties
- diagnostic ordering
- WebAssembly section ordering
- benchmark seed derivation
- benchmark corpus generation

Any sorting must specify a total order. Any hashing must specify collision resolution by a stable lexical order. Any compaction pass must preserve source order.

---

## 11. WebAssembly backend

WebAssembly is the only backend in this document.

### 11.1 Type lowering

For v0, Micro-Swift primitive types lower to Wasm `i32` lanes:

- `Int -> i32`
- `UInt8 -> i32` with compile-time range discipline and explicit masking where needed
- `Bool -> i32` with `0/1`

### 11.2 Control flow lowering

- `if/else` lowers to Wasm structured control
- function calls lower to direct function indices
- `print` lowers to an imported host function

### 11.3 Deterministic emission

The emitter fixes:

- type section order
- import section order
- function section order
- code section order
- local declaration order
- constant encoding rules

### 11.4 Correctness strategy

Correctness is checked by running emitted Wasm in a conforming runtime and comparing observable behavior against the reference Swift program on the same subset.

---

## 12. Benchmark strategy

### 12.1 Benchmark philosophy

The benchmark claim must remain narrow and honest:

> On giant single-file programs written in the Micro-Swift subset, the MLX-Swift prototype achieves higher steady-state front-end throughput than the chosen `swiftc` baseline.

### 12.2 Benchmark corpora

The repo should ship deterministic generators for at least four giant-file families.

**Monster-Lex**
A huge file dominated by identifiers, integers, operators, comments, and whitespace.

**Monster-Expr**
A huge file with millions of expression statements and declarations stressing precedence parsing and literal concretization.

**Monster-Semantic**
A huge file with many top-level functions, large call volumes, and type-heavy declarations stressing name resolution and type propagation.

**Monster-Error**
A huge mostly-valid file with sparse seeded lexical, parse, and type errors at deterministic positions.

### 12.3 Single-file requirement

At least one benchmark must be a single enormous source file, not merely a directory of many files.

### 12.4 Measurement modes

Every benchmark is run in three modes:

- cold-start
- warm steady-state
- error path

### 12.5 Metrics

Primary metrics:

- bytes/sec
- tokens/sec
- expressions/sec
- end-to-end compile wall time
- peak memory
- diagnostics/sec on error corpora

Secondary metrics:

- lex-only time
- parse-only incremental time
- typecheck-only incremental time
- Wasm emission time
- baseline comparison ratio

### 12.6 Baselines

The primary baseline remains a fixed `swiftc` front-end-oriented run on the same subset-conforming source. A secondary baseline can use a fuller compile path, but it must be labeled accordingly.

### 12.7 Benchmark risks

If the prototype is not faster on the giant-file benchmark, the write-up must say why. Likely causes include:

- cold-start compilation overhead not amortized
- too much host/device synchronization
- poor page-size tuning
- compaction kernels too expensive
- insufficient kernel reuse

---

## 13. Tooling, CLI architecture, formatting, linting, and tests

This section changes substantially in this revision.

The project remains a Swift Package, but the CLI and test surface now explicitly follow a Point-Free-style pattern. `pfw` uses `swift-argument-parser` for an `AsyncParsableCommand` root command; isolates environment-facing services behind dependency clients registered with `DependencyKey` and surfaced through `DependencyValues`; and tests commands by parsing the root command directly, running it in-process, capturing stdout, and asserting inline snapshots. Its test suites use Swift Testing traits for serialization, default dependency overrides, and snapshot policy. That is the pattern adopted here for `MicroSwiftCLI`. ([GitHub][1])

### 13.1 CLI architecture

`MicroSwiftCLI` should be a single executable target rooted at an `AsyncParsableCommand`. Subcommands should include at least:

- `doctor`
- `seed dump`
- `mlx-smoke`
- `lex`
- `parse`
- `typecheck`
- `emit-wasm`
- `bench`

Each subcommand should be thin. Argument parsing lives in the CLI type; orchestration lives in small adapters; compiler logic stays in pure modules.

### 13.2 Dependency injection

The CLI should not reach directly into `FileManager`, environment variables, clocks, UUID generation, subprocess runners, or MLX runtime discovery. Those should be modeled as dependency clients in the same style as `pfw`’s `fileSystem`, `pointFreeServer`, `openInBrowser`, and related clients. The pattern is: protocol or value client, `DependencyKey`, then `DependencyValues` accessors. That keeps the CLI shell testable and deterministic. ([GitHub][3])

For this repo, the minimum dependency set in M0 should be:

- file system
- environment reader
- process runner
- clock
- UUID generator
- stdout/stderr writer abstraction
- MLX runtime locator
- Xcodebuild runner

### 13.3 Snapshot testing strategy

Use Point-Free’s snapshot stack for golden verification.

For command output:

- parse the root command directly in tests
- execute it in-process
- capture stdout/stderr
- assert inline snapshots for small human-readable outputs such as `doctor`, `--help`, and user-facing diagnostics

For larger artifacts:

- use file snapshots or structured snapshots
- snapshot token tapes, IR dumps, diagnostics, and benchmark manifests as text

`swift-snapshot-testing` supports textual snapshots, and `pfw` uses inline snapshots plus suite-wide snapshot recording defaults. ([GitHub][4])

### 13.4 Custom dump strategy

Use `swift-custom-dump` for deterministic textual rendering of structured compiler state. It produces more readable, Swift-like output than `dump`, automatically orders dictionary keys, and provides small textual diffs. That makes it a good fit for IR dumps, diagnostics tables, benchmark manifests, and relational proof tables. ([GitHub][5])

### 13.5 Formatting and linting

There is no `SwiftLintPlugins` dependency in this plan and no external SwiftLint plugin lane.

The formatting/linting path is the toolchain formatter/linter:

- `swift format` for formatting
- `swift format lint --strict` for linting

The `swift-format` project documents the `lint` subcommand directly, and current discoverability discussion around `swift lint` makes clear that the actual built-in path is nested under `swift format lint`. So the repo should expose this as `./dev lint`, but implement it with the toolchain linter rather than with SwiftLint plugins. ([GitHub][6])

### 13.6 Verification philosophy

M0 is **local-first**, not CI-gated.

The canonical verification entrypoint is:

```sh
./dev verify
```

This command runs:

1. format check
2. lint
3. build
4. unit tests
5. snapshot tests
6. MLX smoke test
7. docs drift checks for canonical commands

This verification path must also be installed as a pre-commit hook.

### 13.7 Pre-commit hook policy

Ship a checked-in hook at:

```text
.githooks/pre-commit
```

and a bootstrap command:

```sh
./dev install-hooks
```

that runs:

```sh
git config core.hooksPath .githooks
```

The pre-commit hook should execute `./dev verify`. Under the constitution, that means the whole local gate must stay within the latency budget. If the gate exceeds the target budget, that is a design defect to fix, not a reason to weaken verification.

### 13.8 MLX local execution path

MLX remains the one place where the repo cannot pretend SwiftPM command-line builds are enough. The MLX Swift README explicitly notes that command-line SwiftPM cannot build the Metal shaders and that `xcodebuild` is the command-line build path for that case. The MLX Swift examples repo’s `mlx-run` wrapper uses Xcode command-line tools to locate and run those built binaries. M0 should adopt that exact local pattern. ([GitHub][7])

---

## 14. Detailed milestone plan

### Milestone 0 — Repository, toolchain, runtime, local verification, and Point-Free CLI foundation

**Goal:** establish a Swift-only repo that can build, test, lint, format, and run MLX-Swift command-line programs deterministically on a local machine, with one canonical verification path and a pre-commit hook that enforces it.

This milestone is no longer framed around CI. It is framed around a fresh clone being able to prove correctness locally.

#### 14.0.1 Core architectural decisions

M0 locks in the following choices:

- one root Swift package as the source of truth
- one executable CLI target rooted at `AsyncParsableCommand`
- toolchain formatting and linting through `swift format` / `swift format lint`
- dependency injection through `swift-dependencies`
- snapshot testing and inline snapshots for CLI and golden outputs
- MLX command-line execution through an Xcode build plus `mlx-run` wrapper
- pre-commit hook as the enforcement point for local verification

#### 14.0.2 Repository layout

```text
/
├─ Package.swift
├─ Package.resolved
├─ .swift-version
├─ .swift-format
├─ README.md
├─ Docs/
│  ├─ adr/
│  │  ├─ 0001-package-only-repo.md
│  │  ├─ 0002-mlx-runtime-wrapper.md
│  │  └─ 0003-local-first-verification.md
│  └─ milestones/
│     └─ 0-foundation.md
├─ Config/
│  ├─ bench-seeds.json
│  └─ toolchain.json
├─ Scripts/
│  ├─ dev
│  ├─ mlx-run
│  ├─ doctor.sh
│  ├─ verify.sh
│  └─ lib/
│     └─ common.sh
├─ .githooks/
│  └─ pre-commit
├─ Sources/
│  ├─ MicroSwiftSpec/
│  ├─ MicroSwiftLexerGen/
│  ├─ MicroSwiftTensorCore/
│  ├─ MicroSwiftFrontend/
│  ├─ MicroSwiftWasm/
│  ├─ MicroSwiftBench/
│  └─ MicroSwiftCLI/
├─ Tests/
│  ├─ MicroSwiftSpecTests/
│  ├─ MicroSwiftLexerGenTests/
│  ├─ MicroSwiftTensorCoreTests/
│  ├─ MicroSwiftFrontendTests/
│  ├─ MicroSwiftWasmTests/
│  ├─ MicroSwiftBenchTests/
│  └─ MicroSwiftCLITests/
│     ├─ Internal/
│     └─ Snapshots/
└─ Artifacts/
   └─ snapshots/
```

#### 14.0.3 Package and dependency policy

Package dependencies in M0 should be minimal and explicit:

- `mlx-swift`
- `swift-argument-parser`
- `swift-dependencies`
- `swift-custom-dump`
- `swift-snapshot-testing`

No SwiftLint plugin package. No auxiliary node/python/ruby tooling. No CI-only dependencies. `pfw`’s package is a useful model here: executable target plus test target, with `ArgumentParser`, `Dependencies`, `CustomDump`, and inline snapshot testing in the support stack. ([GitHub][8])

#### 14.0.4 CLI surface in M0

The initial CLI should expose only a minimal verified surface:

- `micro-swift doctor`
- `micro-swift seed dump`
- `micro-swift mlx-smoke`

The root command should be `AsyncParsableCommand`. That matches both the intended future async nature of MLX and the concrete shape used in `pfw`. ([GitHub][1])

#### 14.0.5 Dependency clients in M0

M0 should define dependency clients for:

- `fileSystem`
- `env`
- `clock`
- `uuid`
- `process`
- `mlxRuntime`
- `stdout`
- `stderr`

Each client gets:

- protocol or callable client type
- `DependencyKey`
- `DependencyValues` accessor
- live implementation
- test implementation

The design target is the same pattern visible in `pfw`’s dependency clients and test overrides. ([GitHub][3])

#### 14.0.6 Local verification commands

`Scripts/dev` is the only user-facing orchestration entrypoint. It should expose:

```sh
./dev doctor
./dev format
./dev lint
./dev build
./dev test
./dev mlx-smoke
./dev verify
./dev install-hooks
./dev run micro-swift <args...>
```

Command meanings:

- `doctor`: print toolchain/runtime diagnosis
- `format`: run toolchain formatter in write mode
- `lint`: run `swift format lint --strict`
- `build`: `swift build`
- `test`: `swift test`
- `mlx-smoke`: build with `xcodebuild`, run through `Scripts/mlx-run`
- `verify`: the canonical local gate
- `install-hooks`: wire `.githooks/pre-commit`
- `run`: convenience entrypoint into the built CLI

#### 14.0.7 Point-Free-style test harness

The CLI test harness should copy the core `pfw` pattern:

- parse commands with `MicroSwift.parseAsRoot(arguments)`
- execute them in-process
- capture stdout/stderr
- assert inline snapshots for user-facing output
- use a base Swift Testing suite that installs default dependencies
- use per-test or per-suite dependency overrides for special cases

`pfw` does all of these things: its command tests parse the root command directly and snapshot stdout, and its base suite installs serialized execution, snapshot recording defaults, and dependency overrides. ([GitHub][9])

#### 14.0.8 Snapshot strategy in M0

M0 snapshot coverage should already include:

- `doctor --json`
- `doctor` human-readable output
- `seed dump --json`
- `--help`
- `mlx-smoke --json`
- dependency-derived path rendering where relevant

Inline snapshots are preferred for short command outputs. File snapshots are preferred for structured or multiline artifacts.

#### 14.0.9 Deterministic benchmark seed infrastructure

M0 should already establish the seed contract for later corpora.

`Config/bench-seeds.json` should define:

- schema version
- global seed
- per-corpus seed ids

`MicroSwiftSpec` should define a typed manifest:

- `BenchSeedManifest`
- `CorpusID`
- deterministic derivation rules

All later benchmark generators must derive from this seed contract, not invent their own RNG setup.

#### 14.0.10 MLX smoke path

The MLX smoke test proves the local runtime path works. It must:

1. build the CLI with `xcodebuild`
2. run the built CLI through `Scripts/mlx-run`
3. execute a trivial MLX kernel
4. emit stable JSON

The wrapper exists because MLX command-line tools need the Xcode-built runtime/framework context, and MLX documents `xcodebuild` as the supported command-line build path for Metal shader builds. The examples repo uses an `mlx-run` script for exactly this reason. ([GitHub][7])

#### 14.0.11 Pre-commit hook contents

The pre-commit hook should be thin:

```sh
#!/usr/bin/env bash
set -euo pipefail
exec ./dev verify
```

No duplicated logic inside the hook. The hook delegates entirely to the canonical verification command.

#### 14.0.12 Acceptance criteria

M0 is complete only when all of the following are true:

1. A fresh clone can run `./dev install-hooks` once and then rely on the checked-in pre-commit hook.
2. `./dev verify` exits `0` locally on a supported Apple silicon setup.
3. `micro-swift doctor --json` is deterministic except for explicitly marked volatile fields.
4. `micro-swift seed dump --json` matches a checked-in snapshot.
5. `micro-swift mlx-smoke --json` succeeds through the Xcode plus wrapper path.
6. The CLI tests run commands in-process via `parseAsRoot`, not through subprocess shells.
7. Snapshot tests cover both human-readable and structured output.
8. The full local verification path stays within the latency budget.

#### 14.0.13 Deliverables

- root Swift package with all seven modules
- `AsyncParsableCommand` CLI scaffold
- dependency client layer for shell effects
- `Scripts/dev`
- `Scripts/mlx-run`
- `.githooks/pre-commit`
- `./dev install-hooks`
- initial CLI commands: `doctor`, `seed dump`, `mlx-smoke`
- inline snapshot harness and base suite
- deterministic seed manifest
- ADRs and milestone documentation

#### 14.0.14 Why this milestone matters

This milestone encodes the shell architecture before the compiler exists. If M0 is wrong, every later milestone inherits friction: untestable command surfaces, ad hoc environment reads, nondeterministic output, and flaky MLX execution. M0 should make those invalid states structurally harder to represent.

---

### Milestone 1 — Source tape, spans, and file paging

**Goal:** build the source representation that everything else depends on.

**Deliverables**

- `SourceFile` loader to `MLXArray<UInt8>`
- line-break masks, line ids, line-start offsets
- `Span` type and line/column resolver
- deterministic page splitter for giant files
- page-summary structure with byte count and line count

**Acceptance criteria**

- exact byte-for-byte round-trip from source file to tape
- correct line/column lookup for arbitrary byte positions
- deterministic page boundaries for a given source and configured page size

---

### Milestone 2 — Regex DSL and lexer generator

**Goal:** define the lexer declaratively and compile it into deterministic runtime artifacts.

**Deliverables**

- regex DSL for token rules
- parser for the regex DSL
- regex AST normalization
- byte-equivalence-class construction
- rule-family classification:
  - literal
  - run
  - local-window
  - fallback automaton

- stable serialized lexer artifact format

**Acceptance criteria**

- the Micro-Swift lexer spec compiles successfully
- state/rule numbering is deterministic
- the artifact format is stable enough to diff in golden tests

---

### Milestone 3 — Tensor lexer fast paths

**Goal:** implement the high-throughput runtime lexer for the common rule families.

**Deliverables**

- byte classification kernels
- identifier run matcher
- integer run matcher
- whitespace/comment matcher
- fixed operator/literal matcher
- longest-match + priority resolver
- skip-token filtering
- keyword remap of identifier tokens
- lexical error token creation with spans

**Acceptance criteria**

- golden token streams for representative fixtures
- correct longest-match behavior
- lex errors point to exact offending spans

---

### Milestone 4 — Fallback automaton path and custom Metal kernels

**Goal:** support residual regex patterns without abandoning the regex-generator story.

**Deliverables**

- block-local fallback automaton evaluator
- MLXFast custom Metal kernel wrapper in Swift
- equivalence tests between fallback path and regex spec
- kernel cache and reuse policy

**Acceptance criteria**

- permitted residual rules lower into the fallback engine
- identical tokens via fast path or fallback path
- kernels are created once and reused

---

### Milestone 5 — Structural indexing and bracket proof

**Goal:** compute scope and delimiter structure from the token tape.

**Deliverables**

- brace/paren depth vectors
- statement start masks and ids
- scope ids
- delimiter matching or equivalent structural proof
- parse diagnostics for unmatched delimiters and malformed block regions

**Acceptance criteria**

- depth vectors are correct on nested functions and `if/else` blocks
- unbalanced inputs produce stable diagnostics with exact spans
- all outputs are deterministic

---

### Milestone 6 — Relational statement and declaration IR

**Goal:** lower top-level and block-level source structure into row-based IR tables.

**Deliverables**

- function table
- declaration table
- statement table
- block table
- stable id allocator based on source order and prefix counts
- origin spans for every row

**Acceptance criteria**

- fixtures produce the expected number of functions, declarations, and blocks
- row ids are stable across runs
- IR dumps are golden-testable

---

### Milestone 7 — Expression parser (Option A)

**Goal:** implement operator precedence parsing with Cartesian-tree / previous-smaller-or-equal style construction.

**Deliverables**

- expression-span extractor
- operator tape extractor
- precedence/associativity rank table
- parent relation builder
- operand attachment
- expression IR rows with exact spans

**Acceptance criteria**

- `10 + 5 * 2` parses as `10 + (5 * 2)`
- `(10 + 5) * 2` parses as expected
- equal-precedence associativity is correct
- malformed operator sequences produce precise spans

---

### Milestone 8 — Symbol interning and name resolution

**Goal:** resolve function references, parameters, and local `let` bindings deterministically.

**Deliverables**

- stable symbol interning
- function symbol table
- scope-aware declaration resolution
- unresolved-name and duplicate-definition diagnostics
- deterministic source-order joins

**Acceptance criteria**

- valid fixtures resolve all names uniquely
- invalid fixtures get exact primary and secondary spans
- symbol ids and resolution outputs are deterministic

---

### Milestone 9 — Type propagation, literal concretization, and semantic proofs

**Goal:** implement the semantic core of the proof of concept.

**Deliverables**

- type domain encodings
- expected-type seeds from annotations and signatures
- propagation kernels over expression regions
- operator rule tables
- call rule tables
- integer-literal concretization
- `UInt8` range checks
- whole-program proof masks
- type diagnostics with source spans

**Acceptance criteria**

- canonical `UInt8` concretization examples pass
- incorrect `UInt8` ranges fail at the literal span
- `if` conditions must be `Bool`
- function call labels and argument types are enforced

---

### Milestone 10 — Control flow and minimal CFG metadata

**Goal:** support `if/else` structure sufficiently for semantic checks and code generation.

**Deliverables**

- `if/else` row representation
- branch block spans
- condition expression links
- return-site validation for functions with single tail-return rule
- block-scoped declaration handling inside branches

**Acceptance criteria**

- valid nested `if/else` cases compile
- non-`Bool` conditions produce precise diagnostics
- invalid returns or malformed branch shapes are rejected

---

### Milestone 11 — Span-preserving optimizations

**Goal:** add simple but meaningful optimizations without losing provenance.

**Deliverables**

- constant folding
- dead-code elimination for unused lets
- span/provenance retention through rewrites
- deterministic compaction of surviving IR rows

**Acceptance criteria**

- foldable expressions are rewritten correctly
- unused declarations are dropped
- later diagnostics still point to original source spans

---

### Milestone 12 — WebAssembly backend

**Goal:** emit deterministic Wasm binaries for valid Micro-Swift programs.

**Deliverables**

- type lowering
- expression lowering
- call lowering
- structured `if/else` lowering
- `print` import wiring
- binary section emitter
- deterministic function and section ordering

**Acceptance criteria**

- valid fixtures execute correctly in a conforming Wasm runtime
- output matches expected program behavior
- binary output is deterministic byte-for-byte

---

### Milestone 13 — Diagnostic rendering and golden tests

**Goal:** make the prototype demo-worthy as a compiler, not just as kernels.

**Deliverables**

- human-readable diagnostic renderer
- caret and range rendering
- secondary-note rendering
- structured JSON diagnostic output
- golden tests for lex/parse/type/backend errors
- `CustomDump`-based structural dumps for diagnostics rows and IR subsets
- inline snapshot coverage for small user-facing diagnostics

**Acceptance criteria**

- all benchmarked error corpora render stable, span-correct diagnostics
- golden tests cover both structured and rendered forms

---

### Milestone 14 — Giant-file benchmark generator and fairness harness

**Goal:** produce the benchmark artifacts that actually test the hypothesis.

**Deliverables**

- deterministic corpus generators for:
  - Monster-Lex
  - Monster-Expr
  - Monster-Semantic
  - Monster-Error

- single-file giant-source generator
- benchmark runner scripts
- baseline runner scripts for `swiftc`
- result schema and report generator

**Acceptance criteria**

- at least one single-file corpus is large enough to amortize overhead
- benchmarks run in cold-start and warm steady-state modes
- reports include ratios and raw timings

---

### Milestone 15 — Performance tuning, chunk summaries, and fusion

**Goal:** make the benchmark outcome as favorable and honest as possible.

**Deliverables**

- fixed-size page kernels for graph reuse
- page-summary prefix-scan pipeline
- warm-cache compiled function reuse
- minimized host/device synchronization
- tuned custom Metal kernels where needed
- benchmark-guided tuning of page size and row layouts

**Acceptance criteria**

- warm steady-state throughput is materially better than cold-start throughput
- page chunking scales to the giant-file corpus
- regression suite prevents silent performance collapse

---

### Milestone 16 — Headline demo and write-up

**Goal:** turn the prototype into a credible research demonstration.

**Deliverables**

- one canonical valid giant-file benchmark
- one canonical error-path benchmark
- comparison report against the fixed `swiftc` baseline
- architecture write-up
- limitations and threats-to-validity section

**Acceptance criteria**

- reproducible benchmark scripts checked into repo
- deterministic outputs and diagnostics demonstrated live
- report clearly states what was faster, what was not, and why

---

## 15. Risks and mitigation

The main technical risk is that the generic parts of the design stay elegant while the hot kernels underperform. The mitigation is explicit: use MLX-Swift for the broad graph, but permit MLXFast kernels for the few critical inner loops that want block-local state machines.

The main scientific risk is benchmark framing. If the benchmark is too small, the result is likely negative for reasons unrelated to the central thesis. The mitigation is to make giant single-file workloads a design requirement.

The main engineering risk is determinism drift as the implementation becomes more parallel. The mitigation is to enforce stable ordering at every milestone and to snapshot token streams, IR dumps, diagnostics, seed manifests, and Wasm binaries.

The main tooling risk is shell complexity. The mitigation is the Point-Free-style CLI shell: dependency injection for all effects, in-process command execution in tests, inline snapshots for user surfaces, and one canonical local verification entrypoint.

---

## 16. Selected references

- Aaron Hsu, _A data parallel compiler hosted on the GPU_.
- Raph Levien, work on scan-based structure extraction, monoidal parsing, and parentheses matching.
- Robin Voetter, work on parallel lexing, parsing, semantic analysis, and GPU compilation.
- Automata and regex-derivative literature relevant to deterministic lexer generation.
- WebAssembly core specification.
- MLX Swift README and MLX Swift examples, especially the command-line `xcodebuild` and `mlx-run` execution model. ([GitHub][7])
- Point-Free `pfw`, as a concrete reference for CLI architecture, dependency injection, and inline snapshot-tested command surfaces. ([GitHub][8])
- Point-Free `swift-dependencies` docs and patterns for `DependencyKey` / `DependencyValues`. ([GitHub][10])
- Point-Free `swift-snapshot-testing`, including Swift Testing snapshot traits and textual snapshot strategies. ([GitHub][4])
- Point-Free `swift-custom-dump` for readable stable dumps and compact diffs. ([GitHub][5])
- `swift-argument-parser` and the `AsyncParsableCommand` model. ([GitHub][11])
- `swift-format` linting documentation for the built-in toolchain lint lane. ([GitHub][6])

---

The next concrete artifact should be the actual `Package.swift`, `Scripts/dev`, `.githooks/pre-commit`, and `MicroSwiftCLI` test harness skeleton that make Milestone 0 executable.

[1]: https://github.com/pointfreeco/pfw/blob/main/Sources/pfw/Main.swift "pfw/Sources/pfw/Main.swift at main · pointfreeco/pfw · GitHub"
[2]: https://github.com/pointfreeco/pfw/blob/main/Package.swift "pfw/Package.swift at main · pointfreeco/pfw · GitHub"
[3]: https://github.com/pointfreeco/pfw/blob/main/Sources/pfw/Dependencies/FileSystem.swift "pfw/Sources/pfw/Dependencies/FileSystem.swift at main · pointfreeco/pfw · GitHub"
[4]: https://github.com/pointfreeco/swift-snapshot-testing "GitHub - pointfreeco/swift-snapshot-testing:  Delightful Swift snapshot testing. · GitHub"
[5]: https://github.com/pointfreeco/swift-custom-dump "GitHub - pointfreeco/swift-custom-dump: A collection of tools for debugging, diffing, and testing your application's data structures. · GitHub"
[6]: https://github.com/swiftlang/swift-format?utm_source=chatgpt.com "Formatting technology for Swift source code"
[7]: https://github.com/ml-explore/mlx-swift?utm_source=chatgpt.com "ml-explore/mlx-swift: Swift API for MLX"
[8]: https://github.com/pointfreeco/pfw/blob/main/Package.swift?utm_source=chatgpt.com "pfw/Package.swift at main · pointfreeco/pfw"
[9]: https://github.com/pointfreeco/pfw/blob/main/Tests/pfwTests/Internal/AssertComand.swift "pfw/Tests/pfwTests/Internal/AssertComand.swift at main · pointfreeco/pfw · GitHub"
[10]: https://github.com/pointfreeco/swift-dependencies/blob/main/Sources/Dependencies/DependencyKey.swift?utm_source=chatgpt.com "DependencyKey.swift"
[11]: https://github.com/apple/swift-argument-parser?utm_source=chatgpt.com "apple/swift-argument-parser: Straightforward, type-safe ..."
