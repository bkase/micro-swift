import Mathlib.Data.List.Basic
import MicroSwiftProofs.Emission

namespace TestBCM
open Emission

private def cumSum (d : List Int) (p : Nat) : Int :=
  (List.range (p + 1)).foldl (fun acc j => acc + d.getD j 0) 0

private theorem cumSum_zero (d : List Int) : cumSum d 0 = d.getD 0 0 := by
  simp [cumSum, List.range_succ, List.range_zero]

private theorem cumSum_succ (d : List Int) (p : Nat) :
    cumSum d (p + 1) = cumSum d p + d.getD (p + 1) 0 := by
  simp only [cumSum, Nat.add_eq, Nat.add_zero]
  rw [List.range_succ, List.foldl_append]; simp

private theorem getD_replicate_zero (n j : Nat) :
    (List.replicate n (0 : Int)).getD j 0 = 0 := by
  simp [List.getD, List.getElem?_replicate]; split <;> simp

private theorem cumSum_zeros (n p : Nat) :
    cumSum (List.replicate n (0 : Int)) p = 0 := by
  induction p with
  | zero => rw [cumSum_zero, getD_replicate_zero]
  | succ p ih => rw [cumSum_succ, getD_replicate_zero, ih]; simp

private theorem getD_set_Int (d : List Int) (k j : Nat) (v : Int) :
    (d.set k v).getD j 0 =
    if j = k ∧ k < d.length then v else d.getD j 0 := by
  simp only [List.getD, List.getElem?_set]
  split <;> split <;> simp_all <;> omega

private theorem cumSum_set (d : List Int) (k : Nat) (v : Int) (p : Nat) :
    cumSum (d.set k v) p =
    cumSum d p + if k ≤ p ∧ k < d.length then v - d.getD k 0 else 0 := by
  induction p with
  | zero =>
    rw [cumSum_zero, cumSum_zero, getD_set_Int]
    split <;> split <;> simp_all <;> omega
  | succ p ih =>
    rw [cumSum_succ, cumSum_succ, ih, getD_set_Int]
    -- Three cases: k ≤ p, k = p+1, k > p+1
    by_cases hle : k ≤ p
    · -- k ≤ p, k ≠ p+1
      have hne : ¬(p + 1 = k ∧ k < d.length) := by omega
      simp only [hne, ite_false]
      by_cases hkl : k < d.length
      · simp [hle, hkl, show k ≤ p + 1 by omega]; omega
      · have : ¬(k ≤ p ∧ k < d.length) := fun h => hkl h.2
        have : ¬(k ≤ p + 1 ∧ k < d.length) := fun h => hkl h.2
        simp [*]
    · by_cases hke : k = p + 1
      · -- k = p+1; after subst, k is gone, use p+1
        subst hke
        have hne : ¬(p + 1 ≤ p ∧ p + 1 < d.length) := by omega
        simp only [hne, ite_false, show (p + 1 = p + 1) from rfl, true_and]
        by_cases hkl : p + 1 < d.length
        · simp [hkl, show p + 1 ≤ p + 1 from le_refl _]; omega
        · have : ¬(p + 1 ≤ p + 1 ∧ p + 1 < d.length) := fun h => hkl h.2
          simp [hkl, this]
      · -- k > p+1
        have h1 : ¬(k ≤ p ∧ k < d.length) := by omega
        have h2 : ¬(k ≤ p + 1 ∧ k < d.length) := by omega
        have h3 : ¬(p + 1 = k ∧ k < d.length) := by omega
        simp [h1, h2, h3]

-- ═══ Part 2: Delta body and its effect on cumSum ═══

/-- The delta fold body, exactly matching buildCoverageMask's inner fold -/
private def deltaBody (d : List Int) (sl : Nat × Nat) : List Int :=
  let start := sl.1
  let length := sl.2
  let end_ := start + length
  let d1 := d.set start ((match d[start]? with | some v => v | none => 0) + 1)
  if end_ < d.length then
    d1.set end_ ((match d1[end_]? with | some v => v | none => 0) - 1)
  else d1

private theorem deltaBody_length (d : List Int) (sl : Nat × Nat) :
    (deltaBody d sl).length = d.length := by
  simp only [deltaBody]; split <;> simp [List.length_set]

private theorem deltaFold_length (tokens : List (Nat × Nat)) (d : List Int) :
    (tokens.foldl deltaBody d).length = d.length := by
  induction tokens generalizing d with
  | nil => simp
  | cons t rest ih => simp only [List.foldl_cons]; rw [ih, deltaBody_length]

/-- Effect of deltaBody on cumSum: adds 1 if s ≤ p, subtracts 1 if s+l ≤ p and in range -/
private theorem cumSum_deltaBody (d : List Int) (s l p : Nat) :
    cumSum (deltaBody d (s, l)) p =
    cumSum d p + (if s ≤ p ∧ s < d.length then 1 else 0) +
    (if s + l ≤ p ∧ s + l < d.length then -1 else 0) := by
  simp only [deltaBody, match_eq_getD]
  split
  · -- end_ < d.length: result is double set
    rename_i h_end
    rw [cumSum_set, cumSum_set]
    simp only [List.length_set]
    -- Simplify the getD differences
    -- Inner set: v - d.getD s 0 = (d.getD s 0 + 1) - d.getD s 0 = 1
    -- Outer set: v - d'.getD (s+l) 0 = (d'.getD (s+l) 0 - 1) - d'.getD (s+l) 0 = -1
    -- where d' = d.set s (d.getD s 0 + 1)
    by_cases hs : s ≤ p ∧ s < d.length
    · by_cases hsl : s + l ≤ p ∧ s + l < d.length
      · simp [hs, hsl]; omega
      · simp [hs, hsl]; omega
    · by_cases hsl : s + l ≤ p ∧ s + l < d.length
      · simp [hs, hsl]; omega
      · simp [hs, hsl]
  · -- end_ ≥ d.length: result is single set
    rename_i h_end
    push_neg at h_end; rw [cumSum_set]
    by_cases hs : s ≤ p ∧ s < d.length
    · simp [hs]
      have : ¬(s + l ≤ p ∧ s + l < d.length) := by omega
      simp [this]; omega
    · simp [hs]
      have : ¬(s + l ≤ p ∧ s + l < d.length) := by
        intro ⟨h1, h2⟩; exact hs ⟨by omega, by omega⟩
      simp [this]

-- ═══ Part 3: countCovering (recursive definition) ═══

private def countCovering : List (Nat × Nat) → Nat → Int
  | [], _ => 0
  | (s, l) :: rest, p => (if s ≤ p ∧ p < s + l then 1 else 0) + countCovering rest p

/-- After processing all tokens from zeros, cumSum = countCovering (for p < pageSize) -/
private theorem cumSum_fold_eq (tokens : List (Nat × Nat)) (pageSize p : Nat) (hp : p < pageSize) :
    cumSum (tokens.foldl deltaBody (List.replicate (pageSize + 1) (0 : Int))) p =
    countCovering tokens p := by
  suffices h : ∀ (d : List Int), d.length = pageSize + 1 →
      cumSum (tokens.foldl deltaBody d) p = cumSum d p + countCovering tokens p by
    rw [h _ (by simp), cumSum_zeros]; simp
  intro d hd_len
  induction tokens generalizing d with
  | nil => simp [countCovering]
  | cons t rest ih =>
    obtain ⟨s, l⟩ := t
    simp only [List.foldl_cons, countCovering]
    rw [ih _ (by rw [deltaBody_length, hd_len])]
    rw [cumSum_deltaBody, hd_len]
    -- Goal: cumSum d p + [s ≤ p ∧ s < ps+1 ? 1 : 0] + [s+l ≤ p ∧ s+l < ps+1 ? -1 : 0]
    --       + countCovering rest p
    --     = cumSum d p + ([s ≤ p ∧ p < s+l ? 1 : 0] + countCovering rest p)
    by_cases hs : s ≤ p
    · have hs_lt : s < pageSize + 1 := by omega
      by_cases hsl : s + l ≤ p
      · have hsl_lt : s + l < pageSize + 1 := by omega
        have hnot : ¬(p < s + l) := by omega
        simp [hs, hs_lt, hsl, hsl_lt, hnot]; omega
      · push_neg at hsl
        simp [hs, hs_lt, show ¬(s + l ≤ p) from by omega, hsl]; omega
    · push_neg at hs
      have h1 : ¬(s ≤ p ∧ s < pageSize + 1) := by omega
      have h2 : ¬(s ≤ p ∧ p < s + l) := by omega
      have h3 : ¬(s + l ≤ p ∧ s + l < pageSize + 1) := by omega
      simp [h1, h2, h3]

-- ═══ Part 4: Prefix-sum fold characterization ═══

/-- match on getElem? equals getD -/
private theorem match_eq_getD (l : List Int) (i : Nat) :
    (match l[i]? with | some v => v | none => 0) = l.getD i 0 := by
  simp only [List.getD]; cases l[i]? <;> rfl

/-- The fold body matching buildCoverageMask's prefix-sum phase -/
private def prefSumStep (delta : List Int) (ra : Int × List Bool) (i : Nat) : Int × List Bool :=
  let r := ra.1 + (match delta[i]? with | some v => v | none => 0)
  (r, ra.2 ++ [decide (r > 0)])

private theorem getD_append_left' (l1 l2 : List Bool) (n : Nat) (d : Bool) (h : n < l1.length) :
    (l1 ++ l2).getD n d = l1.getD n d := by
  simp [List.getD, List.getElem?_append_left h]

private theorem getD_append_right' (l1 l2 : List Bool) (n : Nat) (d : Bool)
    (h : l1.length ≤ n) :
    (l1 ++ l2).getD n d = l2.getD (n - l1.length) d := by
  simp [List.getD, List.getElem?_append_right h]

/-- After folding over range n, the result has the right values -/
private theorem prefSum_fold_inv (delta : List Int) (n : Nat) :
    let result := (List.range n).foldl (prefSumStep delta) ((0 : Int), ([] : List Bool))
    result.1 = (if n = 0 then 0 else cumSum delta (n - 1)) ∧
    result.2.length = n ∧
    ∀ j, j < n → result.2.getD j false = decide (cumSum delta j > 0) := by
  induction n with
  | zero => simp [prefSumStep]
  | succ k ih =>
    simp only [List.range_succ, List.foldl_append, List.foldl_cons, List.foldl_nil]
    set prev := (List.range k).foldl (prefSumStep delta) (0, [])
    obtain ⟨h_run, h_len, h_vals⟩ := ih
    simp only [prefSumStep]
    refine ⟨?_, ?_, ?_⟩
    · -- running = cumSum delta k
      simp only [Nat.succ_ne_zero, ite_false, Nat.succ_sub_one, match_eq_getD]
      cases k with
      | zero => simp [h_run, cumSum_zero, List.getD]
      | succ m =>
        simp only [Nat.succ_ne_zero, ite_false, Nat.succ_sub_one] at h_run
        rw [h_run, cumSum_succ]
    · -- length = k + 1
      rw [List.length_append, h_len]; simp
    · -- values at each position
      intro j hj
      by_cases hjk : j < k
      · -- j < k: value was already in prev.2
        rw [getD_append_left' _ _ _ _ (by rw [h_len]; exact hjk)]
        exact h_vals j hjk
      · -- j = k: newly appended value
        have hjk_eq : j = k := by omega
        rw [hjk_eq]
        rw [getD_append_right' _ _ _ _ (by rw [h_len])]
        -- [v].getD 0 false = v, then show v = decide(cumSum delta k > 0)
        have hcs : prev.1 + (match delta[k]? with | some v => v | none => 0) = cumSum delta k := by
          rw [match_eq_getD]
          cases k with
          | zero => simp [h_run, cumSum_zero, List.getD]
          | succ m =>
            simp only [Nat.succ_ne_zero, ite_false, Nat.succ_sub_one] at h_run
            rw [h_run, cumSum_succ]
        simp [h_len, List.getD, hcs]

/-- getD of the prefix-sum fold -/
private theorem prefSum_fold_getD (delta : List Int) (pageSize p : Nat) (hp : p < pageSize) :
    ((List.range pageSize).foldl (fun (ra : Int × List Bool) i =>
      let r := ra.1 + (match delta[i]? with | some v => v | none => 0)
      (r, ra.2 ++ [decide (r > 0)])
    ) ((0 : Int), ([] : List Bool))).2.getD p false =
    decide (cumSum delta p > 0) := by
  -- The fold body is definitionally equal to prefSumStep
  show ((List.range pageSize).foldl (prefSumStep delta) ((0 : Int), ([] : List Bool))).2.getD p false =
      decide (cumSum delta p > 0)
  exact (prefSum_fold_inv delta pageSize).2.2 p hp

-- ═══ Part 5: decide(countCovering > 0) = any(covers) ═══

/-- countCovering is always ≥ 0 -/
private theorem countCovering_nonneg (tokens : List (Nat × Nat)) (p : Nat) :
    countCovering tokens p ≥ 0 := by
  induction tokens with
  | nil => simp [countCovering]
  | cons t rest ih =>
    obtain ⟨s, l⟩ := t; simp only [countCovering]; split <;> omega

private theorem decide_count_eq_any (tokens : List (Nat × Nat)) (p : Nat) :
    decide (countCovering tokens p > 0) =
    tokens.any (fun (s, l) => decide (p ≥ s ∧ p < s + l)) := by
  induction tokens with
  | nil => simp [countCovering]
  | cons t rest ih =>
    obtain ⟨s, l⟩ := t
    simp only [countCovering, List.any_cons]
    by_cases hcov : s ≤ p ∧ p < s + l
    · simp [hcov, show p ≥ s from hcov.1]
      have := countCovering_nonneg rest p; omega
    · have hncov : ¬(p ≥ s ∧ p < s + l) := by omega
      simp [hcov, hncov, ih]

-- ═══ Part 6: Main theorem ═══

private theorem buildCoverageMask_getD' (tokens : List (Nat × Nat)) (pageSize : Nat)
    (p : Nat) (hp : p < pageSize) :
    (buildCoverageMask tokens pageSize).getD p false =
    tokens.any (fun (s, l) => decide (p ≥ s ∧ p < s + l)) := by
  -- Unfold buildCoverageMask and show it equals our abstractions
  unfold buildCoverageMask
  -- The delta fold body is definitionally equal to deltaBody
  show ((List.range pageSize).foldl (fun (ra : Int × List Bool) i =>
      let r := ra.1 + (match (tokens.foldl deltaBody (List.replicate (pageSize + 1) (0 : Int)))[i]?
        with | some v => v | none => 0)
      (r, ra.2 ++ [decide (r > 0)])
    ) ((0 : Int), ([] : List Bool))).2.getD p false =
    tokens.any (fun (s, l) => decide (p ≥ s ∧ p < s + l))
  -- Apply prefix-sum characterization
  set delta := tokens.foldl deltaBody (List.replicate (pageSize + 1) (0 : Int))
  rw [prefSum_fold_getD delta pageSize p hp]
  rw [cumSum_fold_eq tokens pageSize p hp]
  exact decide_count_eq_any tokens p

end TestBCM
