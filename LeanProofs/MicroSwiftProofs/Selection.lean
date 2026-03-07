import Mathlib.Data.List.Basic
import Mathlib.Data.List.Scan
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

private theorem length_scanl' {α β : Type*} (f : β → α → β) (b : β) (l : List α) :
    (l.scanl f b).length = l.length + 1 := by
  induction l generalizing b with
  | nil => simp [List.scanl]
  | cons x xs ih => simp [List.scanl, ih]

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
-- Helper: zipWith_ite on masks that agree at position j
private theorem zipWith_ite_getD_eq (mask₁ mask₂ : List Bool) (vals : List Nat) (j : Nat)
    (h : mask₁.getD j false = mask₂.getD j false) :
    (List.zipWith (fun sel e => if sel then e else 0) mask₁ vals).getD j 0 =
    (List.zipWith (fun sel e => if sel then e else 0) mask₂ vals).getD j 0 := by
  simp only [List.getD, List.getElem?_zipWith]
  cases hm1 : mask₁[j]? with
  | none =>
    simp only [List.getD, hm1, Option.getD] at h
    -- h : false = mask₂.getD j false, so mask₂[j]? is none or some false
    cases hm2 : mask₂[j]? with
    | none => simp
    | some v2 =>
      simp only [hm2, Option.getD] at h; subst h
      -- v2 = false, so both sides have "if false then e else 0" = 0
      cases vals[j]? <;> simp
  | some v1 =>
    cases hm2 : mask₂[j]? with
    | none =>
      simp only [List.getD, hm1, hm2, Option.getD] at h
      -- h : v1 = false
      subst h
      cases vals[j]? <;> simp
    | some v2 =>
      simp only [List.getD, hm1, hm2, Option.getD] at h
      rw [h]

-- Helper: getD of zipWith and
private theorem getD_zipWith_and (a b : List Bool) (i : Nat) :
    (List.zipWith and a b).getD i false =
    (a.getD i false && b.getD i false) := by
  simp only [List.getD]
  rw [List.getElem?_zipWith]
  cases ha : a[i]? with
  | none => simp
  | some va =>
    cases hb : b[i]? with
    | none =>
      simp only [Option.map, Option.bind]
      cases va <;> simp
    | some vb => simp

-- Helper: getD of zipWith for a binary function
private theorem getD_zipWith_nat_bool (f : Nat → Nat → Bool) (a b : List Nat) (i : Nat) :
    (List.zipWith f a b).getD i false =
    match a[i]?, b[i]? with
    | some va, some vb => f va vb
    | _, _ => false := by
  simp only [List.getD]
  rw [List.getElem?_zipWith]
  cases ha : a[i]? with
  | none => simp
  | some va =>
    cases hb : b[i]? with
    | none => simp
    | some vb => simp

private theorem iterStep_prefix_eq (winners : List Reduction.Winner) (validLen : Nat)
    (mask₁ mask₂ : List Bool) (i : Nat)
    (h_len₁ : mask₁.length = winners.length) (h_len₂ : mask₂.length = winners.length)
    (h : ∀ j < i, mask₁.getD j false = mask₂.getD j false) :
    (iterStep winners validLen mask₁).getD i false =
    (iterStep winners validLen mask₂).getD i false := by
  unfold iterStep selectionIteration
  set pos := mkPositive winners validLen
  set endExcl := mkEndExclusive winners
  set ps := arange winners.length
  set se₁ := List.zipWith (fun sel e => if sel then e else 0) mask₁ endExcl
  set se₂ := List.zipWith (fun sel e => if sel then e else 0) mask₂ endExcl
  set cb₁ := 0 :: (cummaxFwd se₁).take (winners.length - 1)
  set cb₂ := 0 :: (cummaxFwd se₂).take (winners.length - 1)
  -- Both cb₁ and cb₂ have length winners.length (since masks have same length)
  have h_ee_len : endExcl.length = winners.length := by
    simp [endExcl, mkEndExclusive, arange, MLX.arange, List.length_zipWith, List.length_range, List.length_map]
  have h_se_len : se₁.length = winners.length := by
    simp [se₁, List.length_zipWith, h_len₁, h_ee_len]
  have h_se_len₂ : se₂.length = winners.length := by
    simp [se₂, List.length_zipWith, h_len₂, h_ee_len]
  -- Show cb₁[i]? = cb₂[i]?
  suffices h_cb : cb₁[i]? = cb₂[i]? by
    rw [getD_zipWith_and, getD_zipWith_and]
    congr 1
    rw [getD_zipWith_nat_bool, getD_zipWith_nat_bool]
    rw [h_cb]
  -- Prove cb₁[i]? = cb₂[i]?
  cases i with
  | zero => simp [cb₁, cb₂]
  | succ i =>
    simp only [cb₁, cb₂, List.getElem?_cons_succ]
    -- Need: (cummaxFwd se₁).take(n-1)[i]? = (cummaxFwd se₂).take(n-1)[i]?
    by_cases hi_range : i < winners.length - 1
    · -- In range of take
      simp only [List.getElem?_take, show i < winners.length - 1 from hi_range, ite_true]
      -- cummaxFwd agreement at position i
      have h_se : ∀ j ≤ i, se₁.getD j 0 = se₂.getD j 0 :=
        fun j hj => zipWith_ite_getD_eq mask₁ mask₂ endExcl j (h j (by omega))
      have h_eq := cummaxFwd_prefix_eq se₁ se₂ winners.length i h_se_len h_se_len₂ h_se
      -- Both cummaxFwd have the same length
      have h_cm_len₁ : (cummaxFwd se₁).length = winners.length := by
        simp [cummaxFwd, MLX.cummaxFwd, List.length_drop, length_scanl', h_se_len]
      have h_cm_len₂' : (cummaxFwd se₂).length = winners.length := by
        simp [cummaxFwd, MLX.cummaxFwd, List.length_drop, length_scanl', h_se_len₂]
      -- i is in range of both cummax results
      have hi₁ : i < (cummaxFwd se₁).length := by omega
      have hi₂ : i < (cummaxFwd se₂).length := by omega
      rw [List.getElem?_eq_getElem hi₁, List.getElem?_eq_getElem hi₂]
      -- Convert getD equality to getElem equality
      simp only [List.getD, List.getElem?_eq_getElem hi₁, List.getElem?_eq_getElem hi₂] at h_eq
      simpa using h_eq
    · -- Out of range of take: both give none
      have h_cm_len₁ : (cummaxFwd se₁).length = winners.length := by
        simp [cummaxFwd, MLX.cummaxFwd, List.length_drop, length_scanl', h_se_len]
      have h_cm_len₂ : (cummaxFwd se₂).length = winners.length := by
        simp [cummaxFwd, MLX.cummaxFwd, List.length_drop, length_scanl', h_se_len₂]
      rw [List.getElem?_eq_none (by simp [List.length_take, h_cm_len₁]; omega)]
      rw [List.getElem?_eq_none (by simp [List.length_take, h_cm_len₂]; omega)]

private theorem mkPositive_length (winners : List Reduction.Winner) (validLen : Nat) :
    (mkPositive winners validLen).length = winners.length := by
  simp [mkPositive, arange, MLX.arange, List.length_zipWith, List.length_map, List.length_range]

private theorem mkEndExclusive_length (winners : List Reduction.Winner) :
    (mkEndExclusive winners).length = winners.length := by
  simp [mkEndExclusive, arange, MLX.arange, List.length_zipWith, List.length_map, List.length_range]

private theorem iterStep_length (winners : List Reduction.Winner) (validLen : Nat)
    (mask : List Bool) (h_len : mask.length = winners.length) :
    (iterStep winners validLen mask).length = winners.length := by
  unfold iterStep selectionIteration
  simp only [List.length_zipWith, mkPositive_length, List.length_cons, List.length_take,
    cummaxFwd, MLX.cummaxFwd, List.length_drop, arange, MLX.arange,
    List.length_range, mkEndExclusive_length, length_scanl', h_len]
  omega

private theorem maskAfter_length (winners : List Reduction.Winner) (validLen k : Nat) :
    (maskAfter winners validLen k).length = winners.length := by
  induction k with
  | zero => simp [maskAfter, mkPositive_length]
  | succ k ih => rw [maskAfter_succ]; exact iterStep_length winners validLen _ ih

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
        rw [iterStep_prefix_eq winners validLen _ _ j
          (maskAfter_length winners validLen k) (maskAfter_length winners validLen j)
          h_agree, ← maskAfter_succ]
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

/-! ## Selection equivalence helpers -/

/-- The scalar greedy mask: true at position i iff the scalar walk would select there. -/
private def scalarGreedyMaskAux (winners : List Reduction.Winner) (validLen : Nat)
    (positions : List Nat) (coveredUntil : Nat) (mask : List Bool) : Nat × List Bool :=
  match positions with
  | [] => (coveredUntil, mask)
  | i :: rest =>
    match winners[i]? with
    | some w =>
      if w.len > 0 ∧ i ≥ coveredUntil ∧ i < validLen then
        scalarGreedyMaskAux winners validLen rest (i + w.len)
          (mask.set i true)
      else
        scalarGreedyMaskAux winners validLen rest coveredUntil mask
    | none => scalarGreedyMaskAux winners validLen rest coveredUntil mask

private def scalarGreedyMask (winners : List Reduction.Winner) (validLen : Nat) : List Bool :=
  (scalarGreedyMaskAux winners validLen (List.range winners.length) 0
    (List.replicate winners.length false)).2

/-- The fixpoint mask is unique: any mask satisfying iterStep = self must agree
    pointwise with maskAfter(validLen). Uses wave-front convergence. -/
private theorem fixpoint_unique_pointwise (winners : List Reduction.Winner) (validLen : Nat)
    (h_valid : validLen ≤ winners.length)
    (mask : List Bool) (h_len : mask.length = winners.length)
    (h_fix : ∀ i, i < winners.length →
      mask.getD i false = (iterStep winners validLen mask).getD i false)
    (h_beyond : ∀ i, i ≥ validLen → mask.getD i false = false)
    (i : Nat) (hi : i < winners.length) :
    mask.getD i false = (maskAfter winners validLen validLen).getD i false := by
  -- Use strong induction, handling both i < validLen and i ≥ validLen
  induction i using Nat.strongRecOn with
  | _ i ih =>
    by_cases hi_val : i < validLen
    · have h_conv := mask_converges_at winners validLen i hi validLen (by omega)
      rw [h_conv, maskAfter_succ, h_fix i hi]
      have h_agree : ∀ j < i, mask.getD j false = (maskAfter winners validLen i).getD j false := by
        intro j hj
        have hj_len : j < winners.length := by omega
        rw [ih j hj hj_len]
        have hc1 := mask_converges_at winners validLen j hj_len validLen (by omega)
        have hc2 := mask_converges_at winners validLen j hj_len i (by omega)
        rw [hc1, hc2]
      exact iterStep_prefix_eq winners validLen mask (maskAfter winners validLen i) i
        h_len (maskAfter_length winners validLen i) h_agree
    · rw [h_beyond i (by omega)]
      exact (maskAfter_false_beyond winners validLen validLen i (by omega)).symm

/-- vectorizedSelect is maskAfter validLen when unfolded. -/
private theorem vectorizedSelect_eq_maskAfter (winners : List Reduction.Winner) (validLen : Nat) :
    vectorizedSelect winners validLen = maskAfter winners validLen validLen := by
  simp only [vectorizedSelect_eq_iter, maskAfter]

/-- extractSelected depends only on the pointwise values of the mask. -/
private theorem extractSelected_ext (winners : List Reduction.Winner)
    (mask₁ mask₂ : List Bool)
    (h_len₁ : mask₁.length = winners.length) (h_len₂ : mask₂.length = winners.length)
    (h : ∀ i, i < winners.length → mask₁.getD i false = mask₂.getD i false) :
    extractSelected winners mask₁ = extractSelected winners mask₂ := by
  unfold extractSelected
  -- Both zip with the same range and winners, differing only in the mask
  suffices h_eq : mask₁ = mask₂ by rw [h_eq]
  apply List.ext_getElem
  · rw [h_len₁, h_len₂]
  · intro i h1 h2
    have hi : i < winners.length := by rw [h_len₁] at h1; exact h1
    have h_eq := h i hi
    simp only [List.getD, List.getElem?_eq_getElem h1, List.getElem?_eq_getElem h2] at h_eq
    simpa using h_eq

/-- scalarGreedyMaskAux processes a prefix then a suffix. -/
private theorem scalarGreedyMaskAux_append (winners : List Reduction.Winner) (validLen : Nat)
    (ps1 ps2 : List Nat) (cu : Nat) (mask : List Bool) :
    scalarGreedyMaskAux winners validLen (ps1 ++ ps2) cu mask =
    let r := scalarGreedyMaskAux winners validLen ps1 cu mask
    scalarGreedyMaskAux winners validLen ps2 r.1 r.2 := by
  induction ps1 generalizing cu mask with
  | nil => simp [scalarGreedyMaskAux]
  | cons p rest ih =>
    simp only [List.cons_append]
    dsimp only [scalarGreedyMaskAux]
    cases hw : winners[p]? with
    | none => exact ih cu mask
    | some w =>
      simp only [hw]
      split
      · exact ih (p + w.len) (mask.set p true)
      · exact ih cu mask

/-- Positions not in the position list are unchanged by scalarGreedyMaskAux. -/
private theorem scalarGreedyMaskAux_unchanged (winners : List Reduction.Winner) (validLen : Nat)
    (positions : List Nat) (cu : Nat) (mask : List Bool) (j : Nat)
    (hj : j ∉ positions) :
    (scalarGreedyMaskAux winners validLen positions cu mask).2.getD j false = mask.getD j false := by
  induction positions generalizing cu mask with
  | nil => simp [scalarGreedyMaskAux]
  | cons p rest ih =>
    simp only [List.mem_cons, not_or] at hj
    dsimp only [scalarGreedyMaskAux]
    cases hw : winners[p]? with
    | none => exact ih cu mask hj.2
    | some w =>
      simp only [hw]
      split
      · have h1 := ih (p + w.len) (mask.set p true) hj.2
        rw [h1]
        simp only [List.getD, List.getElem?_set]
        split
        · rename_i heq; exact absurd heq.symm hj.1
        · rfl
      · exact ih cu mask hj.2

/-- scalarGreedyMask[i] is false initially in the replicate mask. -/
private theorem replicate_getD_false (n i : Nat) :
    (List.replicate n false).getD i false = false := by
  simp [List.getD, List.getElem?_replicate]
  split <;> simp

/-- Recursive definition of "coverage before position i" given a mask and winners.
    coveredBeforeRec(mask, winners, k) = max{j + winners[j].len : j < k, mask[j]} ∪ {0} -/
private def coveredBeforeRec (mask : List Bool) (winners : List Reduction.Winner) : Nat → Nat
  | 0 => 0
  | i + 1 => max (coveredBeforeRec mask winners i)
    (if mask.getD i false then i + (match winners[i]? with | some w => w.len | none => 0) else 0)

/-- The key connection between the vectorized coveredBefore and coveredBeforeRec.
    The (0 :: cummaxFwd(selectedEnds).take(n-1)) array at index i equals coveredBeforeRec. -/
private theorem coveredBefore_getD_eq (mask : List Bool) (winners : List Reduction.Winner)
    (h_len : mask.length = winners.length) (i : Nat) (hi : i < winners.length) :
    let se := List.zipWith (fun sel e => if sel then e else 0) mask (mkEndExclusive winners)
    let cb := 0 :: (cummaxFwd se).take (winners.length - 1)
    cb.getD i 0 = coveredBeforeRec mask winners i := by
  set se := List.zipWith (fun sel e => if sel then e else 0) mask (mkEndExclusive winners)
  have h_se_len : se.length = winners.length := by
    simp [se, List.length_zipWith, h_len, mkEndExclusive_length]
  have h_se_getD : ∀ k, k < winners.length →
      se.getD k 0 = (if mask.getD k false then k + (match winners[k]? with | some w => w.len | none => 0) else 0) := by
    intro k hk
    -- se[k]? = (mask[k]?.bind fun a => (mkEndExclusive winners)[k]?.map fun b => if a then b else 0)
    simp only [se, List.getD, List.getElem?_zipWith]
    -- mask[k]? and endExcl[k]? are both some since k < length
    have hm : k < mask.length := by omega
    have he : k < (mkEndExclusive winners).length := by rw [mkEndExclusive_length]; omega
    -- Compute endExcl[k]
    have h_ee : (mkEndExclusive winners)[k]? = some (k + winners[k].len) := by
      rw [List.getElem?_eq_getElem he]
      congr 1
      simp only [mkEndExclusive, arange, MLX.arange]
      simp only [List.getElem_zipWith, List.getElem_range, List.getElem_map]
    simp only [List.getElem?_eq_getElem hm, h_ee, Option.some_bind, Option.map_some', Option.getD]
    -- Now: if mask[k] then k + winners[k].len else 0
    --    = if mask.getD k false then k + (match winners[k]? with ...) else 0
    -- The LHS has mask[k] (Bool), the RHS has mask.getD k false which = mask[k] when k < length
    -- But after simp, mask.getD should already be resolved. Let's just split on mask[k]
    cases mask[k] <;> simp [List.getElem?_eq_getElem (show k < winners.length by omega)]
  have h_scanl : ∀ k, k ≤ winners.length →
      (se.scanl max 0).getD k 0 = coveredBeforeRec mask winners k := by
    intro k
    induction k with
    | zero => intro _; simp [coveredBeforeRec]
    | succ k ih_k =>
      intro hk
      have hk' : k < se.length := by rw [h_se_len]; omega
      have h_prev := ih_k (by omega)
      -- (se.scanl max 0).getD (k+1) 0 = coveredBeforeRec(k+1)
      -- = max (coveredBeforeRec k) (if mask.getD k false then ... else 0)
      -- Use the fact that scanl[k+1] = max(scanl[k], se[k])
      have h_scanl_len : (se.scanl max 0).length = se.length + 1 := length_scanl' _ _ _
      have h_in : k + 1 < (se.scanl max 0).length := by rw [h_scanl_len]; omega
      have h_in' : k < (se.scanl max 0).length := by omega
      simp only [List.getD, List.getElem?_eq_getElem h_in, Option.getD]
      -- Use getElem_succ_scanl
      rw [List.getElem_succ_scanl]
      simp only [coveredBeforeRec]
      congr 1
      · -- scanl[k] = coveredBeforeRec k
        simp only [List.getD, List.getElem?_eq_getElem h_in', Option.getD] at h_prev
        exact h_prev
      · -- se[k] = the conditional expression
        have := h_se_getD k (by omega)
        simp only [se, List.getD, List.getElem?_eq_getElem hk', Option.getD] at this ⊢
        convert this using 1
  cases i with
  | zero => simp [coveredBeforeRec]
  | succ i =>
    simp only [List.getD, List.getElem?_cons_succ]
    have hi' : i < winners.length - 1 := by omega
    rw [List.getElem?_take, if_pos hi']
    simp only [cummaxFwd, MLX.cummaxFwd]
    rw [List.getElem?_drop]
    rw [show 1 + i = i + 1 from by omega]
    have h := h_scanl (i + 1) (by omega)
    simp only [List.getD] at h
    have h_scanl_len : (se.scanl max 0).length = se.length + 1 := length_scanl' _ _ _
    have h_in : i + 1 < (se.scanl max 0).length := by rw [h_scanl_len, h_se_len]; omega
    rw [List.getElem?_eq_getElem h_in]
    rw [List.getElem?_eq_getElem h_in] at h
    simp at h
    simp [h]

/-- The iterStep result at position i equals positive[i] && decide(i >= coveredBeforeRec). -/
private theorem iterStep_getD_eq' (winners : List Reduction.Winner) (validLen : Nat)
    (mask : List Bool) (i : Nat) (hi : i < winners.length)
    (h_len : mask.length = winners.length) :
    (iterStep winners validLen mask).getD i false =
    ((mkPositive winners validLen).getD i false &&
     decide (i ≥ coveredBeforeRec mask winners i)) := by
  unfold iterStep selectionIteration
  rw [getD_zipWith_and]
  congr 1
  rw [getD_zipWith_nat_bool]
  have h_pos : (arange winners.length)[i]? = some i := by
    simp [arange, MLX.arange, List.getElem?_range, hi]
  rw [h_pos]
  set se := List.zipWith (fun sel e => if sel then e else 0) mask (mkEndExclusive winners)
  set cb := 0 :: (cummaxFwd se).take (winners.length - 1)
  have h_cb := coveredBefore_getD_eq mask winners h_len i hi
  have h_cb_len : cb.length = winners.length := by
    simp only [cb, List.length_cons, List.length_take,
      cummaxFwd, MLX.cummaxFwd, List.length_drop, length_scanl',
      List.length_zipWith, h_len, mkEndExclusive_length, se]
    omega
  have h_in : i < cb.length := by rw [h_cb_len]; exact hi
  suffices h_val : cb[i]? = some (coveredBeforeRec mask winners i) by
    rw [h_val]
  -- h_cb : cb.getD i 0 = coveredBeforeRec mask winners i
  -- goal : cb[i]? = some (coveredBeforeRec mask winners i)
  rw [List.getElem?_eq_getElem h_in]
  -- goal : some cb[i] = some (coveredBeforeRec ...)
  congr 1
  -- goal : cb[i] = coveredBeforeRec ...
  -- h_cb is getD form, convert
  have : cb.getD i 0 = cb[i] := by
    simp [List.getD, List.getElem?_eq_getElem h_in]
  rw [← this]
  exact h_cb

/-- Helper: decompose range n into range k ++ [k] ++ rest for k < n. -/
private theorem range_decompose_at (n k : Nat) (hk : k < n) :
    List.range n = List.range k ++ ([k] ++ (List.range (n - k - 1)).map (· + (k + 1))) := by
  conv_lhs => rw [show n = (k + 1) + (n - k - 1) from by omega]
  rw [List.range_add, List.range_succ, List.append_assoc]
  congr 1; congr 1
  ext x; simp [Nat.add_comm]

/-- Decompose scalarGreedyMask to extract the contribution at position k. -/
private theorem scalarGreedyMask_at_k (winners : List Reduction.Winner) (validLen : Nat)
    (k : Nat) (hk : k < winners.length) :
    let prev := scalarGreedyMaskAux winners validLen (List.range k) 0
      (List.replicate winners.length false)
    (scalarGreedyMask winners validLen).getD k false =
      (scalarGreedyMaskAux winners validLen [k] prev.1 prev.2).2.getD k false := by
  simp only [scalarGreedyMask]
  rw [range_decompose_at winners.length k hk]
  rw [scalarGreedyMaskAux_append, scalarGreedyMaskAux_append]
  set prev := scalarGreedyMaskAux winners validLen (List.range k) 0
    (List.replicate winners.length false)
  set step := scalarGreedyMaskAux winners validLen [k] prev.1 prev.2
  have h_not_mem : k ∉ (List.range (winners.length - k - 1)).map (· + (k + 1)) := by
    simp [List.mem_map]; intro a _ ha; omega
  exact scalarGreedyMaskAux_unchanged _ _ _ _ _ k h_not_mem

private theorem scalarGreedyMaskAux_length' (winners : List Reduction.Winner) (validLen : Nat)
    (positions : List Nat) (coveredUntil : Nat) (mask : List Bool)
    (h_mask : mask.length = winners.length)
    (h_pos : ∀ p ∈ positions, p < winners.length) :
    (scalarGreedyMaskAux winners validLen positions coveredUntil mask).2.length = winners.length := by
  induction positions generalizing coveredUntil mask with
  | nil => exact h_mask
  | cons i rest ih =>
    have hi : i < winners.length := h_pos i (by simp)
    have h_rest : ∀ p ∈ rest, p < winners.length := fun p hp => h_pos p (by simp [hp])
    simp only [scalarGreedyMaskAux]
    cases hw : winners[i]? with
    | none =>
      simp only [hw]
      exact ih coveredUntil mask h_mask h_rest
    | some w =>
      simp only [hw]
      by_cases hcond : w.len > 0 ∧ i ≥ coveredUntil ∧ i < validLen
      · simp only [hcond, and_self, decide_true, ite_true]
        exact ih (i + w.len) (mask.set i true) (by simp [List.length_set, h_mask]) h_rest
      · simp only [show ¬(w.len > 0 ∧ i ≥ coveredUntil ∧ i < validLen) from hcond, ite_false]
        exact ih coveredUntil mask h_mask h_rest

private theorem prev_mask_length (winners : List Reduction.Winner) (validLen : Nat) (k : Nat)
    (hk : k ≤ winners.length) :
    (scalarGreedyMaskAux winners validLen (List.range k) 0
      (List.replicate winners.length false)).2.length = winners.length := by
  apply scalarGreedyMaskAux_length'
  · simp
  · intro p hp; simp [List.mem_range] at hp; omega

/-- The scalar walk's state after processing range(0..k) matches coveredBeforeRec
    and the mask agrees with scalarGreedyMask on positions < k. -/
private theorem scalarGreedyMask_characterize (winners : List Reduction.Winner) (validLen : Nat)
    (h_valid : validLen ≤ winners.length) :
    ∀ k, k ≤ winners.length →
    let state := scalarGreedyMaskAux winners validLen (List.range k) 0
      (List.replicate winners.length false)
    state.1 = coveredBeforeRec (scalarGreedyMask winners validLen) winners k ∧
    (∀ j, j < k → state.2.getD j false = (scalarGreedyMask winners validLen).getD j false) := by
  intro k
  induction k with
  | zero => intro _; simp [scalarGreedyMaskAux, coveredBeforeRec]
  | succ k ih =>
    intro hk
    obtain ⟨ih_cu, ih_mask⟩ := ih (by omega)
    rw [show List.range (k + 1) = List.range k ++ [k] from List.range_succ]
    rw [scalarGreedyMaskAux_append]
    set prev := scalarGreedyMaskAux winners validLen (List.range k) 0
      (List.replicate winners.length false)
    have hk_lt : k < winners.length := by omega
    -- Get scalarGreedyMask[k] via decomposition
    have h_sgm_at_k := scalarGreedyMask_at_k winners validLen k hk_lt
    -- Unfold scalarGreedyMaskAux on [k]
    unfold scalarGreedyMaskAux
    cases hw : winners[k]? with
    | none => exfalso; simp [List.getElem?_eq_none_iff] at hw; omega
    | some w =>
      simp only [hw, scalarGreedyMaskAux]
      -- Determine scalarGreedyMask[k] from the decomposition
      have h_sgm_val : (scalarGreedyMask winners validLen).getD k false =
          (if w.len > 0 ∧ k ≥ prev.1 ∧ k < validLen then true else false) := by
        rw [h_sgm_at_k]
        unfold scalarGreedyMaskAux
        simp only [hw, scalarGreedyMaskAux]
        split
        · -- condition holds => mask.set k true, getD k = true
          have h_prev_len := prev_mask_length winners validLen k (by omega)
          simp only [List.getD, List.getElem?_set, show k = k from rfl, ite_true, h_prev_len, hk_lt]
          rfl
        · -- condition false => prev.2.getD k = false
          rename_i hcond
          have hk_not : k ∉ List.range k := by simp
          rw [scalarGreedyMaskAux_unchanged _ _ _ _ _ k hk_not]
          exact replicate_getD_false _ _
      split
      · -- condition holds: selected
        rename_i hcond
        constructor
        · -- coveredUntil = k + w.len = coveredBeforeRec(sgm, k+1)
          simp only [coveredBeforeRec, ← ih_cu]
          rw [h_sgm_val, if_pos hcond]
          simp [hw]
          have : prev.1 ≤ k := hcond.2.1; omega
        · intro j hj
          by_cases hjk : j = k
          · subst hjk
            -- After subst, k is gone and j is used everywhere
            rw [h_sgm_val, if_pos hcond]
            have h_prev_len2 := prev_mask_length winners validLen j (by omega)
            have hj_lt_prev : j < prev.2.length := by rw [h_prev_len2]; exact hk_lt
            simp [List.getD, List.getElem?_set, hj_lt_prev]
          · have hj' : j < k := by omega
            simp only [List.getD, List.getElem?_set]
            split
            · rename_i heq; exact absurd heq (Ne.symm hjk)
            · exact ih_mask j hj'
      · -- condition false: not selected
        rename_i hcond
        constructor
        · simp only [coveredBeforeRec, ← ih_cu]
          rw [h_sgm_val, if_neg hcond]; simp [hw]
        · intro j hj
          by_cases hjk : j < k
          · exact ih_mask j hjk
          · have hjk_eq : j = k := by omega
            subst hjk_eq
            rw [h_sgm_val, if_neg hcond]
            have hj_not : j ∉ List.range j := by simp
            rw [scalarGreedyMaskAux_unchanged _ _ _ _ _ j hj_not]
            exact replicate_getD_false _ _

/-- scalarGreedyMask[i] = positive[i] && decide(i >= coveredBeforeRec(scalarGreedyMask, i)). -/
private theorem scalarGreedyMask_getD_eq (winners : List Reduction.Winner) (validLen : Nat)
    (h_valid : validLen ≤ winners.length) (i : Nat) (hi : i < winners.length) :
    (scalarGreedyMask winners validLen).getD i false =
    ((mkPositive winners validLen).getD i false &&
     decide (i ≥ coveredBeforeRec (scalarGreedyMask winners validLen) winners i)) := by
  have ⟨h_cu, _⟩ := scalarGreedyMask_characterize winners validLen h_valid i (by omega)
  set prev := scalarGreedyMaskAux winners validLen (List.range i) 0
    (List.replicate winners.length false)
  have h_decomp := scalarGreedyMask_at_k winners validLen i hi
  rw [h_decomp, ← h_cu]
  -- Analyze scalarGreedyMaskAux on [i]
  unfold scalarGreedyMaskAux
  cases hw : winners[i]? with
  | none => exfalso; simp [List.getElem?_eq_none_iff] at hw; omega
  | some w =>
    simp only [hw, scalarGreedyMaskAux]
    have h_pos : (mkPositive winners validLen).getD i false =
        (decide (w.len > 0) && decide (i < validLen)) := by
      simp only [mkPositive, arange, MLX.arange]
      rw [getD_zipWith_and]
      congr 1
      · simp only [List.getD, List.getElem?_map, hw, Option.map_some]; rfl
      · simp only [List.getD, List.getElem?_map, List.getElem?_range hi, Option.map_some]; rfl
    rw [h_pos]
    split
    · -- condition holds
      rename_i hcond
      have h_prev_len3 := prev_mask_length winners validLen i (by omega)
      simp only [List.getD, List.getElem?_set, show i = i from rfl, ite_true, h_prev_len3, hi]
      simp [hcond.1, hcond.2.2]
      exact hcond.2.1
    · -- condition false
      rename_i hcond
      have hi_not : i ∉ List.range i := by simp
      rw [scalarGreedyMaskAux_unchanged _ _ _ _ _ i hi_not]
      rw [replicate_getD_false]
      -- hcond : ¬(w.len > 0 ∧ i ≥ prev.fst ∧ i < validLen)
      -- goal: false = decide(w.len > 0) && decide(i < validLen) && decide(i ≥ coveredBeforeRec...)
      -- Since condition is false, at least one of the three must fail
      by_cases hw0 : w.len > 0
      · by_cases hv : i < validLen
        · -- Both w.len > 0 and i < validLen hold, so i < prev.fst
          have h_not_ge : ¬(i ≥ prev.fst) := fun h_ge => hcond ⟨hw0, h_ge, hv⟩
          simp [hw0, hv]
          omega
        · simp [hv]
      · simp [hw0]

private theorem scalarGreedyMask_length' (winners : List Reduction.Winner) (validLen : Nat) :
    (scalarGreedyMask winners validLen).length = winners.length := by
  unfold scalarGreedyMask
  apply scalarGreedyMaskAux_length'
  · simp
  · intro p hp; simp [List.mem_range] at hp; exact hp

/-- The scalar greedy mask satisfies the iterStep fixpoint equation at each position. -/
private theorem scalarGreedyMask_is_fixpoint (winners : List Reduction.Winner) (validLen : Nat)
    (h_valid : validLen ≤ winners.length) :
    ∀ i, i < winners.length →
      (scalarGreedyMask winners validLen).getD i false =
      (iterStep winners validLen (scalarGreedyMask winners validLen)).getD i false := by
  intro i hi
  rw [scalarGreedyMask_getD_eq winners validLen h_valid i hi]
  rw [iterStep_getD_eq' winners validLen _ i hi (scalarGreedyMask_length' winners validLen)]

private theorem scalarGreedyMaskAux_length (winners : List Reduction.Winner) (validLen : Nat)
    (positions : List Nat) (coveredUntil : Nat) (mask : List Bool)
    (h_mask : mask.length = winners.length)
    (h_pos : ∀ p ∈ positions, p < winners.length) :
    (scalarGreedyMaskAux winners validLen positions coveredUntil mask).2.length = winners.length := by
  induction positions generalizing coveredUntil mask with
  | nil => exact h_mask
  | cons i rest ih =>
    have hi : i < winners.length := h_pos i (by simp)
    have h_rest : ∀ p ∈ rest, p < winners.length := fun p hp => h_pos p (by simp [hp])
    simp only [scalarGreedyMaskAux]
    cases hw : winners[i]? with
    | none =>
      simp only [hw]
      exact ih coveredUntil mask h_mask h_rest
    | some w =>
      simp only [hw]
      by_cases hcond : w.len > 0 ∧ i ≥ coveredUntil ∧ i < validLen
      · simp only [hcond, and_self, decide_true, ite_true]
        exact ih (i + w.len) (mask.set i true) (by simp [List.length_set, h_mask]) h_rest
      · simp only [show ¬(w.len > 0 ∧ i ≥ coveredUntil ∧ i < validLen) from hcond, ite_false]
        exact ih coveredUntil mask h_mask h_rest

private theorem scalarGreedyMask_length (winners : List Reduction.Winner) (validLen : Nat) :
    (scalarGreedyMask winners validLen).length = winners.length := by
  unfold scalarGreedyMask
  apply scalarGreedyMaskAux_length
  · simp
  · intro p hp; simp [List.mem_range] at hp; exact hp

private theorem scalarGreedyMaskAux_false_beyond (winners : List Reduction.Winner) (validLen : Nat)
    (positions : List Nat) (coveredUntil : Nat) (mask : List Bool)
    (h_mask : mask.length = winners.length)
    (h_pos : ∀ p ∈ positions, p < winners.length)
    (h_init : ∀ i, i ≥ validLen → mask.getD i false = false) :
    ∀ i, i ≥ validLen →
    (scalarGreedyMaskAux winners validLen positions coveredUntil mask).2.getD i false = false := by
  induction positions generalizing coveredUntil mask with
  | nil => exact h_init
  | cons p rest ih =>
    have hp_len : p < winners.length := h_pos p (by simp)
    have h_rest : ∀ q ∈ rest, q < winners.length := fun q hq => h_pos q (by simp [hq])
    simp only [scalarGreedyMaskAux]
    cases hw : winners[p]? with
    | none =>
      simp only [hw]
      exact ih coveredUntil mask h_mask h_rest h_init
    | some w =>
      simp only [hw]
      by_cases hcond : w.len > 0 ∧ p ≥ coveredUntil ∧ p < validLen
      · simp only [hcond, and_self, decide_true, ite_true]
        apply ih (p + w.len) (mask.set p true) (by simp [List.length_set, h_mask]) h_rest
        intro i hi
        simp only [List.getD, List.getElem?_set]
        split
        · rename_i heq; omega
        · exact h_init i hi
      · simp only [show ¬(w.len > 0 ∧ p ≥ coveredUntil ∧ p < validLen) from hcond, ite_false]
        exact ih coveredUntil mask h_mask h_rest h_init

private theorem scalarGreedyMask_false_beyond (winners : List Reduction.Winner) (validLen : Nat)
    (h_valid : validLen ≤ winners.length) :
    ∀ i, i ≥ validLen → (scalarGreedyMask winners validLen).getD i false = false := by
  unfold scalarGreedyMask
  apply scalarGreedyMaskAux_false_beyond
  · simp
  · intro p hp; simp [List.mem_range] at hp; exact hp
  · intro i _
    simp only [List.getD, List.getElem?_replicate]
    split <;> simp

/-- Absorb filterMap into foldl. -/
private theorem filterMap_foldl_eq {α β γ : Type*} (f : α → Option β)
    (g : γ → β → γ) (init : γ) (l : List α) :
    (l.filterMap f).foldl g init =
    l.foldl (fun acc a => match f a with | some b => g acc b | none => acc) init := by
  induction l generalizing init with
  | nil => simp
  | cons a rest ih =>
    simp only [List.filterMap_cons]
    cases hfa : f a with
    | none => simp [hfa, ih]
    | some b => simp [hfa, ih]

/-- scalarGreedyMaskAux is identity for positions ≥ validLen. -/
private theorem scalarGreedyMaskAux_all_ge_validLen
    (winners : List Reduction.Winner) (validLen : Nat)
    (positions : List Nat) (cu : Nat) (mask : List Bool)
    (h_ge : ∀ p ∈ positions, p ≥ validLen) :
    scalarGreedyMaskAux winners validLen positions cu mask = (cu, mask) := by
  induction positions generalizing cu mask with
  | nil => simp [scalarGreedyMaskAux]
  | cons p rest ih =>
    have hp := h_ge p (.head rest)
    simp only [scalarGreedyMaskAux]
    cases hw : winners[p]? with
    | none => exact ih cu mask (fun q hq => h_ge q (.tail p hq))
    | some w =>
      simp only [hw]
      have : ¬(w.len > 0 ∧ p ≥ cu ∧ p < validLen) := by omega
      simp only [this, ite_false]
      exact ih cu mask (fun q hq => h_ge q (.tail p hq))

/-- Generalized zip-filterMap equivalence with offset. -/
private theorem zip_filterMap_offset
    (winners : List Reduction.Winner) (mask : List Bool) (offset : Nat)
    (h_len : mask.length = winners.length) :
    (List.zip ((List.range winners.length).map (· + offset)) (List.zip mask winners)).filterMap
      (fun ⟨i, sel, w⟩ => if sel then
        some (SelectedToken.mk i w.len w.ruleID w.tokenKindID w.mode) else none) =
    (List.range winners.length).filterMap (fun j =>
      if mask.getD j false then
        match winners[j]? with
        | some w => some (SelectedToken.mk (j + offset) w.len w.ruleID w.tokenKindID w.mode)
        | none => none
      else none) := by
  induction winners generalizing mask offset with
  | nil => simp
  | cons w ws ih =>
    cases mask with
    | nil => simp at h_len
    | cons sel rest =>
      simp only [List.length_cons] at h_len ⊢
      have h_rest : rest.length = ws.length := by omega
      rw [List.range_succ_eq_map]
      simp only [List.map_cons, List.map_map, List.zip_cons_cons,
        List.filterMap_cons, List.getD, List.getElem?_cons_zero, Option.getD, Nat.zero_add]
      cases sel <;> simp <;> {
        have h_ih := ih rest (offset + 1) h_rest
        have h_map : List.map ((· + offset) ∘ Nat.succ) (List.range ws.length) =
            List.map (· + (offset + 1)) (List.range ws.length) := by
          apply List.map_congr_left; intro x _
          show Nat.succ x + offset = x + (offset + 1); omega
        rw [h_map, h_ih]
        apply List.filterMap_congr; intro j _
        simp only [Function.comp, List.getElem?_cons_succ, List.getD]
        have : Nat.succ j + offset = j + (offset + 1) := by omega
        simp only [this, Option.getD]
      }

/-- Convert extractSelected from zip form to range-based filterMap. -/
private theorem extractSelected_eq_range_filterMap
    (winners : List Reduction.Winner) (mask : List Bool)
    (h_len : mask.length = winners.length) :
    extractSelected winners mask =
    (List.range winners.length).filterMap (fun i =>
      if mask.getD i false then
        match winners[i]? with
        | some w => some (SelectedToken.mk i w.len w.ruleID w.tokenKindID w.mode)
        | none => none
      else none) := by
  simp only [extractSelected]
  have h := zip_filterMap_offset winners mask 0 h_len
  simp only [Nat.add_zero, List.map_id'] at h
  exact h

/-- extractSelected position pairs equal filterMap from selectedMask + winner lengths. -/
theorem extractSelected_pairs (winners : List Reduction.Winner)
    (selectedMask : List Bool) (h_len : selectedMask.length = winners.length) :
    (extractSelected winners selectedMask).map (fun t => (t.startPos, t.length)) =
    (List.range winners.length).filterMap (fun i =>
      if (match selectedMask[i]? with | some true => true | _ => false) then
        some (i, match (winners.map (·.len))[i]? with | some v => v | none => 0)
      else none) := by
  rw [extractSelected_eq_range_filterMap winners selectedMask h_len, List.map_filterMap]
  apply List.filterMap_congr
  intro i hi
  -- LHS: Option.map (fun t => (t.startPos, t.length)) (if mask.getD i false then ...)
  -- RHS: if (match mask[i]? with ...) then some (i, ...) else none
  -- Both are none when mask[i] ≠ true, and produce (i, w.len) when mask[i] = true
  cases hs : selectedMask[i]? with
  | none => simp [List.getD, hs]
  | some sv =>
    cases sv with
    | false => simp [List.getD, hs]
    | true =>
      simp only [List.getD, hs, Option.getD]
      have hilt : i < winners.length := List.mem_range.mp hi
      have hw : winners[i]? ≠ none := by
        intro h; rw [List.getElem?_eq_none_iff] at h; omega
      obtain ⟨w, hw'⟩ := Option.ne_none_iff_exists'.mp hw
      simp only [hw', Option.map_some, List.getElem?_map, ite_true]

/-- The joint induction: scalarSelect's fold tracks coveredBeforeRec and produces
    the same tokens as filterMap on the mask. -/
private theorem scalarSelectFold_matches
    (winners : List Reduction.Winner) (validLen : Nat)
    (h_valid : validLen ≤ winners.length) :
    ∀ k, k ≤ validLen →
    let fold_result := (List.range k).foldl (fun (acc : Nat × List SelectedToken) (i : Nat) =>
      match winners[i]? with
      | some w =>
        if w.len > 0 && decide (i ≥ acc.1) then
          (i + w.len, acc.2 ++ [SelectedToken.mk i w.len w.ruleID w.tokenKindID w.mode])
        else acc
      | none => acc
    ) (0, [])
    -- (A) cu matches coveredBeforeRec
    fold_result.1 = coveredBeforeRec (scalarGreedyMask winners validLen) winners k ∧
    -- (B) tokens match filterMap on mask
    fold_result.2 = (List.range k).filterMap (fun i =>
      if (scalarGreedyMask winners validLen).getD i false then
        match winners[i]? with
        | some w => some (SelectedToken.mk i w.len w.ruleID w.tokenKindID w.mode)
        | none => none
      else none) := by
  intro k
  induction k with
  | zero => intro _; simp [coveredBeforeRec]
  | succ k ih =>
    intro hk
    have hk' : k ≤ validLen := by omega
    have hk_lt : k < validLen := by omega
    have hk_lt_n : k < winners.length := by omega
    obtain ⟨ih_cu, ih_tokens⟩ := ih hk'
    rw [show List.range (k + 1) = List.range k ++ [k] from List.range_succ]
    simp only [List.foldl_append, List.foldl_cons, List.foldl_nil]
    set fold_k := (List.range k).foldl (fun (acc : Nat × List SelectedToken) (i : Nat) =>
      match winners[i]? with
      | some w =>
        if w.len > 0 && decide (i ≥ acc.1) then
          (i + w.len, acc.2 ++ [SelectedToken.mk i w.len w.ruleID w.tokenKindID w.mode])
        else acc
      | none => acc
    ) (0, [])
    have hw : winners[k]? = some winners[k] := List.getElem?_eq_getElem hk_lt_n
    simp only [hw]
    -- Get mask characterization at k
    have h_sgm := scalarGreedyMask_getD_eq winners validLen h_valid k hk_lt_n
    have h_pos_k : (mkPositive winners validLen).getD k false =
        (decide (winners[k].len > 0) && decide (k < validLen)) := by
      simp only [mkPositive, arange, MLX.arange]
      rw [getD_zipWith_and]
      congr 1
      · simp only [List.getD, List.map_map, Function.comp, List.getElem?_map, hw, Option.map_some,
          Option.getD_some]
      · simp only [List.getD, List.getElem?_map, List.getElem?_range hk_lt_n, Option.map_some,
          Option.getD_some]
    rw [h_pos_k] at h_sgm
    simp only [show decide (k < validLen) = true from decide_eq_true hk_lt, Bool.and_true] at h_sgm
    -- h_sgm now : sgm.getD k false = decide(winners[k].len > 0) && decide(k ≥ coveredBeforeRec(...))
    by_cases h_sel : (decide (winners[k].len > 0) && decide (k ≥ coveredBeforeRec (scalarGreedyMask winners validLen) winners k)) = true
    · -- Selected
      have h_sgm_true : (scalarGreedyMask winners validLen).getD k false = true := by
        rw [h_sgm]; exact h_sel
      have h_fold_cond : (winners[k].len > 0 && decide (k ≥ fold_k.1)) = true := by
        rw [ih_cu]; exact h_sel
      -- Reduce the fold step
      have h_step : (if (winners[k].len > 0 && decide (k ≥ fold_k.fst)) = true then
          (k + winners[k].len, fold_k.snd ++ [SelectedToken.mk k winners[k].len winners[k].ruleID
            winners[k].tokenKindID winners[k].mode])
          else fold_k) =
        (k + winners[k].len, fold_k.snd ++ [SelectedToken.mk k winners[k].len winners[k].ruleID
            winners[k].tokenKindID winners[k].mode]) := if_pos h_fold_cond
      simp only [h_step]
      simp only [Bool.and_eq_true, decide_eq_true_eq] at h_sel
      constructor
      · -- cu = coveredBeforeRec at k+1
        have h_cbr : coveredBeforeRec (scalarGreedyMask winners validLen) winners (k + 1) =
            Nat.max (coveredBeforeRec (scalarGreedyMask winners validLen) winners k)
              (k + winners[k].len) := by
          simp only [coveredBeforeRec, h_sgm_true, hw]; simp
        rw [h_cbr]
        have : coveredBeforeRec (scalarGreedyMask winners validLen) winners k ≤ k + winners[k].len := by
          have := h_sel.2; omega
        exact (max_eq_right this).symm
      · rw [ih_tokens, List.filterMap_append, List.filterMap_cons, List.filterMap_nil]
        simp only [List.getD] at h_sgm_true
        simp [h_sgm_true, hw]
    · -- Not selected
      have h_sgm_false : (scalarGreedyMask winners validLen).getD k false = false := by
        rw [h_sgm]; simp only [Bool.not_eq_true] at h_sel; exact h_sel
      have h_fold_cond : (winners[k].len > 0 && decide (k ≥ fold_k.1)) = false := by
        rw [ih_cu]; simp only [Bool.not_eq_true] at h_sel; exact h_sel
      -- Reduce the fold step
      have h_step : (if (winners[k].len > 0 && decide (k ≥ fold_k.fst)) = true then
          (k + winners[k].len, fold_k.snd ++ [SelectedToken.mk k winners[k].len winners[k].ruleID
            winners[k].tokenKindID winners[k].mode])
          else fold_k) = fold_k := by simp [h_fold_cond]
      simp only [h_step]
      constructor
      · rw [ih_cu]
        have h_cbr : coveredBeforeRec (scalarGreedyMask winners validLen) winners (k + 1) =
            coveredBeforeRec (scalarGreedyMask winners validLen) winners k := by
          simp only [coveredBeforeRec, h_sgm_false]; simp
        rw [h_cbr]
      · rw [ih_tokens, List.filterMap_append, List.filterMap_cons, List.filterMap_nil]
        simp only [List.getD] at h_sgm_false
        simp [h_sgm_false]

/-- Positions ≥ validLen contribute nothing to filterMap when mask is false there. -/
private theorem range_filterMap_beyond_empty
    (winners : List Reduction.Winner) (validLen : Nat)
    (h_valid : validLen ≤ winners.length)
    (mask : List Bool) (h_beyond : ∀ i, i ≥ validLen → mask.getD i false = false) :
    ((List.range (winners.length - validLen)).map (· + validLen)).filterMap (fun i =>
      if mask.getD i false then
        match winners[i]? with
        | some w => some (SelectedToken.mk i w.len w.ruleID w.tokenKindID w.mode)
        | none => none
      else none) = [] := by
  suffices h : ∀ (ps : List Nat), (∀ p ∈ ps, p ≥ validLen) →
      ps.filterMap (fun i =>
        if mask.getD i false then
          match winners[i]? with
          | some w => some (SelectedToken.mk i w.len w.ruleID w.tokenKindID w.mode)
          | none => none
        else none) = [] by
    apply h
    intro p hp
    simp only [List.mem_map, List.mem_range] at hp
    obtain ⟨j, _, rfl⟩ := hp; omega
  intro ps hps
  induction ps with
  | nil => simp
  | cons p rest ih =>
    have hp : mask.getD p false = false := h_beyond _ (hps p (.head rest))
    have h_rest := ih (fun q hq => hps q (.tail p hq))
    simp only [List.filterMap_cons, hp, Bool.false_eq_true, ↓reduceIte]
    exact h_rest

/-- Trimming: filterMap on range n = filterMap on range m when f i = none for i ≥ m. -/
private theorem filterMap_range_eq_of_none_beyond {α : Type*} (f : Nat → Option α)
    (n m : Nat) (h : m ≤ n)
    (h_beyond : ∀ i, m ≤ i → i < n → f i = none) :
    (List.range n).filterMap f = (List.range m).filterMap f := by
  induction n with
  | zero => simp; omega
  | succ n ih =>
    by_cases hn : m = n + 1
    · subst hn; rfl
    · have hm_le_n : m ≤ n := by omega
      have hfn : f n = none := h_beyond n (by omega) (by omega)
      simp only [List.range_succ, List.filterMap_append, List.filterMap_cons,
        List.filterMap_nil, hfn, List.append_nil]
      exact ih hm_le_n (fun i hi1 hi2 => h_beyond i hi1 (by omega))

/-- Bridge: the filterMap-then-foldl form of scalarSelect equals the direct foldl form. -/
private theorem scalarSelect_fold_bridge (winners : List Reduction.Winner) (l : List Nat)
    (init : Nat × List SelectedToken) :
    ((l.filterMap (fun i =>
      match winners[i]? with
      | some w => some (i, w)
      | none => none)).foldl (fun (acc : Nat × List SelectedToken) (iw : Nat × Reduction.Winner) =>
      let (coveredUntil, selected) := acc
      let (i, w) := iw
      if w.len > 0 && i ≥ coveredUntil then
        (i + w.len, selected ++ [SelectedToken.mk i w.len w.ruleID w.tokenKindID w.mode])
      else (coveredUntil, selected)) init) =
    (l.foldl (fun (acc : Nat × List SelectedToken) (i : Nat) =>
      match winners[i]? with
      | some w =>
        if w.len > 0 && decide (i ≥ acc.1) then
          (i + w.len, acc.2 ++ [SelectedToken.mk i w.len w.ruleID w.tokenKindID w.mode])
        else acc
      | none => acc) init) := by
  induction l generalizing init with
  | nil => simp
  | cons a rest ih =>
    simp only [List.filterMap_cons]
    cases ha : winners[a]? with
    | none => simp only [ha, List.foldl_cons]; exact ih init
    | some w => simp only [ha, List.foldl_cons]; exact ih _

/-- extractSelected on the scalar greedy mask gives the same list as scalarSelect. -/
private theorem extractSelected_scalarGreedyMask (winners : List Reduction.Winner) (validLen : Nat)
    (h_valid : validLen ≤ winners.length) :
    extractSelected winners (scalarGreedyMask winners validLen) =
    scalarSelect winners validLen := by
  -- Step 1: Convert extractSelected to range-based filterMap
  rw [extractSelected_eq_range_filterMap _ _ (scalarGreedyMask_length winners validLen)]
  -- Step 2: Trim range(n) to range(validLen) since mask is false beyond
  rw [filterMap_range_eq_of_none_beyond _ _ _ h_valid]
  · -- Step 3: Use scalarSelectFold_matches and bridge
    have ⟨_, h_tokens⟩ := scalarSelectFold_matches winners validLen h_valid validLen le_rfl
    simp only [scalarSelect]
    rw [scalarSelect_fold_bridge]
    exact h_tokens.symm
  · intro i hi _
    have hf := scalarGreedyMask_false_beyond winners validLen h_valid i hi
    simp only [List.getD] at hf
    simp [hf]

theorem selection_equiv (winners : List Reduction.Winner) (validLen : Nat)
    (h_valid : validLen ≤ winners.length) :
    extractSelected winners (vectorizedSelect winners validLen) =
    scalarSelect winners validLen := by
  -- Step 1: Show vectorizedSelect = maskAfter validLen
  rw [vectorizedSelect_eq_maskAfter]
  -- Step 2: By fixpoint uniqueness, maskAfter agrees with scalarGreedyMask
  have h_mask_eq : ∀ i, i < winners.length →
      (maskAfter winners validLen validLen).getD i false =
      (scalarGreedyMask winners validLen).getD i false := by
    intro i hi
    rw [← fixpoint_unique_pointwise winners validLen h_valid
      (scalarGreedyMask winners validLen)
      (scalarGreedyMask_length winners validLen)
      (scalarGreedyMask_is_fixpoint winners validLen h_valid)
      (scalarGreedyMask_false_beyond winners validLen h_valid) i hi]
  -- Step 3: extractSelected respects pointwise mask equality
  rw [extractSelected_ext winners _ _ (maskAfter_length winners validLen validLen)
      (scalarGreedyMask_length winners validLen) h_mask_eq]
  -- Step 4: extractSelected on scalarGreedyMask = scalarSelect
  exact extractSelected_scalarGreedyMask winners validLen h_valid

theorem vectorizedSelect_length (winners : List Reduction.Winner) (validLen : Nat) :
    (vectorizedSelect winners validLen).length = winners.length := by
  rw [vectorizedSelect_eq_maskAfter]; exact maskAfter_length winners validLen validLen

end Selection
