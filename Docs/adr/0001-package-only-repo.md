# ADR 0001 — Single-package root

A single Swift package owns all source and test targets.

Rationale
- Removes ambiguity around module resolution and tooling entrypoints.
- Simplifies local verification with one `swift test` and one `swift build`.
