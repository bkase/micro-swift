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

/-- If `List.zipWith and a b` has true at position i, then `b` has true at position i. -/
private theorem zipWith_and_right (a b : List Bool) (i : Nat) :
    (List.zipWith and a b).getD i false = true →
    b.getD i false = true := by
  induction a generalizing b i with
  | nil => simp [List.zipWith, List.getD]
  | cons x xs ih =>
    cases b with
    | nil => simp [List.zipWith, List.getD]
    | cons y ys =>
      cases i with
      | zero =>
        simp only [List.zipWith, List.getD, List.drop, List.head?]
        intro h; cases x <;> cases y <;> simp_all
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

/-- Notation: mask after k iterations. -/
private def maskAfter (winners : List Reduction.Winner) (validLen : Nat) (k : Nat) : List Bool :=
  (List.range k).foldl (fun m _ => iterStep winners validLen m) (mkPositive winners validLen)

/-- maskAfter k+1 = iterStep (maskAfter k). -/
private theorem maskAfter_succ (winners : List Reduction.Winner) (validLen k : Nat) :
    maskAfter winners validLen (k + 1) = iterStep winners validLen (maskAfter winners validLen k) := by
  simp only [maskAfter, List.range_succ, List.foldl_append, List.foldl_cons, List.foldl_nil]

/-- cummaxFwd at position i depends only on inputs at positions 0..i.
    Since cummaxFwd = (scanl max 0).drop 1, cummaxFwd(xs)[i] = max(0, xs[0], ..., xs[i]). -/
private theorem scanl_max_prefix_eq (xs ys : List Nat) (n : Nat) (init : Nat) (i : Nat)
    (hxn : xs.length = n) (hyn : ys.length = n)
    (h : ∀ j ≤ i, xs.getD j 0 = ys.getD j 0) :
    (xs.scanl max init).getD (i + 1) 0 = (ys.scanl max init).getD (i + 1) 0 := by
  induction xs generalizing ys init i n with
  | nil =>
    subst hxn; simp at hyn; subst hyn
    simp
  | cons x xs ih =>
    cases n with
    | zero => simp at hxn
    | succ n =>
      simp at hxn
      cases ys with
      | nil => simp at hyn
      | cons y ys =>
        simp at hyn
        have hxy : x = y := by
          have := h 0 (Nat.zero_le _)
          simp [List.getD] at this
          exact this
        -- scanl max init (x :: xs) = init :: scanl max (max init x) xs
        -- so getD (i+1) = getD i of the tail scanl
        cases i with
        | zero =>
          -- getD 1 of (init :: scanl max (max init y) _) = (scanl max (max init y) _).getD 0 0
          -- and the first element of any scanl is the init value
          simp only [hxy, List.scanl, List.getD]
          cases xs <;> cases ys <;> simp [List.scanl]
        | succ i =>
          -- getD (i+2) of (init :: scanl ...) = getD (i+1) of (scanl ...)
          -- IH: ∀ (ys) (n init i), xs.length = n → ys.length = n → ... → scanl eq
          simp only [List.scanl, hxy]
          exact ih ys n (max init y) i hxn hyn (by
            intro j hj
            have := h (j + 1) (by omega)
            simpa [List.getD] using this)

private theorem getD_drop {α : Type*} (l : List α) (n i : Nat) (d : α) :
    (l.drop n).getD i d = l.getD (n + i) d := by
  simp [List.getD, List.getElem?_drop]

private theorem cummaxFwd_prefix_eq (xs ys : List Nat) (n : Nat) (i : Nat)
    (hxn : xs.length = n) (hyn : ys.length = n)
    (h : ∀ j ≤ i, xs.getD j 0 = ys.getD j 0) :
    (cummaxFwd xs).getD i 0 = (cummaxFwd ys).getD i 0 := by
  simp only [cummaxFwd, MLX.cummaxFwd]
  rw [getD_drop, getD_drop]
  rw [show 1 + i = i + 1 from by omega]
  exact scanl_max_prefix_eq xs ys n 0 i hxn hyn h

/-- iterStep at position i depends only on the input mask at positions j < i.
    This is the key locality property: coveredBefore[i] depends on cummaxFwd[i-1],
    which depends on selectedEnds[0..i-1], which depends on mask[0..i-1]. -/
private theorem iterStep_prefix_eq (winners : List Reduction.Winner) (validLen : Nat)
    (mask₁ mask₂ : List Bool) (i : Nat)
    (h : ∀ j < i, mask₁.getD j false = mask₂.getD j false) :
    (iterStep winners validLen mask₁).getD i false =
    (iterStep winners validLen mask₂).getD i false := by
  sorry

/-- After j+1 iterations, position j has converged: further iterations don't change it.
    Uses the wave-front argument: iterStep at position j depends only on mask at positions < j.
    By strong induction on j: positions 0..j-1 have already converged (IH), so the inputs to
    iterStep at position j are the same for all k ≥ j+1. -/
-- Strong induction on j: all positions < j have converged after their respective iterations
private theorem mask_converges_at_strong (winners : List Reduction.Winner) (validLen : Nat) :
    ∀ j, j < winners.length →
    ∀ k, k ≥ j + 1 →
    (maskAfter winners validLen k).getD j false =
    (maskAfter winners validLen (j + 1)).getD j false := by
  intro j
  induction j using Nat.strongRecOn with
  | _ j ih_j =>
    intro hj k hk
    -- Induct on the "gap" k - (j+1)
    induction k with
    | zero => omega
    | succ k ih_k =>
      by_cases hk' : k ≥ j + 1
      · -- k ≥ j+1: show maskAfter k and maskAfter j agree on positions < j
        rw [maskAfter_succ]
        have h_agree : ∀ p < j, (maskAfter winners validLen k).getD p false =
            (maskAfter winners validLen j).getD p false := by
          intro p hp
          -- By ih_j for position p: maskAfter k at p = maskAfter(p+1) at p
          -- and maskAfter j at p = maskAfter(p+1) at p
          have h1 := ih_j p hp (by omega) k (by omega)
          have h2 := ih_j p hp (by omega) j (by omega)
          rw [h1, h2]
        rw [iterStep_prefix_eq winners validLen _ _ j h_agree, ← maskAfter_succ]
      · -- k = j
        have : k = j := by omega
        subst this; rfl

private theorem mask_converges_at (winners : List Reduction.Winner) (validLen : Nat)
    (j : Nat) (hj : j < winners.length)
    (k : Nat) (hk : k ≥ j + 1) :
    (maskAfter winners validLen k).getD j false =
    (maskAfter winners validLen (j + 1)).getD j false :=
  mask_converges_at_strong winners validLen j hj k hk

/-- For positions i ≥ validLen, iterStep always gives false (positive[i] = false). -/
private theorem iterStep_false_beyond_validLen (winners : List Reduction.Winner) (validLen : Nat)
    (mask : List Bool) (i : Nat) (hi : i ≥ validLen) :
    (iterStep winners validLen mask).getD i false = false := by
  suffices h_pos_false : (mkPositive winners validLen).getD i false = false by
    by_contra h
    have h_true : (iterStep winners validLen mask).getD i false = true := by
      cases hv : (iterStep winners validLen mask).getD i false <;> simp_all
    have := iterStep_sub_positive winners validLen mask i h_true
    rw [h_pos_false] at this; exact absurd this (by decide)
  -- Show mkPositive[i] = false using that decide(i < validLen) = false
  simp only [mkPositive, arange, MLX.arange]
  by_contra h_ne
  have h_pos : (List.zipWith and
    ((winners.map (·.len)).map (fun l => decide (l > 0)))
    ((List.range winners.length).map (fun p => decide (p < validLen)))).getD i false = true := by
    cases hv : (List.zipWith and _ _).getD i false <;> simp_all
  have h_right := zipWith_and_right _ _ i h_pos
  -- h_right : validMask.getD i false = true
  -- validMask = (List.range n).map (fun p => decide (p < validLen))
  -- If i < n, validMask[i] = decide(i < validLen) = false since i ≥ validLen
  -- If i ≥ n, validMask[i] = false (out of bounds)
  -- h_right : validMask.getD i false = true
  -- Show contradiction by examining what getD produces
  -- If i ≥ winners.length, then List.range doesn't have index i, so getD = false
  -- If i < winners.length, then map gives decide(i < validLen) = false since i ≥ validLen
  by_cases hi_len : i < winners.length
  · -- i is in range, so map gives decide(i < validLen)
    have : ((List.range winners.length).map (fun p => decide (p < validLen)))[i]? =
        some (decide (i < validLen)) := by
      rw [List.getElem?_map]
      simp [List.getElem?_range, hi_len]
    simp only [List.getD, this] at h_right
    simp at h_right; omega
  · -- i is out of range
    have : ((List.range winners.length).map (fun p => decide (p < validLen)))[i]? = none := by
      rw [List.getElem?_eq_none]
      simp; omega
    simp [List.getD, this] at h_right

/-- The mask after validLen iterations is a fixpoint of iterStep.

    Proof uses the wave-front argument: after k iterations, positions 0..k-1
    have converged. Since positions ≥ validLen are always false (from positive),
    after validLen iterations all positions are stable. -/
-- maskAfter is false beyond validLen, for any number of iterations
private theorem maskAfter_false_beyond (winners : List Reduction.Winner) (validLen : Nat)
    (k : Nat) (i : Nat) (hi : i ≥ validLen) :
    (maskAfter winners validLen k).getD i false = false := by
  induction k with
  | zero =>
    -- maskAfter 0 = mkPositive, which is false beyond validLen
    simp only [maskAfter, List.range_zero, List.foldl_nil]
    -- mkPositive[i] = false for i ≥ validLen (same argument as iterStep_false_beyond)
    suffices (mkPositive winners validLen).getD i false = false by exact this
    simp only [mkPositive, arange, MLX.arange]
    by_contra h_ne
    have h_pos : (List.zipWith and
      ((winners.map (·.len)).map (fun l => decide (l > 0)))
      ((List.range winners.length).map (fun p => decide (p < validLen)))).getD i false = true := by
      cases hv : (List.zipWith and _ _).getD i false <;> simp_all
    have h_right := zipWith_and_right _ _ i h_pos
    by_cases hi_len : i < winners.length
    · have : ((List.range winners.length).map (fun p => decide (p < validLen)))[i]? =
          some (decide (i < validLen)) := by
        rw [List.getElem?_map]; simp [List.getElem?_range, hi_len]
      simp only [List.getD, this] at h_right; simp at h_right; omega
    · have : ((List.range winners.length).map (fun p => decide (p < validLen)))[i]? = none := by
        rw [List.getElem?_eq_none]; simp; omega
      simp [List.getD, this] at h_right
  | succ k ih =>
    rw [maskAfter_succ]
    exact iterStep_false_beyond_validLen winners validLen _ i hi

private theorem mkPositive_length (winners : List Reduction.Winner) (validLen : Nat) :
    (mkPositive winners validLen).length = winners.length := by
  simp [mkPositive, arange, MLX.arange, List.length_zipWith, List.length_map, List.length_range]

private theorem mkEndExclusive_length (winners : List Reduction.Winner) :
    (mkEndExclusive winners).length = winners.length := by
  simp [mkEndExclusive, arange, MLX.arange, List.length_zipWith, List.length_map, List.length_range]

private theorem length_scanl {α β : Type*} (f : β → α → β) (b : β) (l : List α) :
    (l.scanl f b).length = l.length + 1 := by
  induction l generalizing b with
  | nil => simp [List.scanl]
  | cons x xs ih => simp [List.scanl, ih]

private theorem iterStep_length (winners : List Reduction.Winner) (validLen : Nat)
    (mask : List Bool) (h_len : mask.length = winners.length) :
    (iterStep winners validLen mask).length = winners.length := by
  unfold iterStep selectionIteration
  simp only [List.length_zipWith, mkPositive_length, List.length_cons, List.length_take,
    cummaxFwd, MLX.cummaxFwd, List.length_drop, arange, MLX.arange,
    List.length_range, mkEndExclusive_length, length_scanl, h_len]
  omega

private theorem maskAfter_length (winners : List Reduction.Winner) (validLen k : Nat) :
    (maskAfter winners validLen k).length = winners.length := by
  induction k with
  | zero => simp [maskAfter, mkPositive_length]
  | succ k ih => rw [maskAfter_succ]; exact iterStep_length winners validLen _ ih

private theorem mono_decreasing_stabilizes (winners : List Reduction.Winner) (validLen : Nat)
    (h_bound : validLen ≤ winners.length) :
    iterStep winners validLen
      ((List.range validLen).foldl (fun m _ => iterStep winners validLen m)
        (mkPositive winners validLen)) =
    (List.range validLen).foldl (fun m _ => iterStep winners validLen m)
      (mkPositive winners validLen) := by
  -- Rewrite using maskAfter notation
  change iterStep winners validLen (maskAfter winners validLen validLen) =
    maskAfter winners validLen validLen
  rw [← maskAfter_succ]
  -- Prove maskAfter(validLen+1) = maskAfter(validLen) via List.ext_getElem
  apply List.ext_getElem
  · -- Length equality
    rw [maskAfter_length, maskAfter_length]
  · -- Pointwise equality
    intro i h1 h2
    -- Convert getElem to getD
    have h1' : i < winners.length := by rw [← maskAfter_length winners validLen (validLen + 1)]; exact h1
    by_cases hi : i < validLen
    · -- Position in valid range: both converged to maskAfter(i+1)[i]
      have hg1 := mask_converges_at winners validLen i (by omega) (validLen + 1) (by omega)
      have hg2 := mask_converges_at winners validLen i (by omega) validLen (by omega)
      -- getD i false = [i]?.getD false. Since i < length, [i]? = some [i], so getD = [i]
      have hl1 := maskAfter_length winners validLen (validLen + 1)
      have hl2 := maskAfter_length winners validLen validLen
      simp only [List.getD, List.getElem?_eq_getElem (by omega : i < (maskAfter winners validLen (validLen + 1)).length)] at hg1
      simp only [List.getD, List.getElem?_eq_getElem (by omega : i < (maskAfter winners validLen validLen).length)] at hg2
      simp at hg1 hg2
      rw [← hg2] at hg1
      exact hg1
    · -- Position beyond validLen: both false
      have hg1 := maskAfter_false_beyond winners validLen (validLen + 1) i (by omega)
      have hg2 := maskAfter_false_beyond winners validLen validLen i (by omega)
      simp only [List.getD, List.getElem?_eq_getElem (by omega : i < (maskAfter winners validLen (validLen + 1)).length)] at hg1
      simp only [List.getD, List.getElem?_eq_getElem (by omega : i < (maskAfter winners validLen validLen).length)] at hg2
      simp at hg1 hg2
      rw [hg1, hg2]

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
