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

/-! ## Helper definitions for proofs -/

/-- The derived positive mask: position has len > 0 and is within validLen. -/
private def mkPositive (winners : List Reduction.Winner) (validLen : Nat) : List Bool :=
  let positions := arange winners.length
  let validMask := positions.map (fun p => decide (p < validLen))
  let winnerLen := winners.map (·.len)
  List.zipWith and (winnerLen.map (fun l => decide (l > 0))) validMask

private def mkEndExclusive (winners : List Reduction.Winner) : List Nat :=
  List.zipWith (· + ·) (arange winners.length) (winners.map (·.len))

/-- The iteration function with winners baked in. -/
private def iterStep (winners : List Reduction.Winner) (validLen : Nat)
    (mask : List Bool) : List Bool :=
  selectionIteration (mkPositive winners validLen) (mkEndExclusive winners)
    winners.length (arange winners.length) mask

/-! ## Fixpoint convergence helper lemmas -/

/-- Unwinding vectorizedSelect to use iterStep. -/
private theorem vectorizedSelect_eq_iter (winners : List Reduction.Winner) (validLen : Nat) :
    vectorizedSelect winners validLen =
    (List.range validLen).foldl (fun m _ => iterStep winners validLen m)
      (mkPositive winners validLen) := by
  simp only [vectorizedSelect, iterStep, mkPositive, mkEndExclusive, arange]

/-- If `List.zipWith and a b` has true at position i, then `a` has true at position i. -/
private theorem zipWith_and_left (a b : List Bool) (i : Nat) :
    (List.zipWith and a b).getD i false = true →
    a.getD i false = true := by
  induction a generalizing b i with
  | nil => simp [List.zipWith, List.getD]
  | cons x xs ih =>
    cases b with
    | nil => simp [List.zipWith, List.getD]
    | cons y ys =>
      cases i with
      | zero =>
        simp only [List.zipWith, List.getD, List.drop, List.head?]
        intro h; cases x <;> simp_all
      | succ j =>
        simp only [List.zipWith, List.getD]
        exact ih ys j

/-- The result of iterStep is always pointwise ≤ `positive`. -/
private theorem iterStep_sub_positive (winners : List Reduction.Winner) (validLen : Nat)
    (mask : List Bool) (i : Nat) :
    (iterStep winners validLen mask).getD i false = true →
    (mkPositive winners validLen).getD i false = true := by
  intro h
  unfold iterStep selectionIteration at h
  exact zipWith_and_left _ _ i h

/-- If the mask at step k is a fixpoint, all subsequent iterations give the same result. -/
private theorem fixpoint_stable (winners : List Reduction.Winner) (validLen : Nat)
    (k : Nat)
    (h_fix : iterStep winners validLen
        ((List.range k).foldl (fun m _ => iterStep winners validLen m)
          (mkPositive winners validLen)) =
      (List.range k).foldl (fun m _ => iterStep winners validLen m)
        (mkPositive winners validLen)) :
    ∀ j, (List.range (k + j)).foldl (fun m _ => iterStep winners validLen m)
           (mkPositive winners validLen) =
         (List.range k).foldl (fun m _ => iterStep winners validLen m)
           (mkPositive winners validLen) := by
  intro j
  induction j with
  | zero => simp [Nat.add_zero]
  | succ j ih =>
    rw [show k + (j + 1) = (k + j) + 1 from by omega]
    rw [show List.range ((k + j) + 1) = List.range (k + j) ++ [k + j]
        from List.range_succ]
    rw [List.foldl_append]
    simp only [List.foldl_cons, List.foldl_nil]
    rw [ih]
    exact h_fix

/-- The mask after validLen iterations is a fixpoint of iterStep.

    This is the core convergence argument. The proof requires showing that
    selectionIteration's coverage propagation via cummax reaches steady state
    within validLen iterations. Each iteration can propagate coverage information
    by at least one position (via the cummax scan), and there are at most validLen
    valid positions, so validLen iterations suffice.

    Formally, the argument is:
    - The output of selectionIteration is `and positive uncovered`
    - `uncovered[i]` depends on `max{selectedEnd[j] : j < i}` (via cummax + shift)
    - If mask is a fixpoint, then the coverage computed from mask is consistent
      with the mask itself
    - Starting from positive (all valid positions selected), each iteration
      removes positions whose predecessors' coverage overlaps them
    - After k iterations, all coverage chains of length ≤ k have been resolved
    - Since chains can be at most validLen long, validLen iterations suffice -/
private theorem mono_decreasing_stabilizes (winners : List Reduction.Winner) (validLen : Nat)
    (_ : validLen ≤ winners.length) :
    iterStep winners validLen
      ((List.range validLen).foldl (fun m _ => iterStep winners validLen m)
        (mkPositive winners validLen)) =
    (List.range validLen).foldl (fun m _ => iterStep winners validLen m)
      (mkPositive winners validLen) := by
  sorry

/-! ## Bridging lemmas: goal statement ↔ internal representation -/

/-- Map fusion: winners.map (fun w => decide (w.len > 0)) equals
    (winners.map (·.len)).map (fun l => decide (l > 0)). -/
private theorem winners_map_decide_len_gt_zero (winners : List Reduction.Winner) :
    winners.map (fun w => decide (w.len > 0)) =
    (winners.map (fun x => x.len)).map (fun l => decide (l > 0)) := by
  induction winners with
  | nil => simp
  | cons _ ws ih => simp [ih]

/-- The raw positive expression in the theorem statement equals mkPositive. -/
private theorem raw_positive_eq_mkPositive (winners : List Reduction.Winner) (validLen : Nat) :
    List.zipWith and (winners.map (fun w => decide (w.len > 0)))
      ((arange winners.length).map (fun p => decide (p < validLen))) =
    mkPositive winners validLen := by
  simp only [mkPositive, arange, MLX.arange]
  congr 1
  exact winners_map_decide_len_gt_zero winners

/-- The raw selectionIteration call equals iterStep. -/
private theorem raw_body_eq_iterStep (winners : List Reduction.Winner) (validLen : Nat)
    (mask : List Bool) :
    selectionIteration
      (List.zipWith and (winners.map (fun w => decide (w.len > 0)))
        ((arange winners.length).map (fun p => decide (p < validLen))))
      (List.zipWith (· + ·) (arange winners.length) (winners.map (·.len)))
      winners.length (arange winners.length) mask =
    iterStep winners validLen mask := by
  simp only [iterStep, mkPositive, mkEndExclusive, arange, MLX.arange]
  congr 2
  exact winners_map_decide_len_gt_zero winners

/-- The entire foldl in the goal statement equals the iterStep-based foldl. -/
private theorem goal_foldl_eq_iterStep_foldl (winners : List Reduction.Winner) (validLen : Nat)
    (l : List Nat) :
    l.foldl (fun mask _ =>
      selectionIteration
        (List.zipWith and (winners.map (fun w => decide (w.len > 0)))
          ((arange winners.length).map (fun p => decide (p < validLen))))
        (List.zipWith (· + ·) (arange winners.length) (winners.map (·.len)))
        winners.length (arange winners.length) mask)
      (List.zipWith and (winners.map (fun w => decide (w.len > 0)))
        ((arange winners.length).map (fun p => decide (p < validLen)))) =
    l.foldl (fun m _ => iterStep winners validLen m) (mkPositive winners validLen) := by
  conv_lhs =>
    arg 1
    ext mask _
    rw [raw_body_eq_iterStep]
  rw [raw_positive_eq_mkPositive]

/-! ## Main theorems -/

/-- The fixed-point converges: after at most `validLen` iterations, the mask is stable.

    Proved modulo `mono_decreasing_stabilizes`, which captures the core combinatorial
    argument that validLen iterations of selectionIteration suffice for convergence. -/
theorem fixpoint_converges (winners : List Reduction.Winner) (validLen : Nat)
    (h_valid : validLen ≤ winners.length) :
    ∀ (n : Nat), n ≥ validLen →
      (List.range n).foldl (fun mask _ =>
        selectionIteration
          (List.zipWith and (winners.map (·.len > 0))
            ((arange winners.length).map (· < validLen)))
          (List.zipWith (· + ·) (arange winners.length) (winners.map (·.len)))
          winners.length (arange winners.length) mask)
        (List.zipWith and (winners.map (·.len > 0))
          ((arange winners.length).map (· < validLen))) =
      vectorizedSelect winners validLen := by
  intro n hn
  rw [vectorizedSelect_eq_iter]
  rw [goal_foldl_eq_iterStep_foldl]
  have hn_eq : n = validLen + (n - validLen) := by omega
  rw [hn_eq]
  exact fixpoint_stable winners validLen validLen
    (mono_decreasing_stabilizes winners validLen h_valid) (n - validLen)

/-- The vectorized fixed-point selection produces the same tokens as the scalar greedy walk.

    Proof strategy: Show that the converged boolean mask from vectorizedSelect marks
    exactly the positions that the scalar greedy walk would select.

    The fixpoint characterization: after convergence, selectedMask[i] = true iff
    - positive[i] = true (winner has len > 0 and position is within validLen), AND
    - i >= max{j + winners[j].len : j < i, selectedMask[j] = true}
      (position is not covered by any earlier selected token)

    This is exactly the greedy selection criterion maintained by coveredUntil
    in scalarSelect. The proof would proceed by:
    1. Characterizing the fixpoint mask via the above predicate
    2. Showing extractSelected applied to this mask produces the same list as
       the scalar foldl, by induction on position

    The key helper lemmas needed:
    - The fixpoint mask is the unique boolean list satisfying the above predicate
    - The scalar walk's coveredUntil at each step equals the cummax-derived coverage
    - extractSelected filters by the mask, matching the scalar's conditional append -/
theorem selection_equiv (winners : List Reduction.Winner) (validLen : Nat)
    (h_valid : validLen ≤ winners.length) :
    extractSelected winners (vectorizedSelect winners validLen) =
    scalarSelect winners validLen := by
  sorry

end Selection
