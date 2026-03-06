# ADR 0003 — Local-first verification

Local correctness is enforced by:

- deterministic formatting
- strict linting
- deterministic smoke output snapshots
- canonical `./dev verify` execution
- pre-commit invoking `./dev verify`
