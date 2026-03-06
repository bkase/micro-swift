# M0 Code Review: Current State vs. Specification

## Overall Assessment

The codebase is well-structured and covers most of the M0 spec. The Point-Free-shaped architecture is solid: `AsyncParsableCommand` root, `swift-dependencies` for DI, snapshot testing via `parseAsRoot`, and all 8 dependency clients are implemented. That said, there are several bugs and spec gaps worth addressing.

---

## Bugs

### 1. `repo_root()` returns `Scripts/` instead of repo root (P0)
**File:** `Scripts/lib/common.sh:5`

```bash
local path="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
```

`BASH_SOURCE[0]` inside `repo_root()` resolves to `Scripts/lib/common.sh`. Going up one directory (`..`) gives `Scripts/`, not the repo root. Should be `../..`. This makes `ROOT_DIR` in `Scripts/dev` point to `Scripts/` instead of the repo root, breaking `install-hooks`, `mlx-smoke`, and `resolve_mlx_binary` (all use `$ROOT_DIR/.build` or `$ROOT_DIR/.git`).

### 2. Double `shift` in `./dev doctor` eats arguments (P0)
**File:** `Scripts/dev:49,53`

Line 49 already shifts past the command name. Then the `doctor)` case does another `shift || true` on line 53, eating the first real argument. So `./dev doctor --json` silently drops `--json` and runs `doctor.sh` with no flags.

### 3. `FileSystemClient.directoryExists` doesn't actually check for directories (P1)
**File:** `Sources/MicroSwiftCLI/Dependencies/DependencyClients.swift:40`

```swift
directoryExists: { FileManager.default.fileExists(atPath: $0) },
```

Should use `FileManager.default.fileExists(atPath:isDirectory:)` with an `ObjCBool` out-parameter, otherwise it returns `true` for files too.

### 4. `Doctor.swift` leaks through `ProcessInfo.processInfo` directly (P2)
**File:** `Sources/MicroSwiftCLI/Commands/Doctor.swift:30`

```swift
runtime: environment["MS_RUNTIME"] ?? ProcessInfo.processInfo.operatingSystemVersionString
```

Falls back to an ambient global instead of going through the `env` dependency. The spec says "all shell effects are dependencies, not ambient globals."

### 5. `TestOutputCapture` is `@unchecked Sendable` with no synchronization (P2)
**File:** `Tests/MicroSwiftCLITests/Internal/DependencyDoubles.swift:5`

Mutable `output` property with no lock/actor. Works in practice because test calls are sequential, but violates the Sendable contract. Could use `LockIsolated` from swift-dependencies, an actor, or `OSAllocatedUnfairLock`.

---

## Spec Gaps

### 6. No `--help` snapshot test
**Spec ref:** 14.0.8 explicitly lists `--help` as requiring snapshot coverage. Currently no test exists for it.

### 7. `MLXRuntimeClient.live()` is a mock, not a real MLX kernel
**Spec ref:** 14.0.10 says the MLX smoke test must "execute a trivial MLX kernel." The live implementation returns hardcoded values:

```swift
public static func live() -> Self {
  Self {
    MLXSmokeResult(status: "ok", kernel: "trivial-add", version: "deterministic-mock")
  }
}
```

No actual MLX code runs. This is the biggest functional gap relative to the spec.

### 8. No base test suite with default dependency overrides
**Spec ref:** 14.0.7 says "use a base Swift Testing suite that installs default dependencies" and "use per-test or per-suite dependency overrides for special cases." Currently every test manually sets up all dependency overrides (stdout, stderr, env, clock, uuid). A shared `@Suite` trait or helper that installs common test defaults would reduce duplication and match the `pfw` pattern.

### 9. `CorpusID` silent fallback to `.spec`
**File:** `Sources/MicroSwiftSpec/CorpusID.swift:11`

```swift
public init(_ raw: String) {
  self = Self(rawValue: raw) ?? .spec
}
```

Unknown corpus strings silently become `.spec`. This could mask configuration errors in `bench-seeds.json`. Consider making this failable or throwing.

---

## Minor Issues

### 10. Swift tools version mismatch
`Package.swift` uses `swift-tools-version: 5.10` but `.swift-version` says `6.0`. With Swift 6.0 toolchain you could use `swift-tools-version: 6.0` for stricter concurrency checking.

### 11. `unsafeFlags` on `MicroSwiftSpec`
**File:** `Package.swift:31`

```swift
.unsafeFlags(["-enable-bare-slash-regex"], .when(configuration: .debug))
```

This flag is for Swift < 6.0 (bare slash regex is default in Swift 6). It also prevents the target from being used as a dependency by external packages.

### 12. Snapshot resources may conflict with snapshot testing
**File:** `Package.swift:86`

```swift
resources: [.copy("__Snapshots__")]
```

`swift-snapshot-testing` reads/writes snapshots relative to `#filePath` in the source tree. Copying them as bundle resources may be unnecessary or cause confusion about which copy is the source of truth.

### 13. Missing `Artifacts/snapshots/` directory
**Spec ref:** 14.0.2 layout includes `Artifacts/snapshots/` but this directory doesn't exist.

---

## Summary Table

| # | Severity | Category | Issue |
|---|----------|----------|-------|
| 1 | P0 Bug | Scripts | `repo_root()` returns wrong directory |
| 2 | P0 Bug | Scripts | Double shift eats `./dev doctor` args |
| 3 | P1 Bug | Source | `directoryExists` doesn't check isDirectory |
| 4 | P2 Bug | Source | `Doctor` leaks ambient `ProcessInfo` |
| 5 | P2 Bug | Tests | `TestOutputCapture` unsound Sendable |
| 6 | Gap | Tests | Missing `--help` snapshot |
| 7 | Gap | Source | MLX live client is a mock |
| 8 | Gap | Tests | No base test suite with shared defaults |
| 9 | Gap | Source | Silent `CorpusID` fallback |
| 10 | Minor | Config | Swift tools version mismatch |
| 11 | Minor | Config | Unnecessary `unsafeFlags` |
| 12 | Minor | Config | Snapshot resources in Package.swift |
| 13 | Minor | Layout | Missing `Artifacts/snapshots/` |

---

## What's Done Well

- All 8 dependency clients with live/test implementations
- Clean `parseAsRoot` in-process test pattern
- 6 snapshot tests covering JSON + text for all 3 commands
- Pre-commit hook is thin and delegates to `./dev verify`
- `BenchSeedManifest` with proper custom Codable for `CorpusID` keys
- `Config/bench-seeds.json` with schema version and per-corpus seeds
- ADRs and milestone docs in place
- `./dev` covers all 9 specified commands
