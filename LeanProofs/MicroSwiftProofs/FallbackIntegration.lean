import Mathlib.Data.List.Basic
import MicroSwiftProofs.MLXPrimitives
import MicroSwiftProofs.Reduction

/-!
# Fallback Integration

Models `integrateWithFallback` from `WinnerReduction.swift`.

The fast-path (literal/classRun/headTail/prefixed) may not cover all lexer rules.
Rules with complex regex patterns are handled by a scalar DFA fallback
(`ScalarFallbackEvaluator.swift`). After both paths produce per-position winners,
they are merged using the same tie-breaking logic as the main reduction.

The scalar version compares element-by-element.
The vectorized version uses the same `.>`, `.==`, `.&&`, `.||`, `which` chain.
-/

namespace FallbackIntegration

open MLX Reduction

/-! ## Fallback Result -/

/-- Per-position fallback winners. Mirrors `FallbackPageResult` in Swift. -/
structure FallbackResult where
  winners : List Winner
  deriving Repr

/-! ## Scalar Merge -/

/-- Scalar merge: at each position, pick the better of fast-path and fallback.
    Uses the same `isBetter` tie-breaking as reduction.
    Mirrors the host `integrateWithFallback(fastWinners:fallbackResult:pageWidth:)`. -/
def scalarMerge (fastWinners fallbackWinners : List Winner) : List Winner :=
  List.zipWith (fun fast fb =>
    if isBetter fb fast then fb else fast
  ) fastWinners fallbackWinners

/-! ## Vectorized Merge -/

/-- Vectorized merge: apply the same element-wise comparison chain and `which`.
    Mirrors the tensor `integrateWithFallback` that uses `.>`, `.==`, `.&&`, `which`. -/
def vectorizedMerge (fastWinners fallbackWinners : List Winner) : List Winner :=
  let mask := vectorizedCompare fallbackWinners fastWinners
  winnerWhich mask fallbackWinners fastWinners

/-! ## Equivalence -/

theorem merge_equiv (fastWinners fallbackWinners : List Winner)
    (h_len : fastWinners.length = fallbackWinners.length) :
    vectorizedMerge fastWinners fallbackWinners =
    scalarMerge fastWinners fallbackWinners := by
  sorry

end FallbackIntegration
