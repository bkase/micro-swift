# micro-swift

MicroSwift is a single-repo Swift toolchain bootstrap for local-first development of
MLX-backed compiler-style tooling.

## Local command surface

- `./dev doctor` — print toolchain/runtime diagnostics
- `./dev seed dump` — show deterministic seed manifest
- `./dev mlx-smoke` — run the MLX smoke path
- `./dev verify` — canonical local check: format, lint, build, test

## Repository shape

- `Sources/` contains executable and module targets.
- `Tests/` contains unit tests and CLI snapshots.
- `Scripts/` contains local tool orchestration.
- `Docs/` contains architecture records and milestones.
