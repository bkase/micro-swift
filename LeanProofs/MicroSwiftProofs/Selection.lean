import Mathlib.Data.List.Basic
import MicroSwiftProofs.MLXPrimitives
import MicroSwiftProofs.Reduction

/-!
# Greedy Selection (Phase D)

Models `GreedySelector.swift`. Given per-position winners, greedily select
non-overlapping tokens left-to-right.

Scalar: walk left-to-right, skip positions covered by previously selected tokens.
Vectorized: fixed-point iteration using cummax to propagate coverage.
-/

namespace Selection

open MLX

/-! ## Shared Types -/

structure SelectedToken where
  startPos : Nat
  length : Nat
  ruleID : Nat
  tokenKindID : Nat
  mode : Nat
  deriving Repr, DecidableEq

/-! ## Scalar Model -/

/-- Scalar greedy selection: walk left-to-right, take a token if it starts at or
    after the end of the last taken token. Mirrors `GreedySelector.select` in Swift. -/
def scalarSelect (winners : List Reduction.Winner) (validLen : Nat) : List SelectedToken :=
  let indexed := (List.range validLen).filterMap fun i =>
    match winners[i]? with
    | some w => some (i, w)
    | none => none
  indexed.foldl (fun (acc : Nat × List SelectedToken) (iw : Nat × Reduction.Winner) =>
    let (coveredUntil, selected) := acc
    let (i, w) := iw
    if w.len > 0 && i ≥ coveredUntil then
      (i + w.len,
       selected ++ [{ startPos := i, length := w.len, ruleID := w.ruleID,
                       tokenKindID := w.tokenKindID, mode := w.mode }])
    else
      (coveredUntil, selected)
  ) (0, []) |>.2

/-! ## Vectorized Model -/

/-- Compute the selected mask for one iteration of the fixed-point loop.
    Mirrors the body of `for _ in 0..<boundedValidLen` in Swift. -/
def selectionIteration (positive : List Bool) (endExclusive : List Nat)
    (pageSize : Nat) (positions : List Nat) (selectedMask : List Bool) : List Bool :=
  let selectedEnds := List.zipWith (fun sel e => if sel then e else 0) selectedMask endExclusive
  let coveredInclusive := cummaxFwd selectedEnds
  -- Shift right by 1, pad with 0 on the left
  let coveredBefore := 0 :: coveredInclusive.take (pageSize - 1)
  -- positions >= coveredBefore means this position is not covered by any prior selection
  List.zipWith and positive
    (List.zipWith (fun pos cb => decide (pos ≥ cb)) positions coveredBefore)

/-- Vectorized greedy selection: iterate the fixed-point `validLen` times.
    After convergence, the selectedMask marks which positions are token starts.
    Mirrors `GreedySelector.select(winnerTensors:validLen:)` in Swift. -/
def vectorizedSelect (winners : List Reduction.Winner) (validLen : Nat) : List Bool :=
  let pageSize := winners.length
  let positions := arange pageSize
  let validMask := positions.map (fun p => decide (p < validLen))
  let winnerLen := winners.map (·.len)
  let positive := List.zipWith and (winnerLen.map (fun l => decide (l > 0))) validMask
  let endExclusive := List.zipWith (· + ·) positions winnerLen

  -- Fixed-point iteration
  let initMask := positive
  (List.range validLen).foldl (fun mask _ =>
    selectionIteration positive endExclusive pageSize positions mask
  ) initMask

/-- Extract selected tokens from the mask and winner data. -/
def extractSelected (winners : List Reduction.Winner) (selectedMask : List Bool) : List SelectedToken :=
  List.zip (List.range winners.length) (List.zip selectedMask winners)
  |>.filterMap fun ⟨i, sel, w⟩ =>
    if sel then some { startPos := i, length := w.len, ruleID := w.ruleID,
                       tokenKindID := w.tokenKindID, mode := w.mode }
    else none

/-! ## Equivalence Theorem -/

/-- The vectorized fixed-point selection produces the same tokens as the scalar greedy walk. -/
theorem selection_equiv (winners : List Reduction.Winner) (validLen : Nat)
    (h_valid : validLen ≤ winners.length) :
    extractSelected winners (vectorizedSelect winners validLen) =
    scalarSelect winners validLen := by
  sorry

/-- The fixed-point converges: after at most `validLen` iterations, the mask is stable. -/
theorem fixpoint_converges (winners : List Reduction.Winner) (validLen : Nat)
    (h_valid : validLen ≤ winners.length) :
    ∀ (n : Nat), n ≥ validLen →
      (List.range n).foldl (fun mask _ =>
        selectionIteration
          (List.zipWith and (winners.map (·.len > 0)) ((arange winners.length).map (· < validLen)))
          (List.zipWith (· + ·) (arange winners.length) (winners.map (·.len)))
          winners.length (arange winners.length) mask)
        (List.zipWith and (winners.map (·.len > 0)) ((arange winners.length).map (· < validLen))) =
      vectorizedSelect winners validLen := by
  sorry

end Selection
