import Mathlib.Data.List.Basic
import MicroSwiftProofs.MLXPrimitives
import MicroSwiftProofs.Selection

/-!
# Emission (Phases F/G)

Models `CoverageMask.swift` and the skip/error filtering from `TransportEmitter.swift`.

After greedy selection and keyword remapping, the emitter:
1. Builds a coverage mask (which bytes are covered by selected tokens)
2. Finds unknown (uncovered) bytes in the valid region → error spans
3. Optionally filters out skip-mode tokens (whitespace, comments)
4. Packs remaining tokens into the output format
-/

namespace Emission

open MLX

/-! ## Coverage Mask -/

/-- Build a coverage mask from selected tokens using delta-array + prefix sum.
    Mirrors `CoverageMask.build` in Swift.

    For each token [start, start+length), increment delta[start], decrement delta[end].
    Then prefix-sum the delta array: covered[i] = (running sum > 0). -/
def buildCoverageMask (tokens : List (Nat × Nat)) (pageSize : Nat) : List Bool :=
  let delta := tokens.foldl (fun d (start, length) =>
    let end_ := start + length
    let d1 := d.set start ((match d[start]? with | some v => v | none => 0) + 1)
    if end_ < d.length then
      d1.set end_ ((match d1[end_]? with | some v => v | none => 0) - 1)
    else d1
  ) (List.replicate (pageSize + 1) (0 : Int))
  let (_, covered) := (List.range pageSize).foldl (fun (running, acc) i =>
    let r := running + (match delta[i]? with | some v => v | none => 0)
    (r, acc ++ [decide (r > 0)])
  ) ((0 : Int), ([] : List Bool))
  covered

/-- Vectorized coverage mask using element-wise ops.
    Mirrors `TransportEmitter.buildCoverageMask` in Swift. -/
def vectorizedCoverageMask (selectedMask : List Bool) (lengths : List Nat)
    (pageSize : Nat) : List Bool :=
  let positions := arange pageSize
  (List.range pageSize).foldl (fun covered startPos =>
    let isSel := match selectedMask[startPos]? with | some true => true | _ => false
    if !isSel then covered
    else
      let len := match lengths[startPos]? with | some l => l | none => 0
      List.zipWith or covered
        (positions.map fun p => decide (p ≥ startPos ∧ p < startPos + len))
  ) (List.replicate pageSize false)

/-! ## Unknown Bytes and Error Spans -/

/-- Find uncovered bytes in the valid prefix. Mirrors `CoverageMask.unknownBytes`. -/
def unknownBytes (covered : List Bool) (validLen : Nat) : List Bool :=
  (List.range covered.length).map fun i =>
    if i < validLen then
      match covered[i]? with | some true => false | _ => true
    else false

/-- An error span: half-open range [start, end_). -/
structure ErrorSpan where
  start : Nat
  end_ : Nat
  deriving Repr, DecidableEq

/-- Build error spans from maximal runs of unknown bytes.
    Mirrors `CoverageMask.errorSpans` in Swift. -/
def errorSpans (unknown : List Bool) : List ErrorSpan :=
  let indexed : List (Nat × Bool) := (List.range unknown.length).map fun i =>
    (i, match unknown[i]? with | some b => b | _ => false)
  let result := indexed.foldl (fun (acc : Option Nat × List ErrorSpan) (pair : Nat × Bool) =>
    let (curStart, spans) := acc
    let (i, isUnk) := pair
    match isUnk, curStart with
    | true, none => (some i, spans)
    | true, some _ => (curStart, spans)
    | false, some s => (none, spans ++ [ErrorSpan.mk s i])
    | false, none => (none, spans)
  ) ((none : Option Nat), ([] : List ErrorSpan))
  match result.1 with
  | some s => result.2 ++ [ErrorSpan.mk s unknown.length]
  | none => result.2

/-! ## Skip Filtering -/

/-- Skip mode constant (matches `TransportEmitter.skipMode = 1`). -/
def skipMode : Nat := 1

/-- Filter out skip-mode tokens. Mirrors the `mode != skipMode` filter in Swift. -/
def filterSkipTokens (tokens : List Selection.SelectedToken) (emitSkip : Bool)
    : List Selection.SelectedToken :=
  if emitSkip then tokens
  else tokens.filter (fun t => decide (t.mode != skipMode))

/-! ## Equivalence -/

/-- Helper: getD of zipWith or = OR of getDs (when lists have equal length) -/
private theorem getD_zipWith_or (a b : List Bool) (i : Nat) (h_len : a.length = b.length) :
    (List.zipWith or a b).getD i false = (a.getD i false || b.getD i false) := by
  simp only [List.getD, List.getElem?_zipWith]
  cases ha : a[i]? with
  | none =>
    have hb : b[i]? = none := by
      rw [List.getElem?_eq_none_iff] at ha ⊢; omega
    simp [hb]
  | some va =>
    have hi : i < a.length := by
      simp only [List.getElem?_eq_some_iff] at ha; exact ha.1
    cases hb : b[i]? with
    | none =>
      exfalso; rw [List.getElem?_eq_none_iff] at hb; omega
    | some vb => simp

/-- The vectorized coverage mask correctly computes coverage:
    position p is covered iff some selected position s has s ≤ p < s + lengths[s].
    This is the semantic correctness theorem for the vectorized algorithm. -/
theorem coverage_vectorized_correct (selectedMask : List Bool) (lengths : List Nat) (pageSize : Nat)
    (h_aligned : selectedMask.length = pageSize) (h_lengths : lengths.length = pageSize)
    (p : Nat) (hp : p < pageSize) :
    (vectorizedCoverageMask selectedMask lengths pageSize).getD p false =
    (List.range pageSize).any (fun s =>
      (match selectedMask[s]? with | some true => true | _ => false) &&
      decide (p ≥ s ∧ p < s + (match lengths[s]? with | some l => l | none => 0))) := by
  simp only [vectorizedCoverageMask, arange, MLX.arange]
  -- Prove by induction: the fold OR-ing range masks computes the any predicate
  suffices h : ∀ (init : List Bool) (positions : List Nat),
      init.length = pageSize →
      (positions.foldl (fun covered startPos =>
        if !(match selectedMask[startPos]? with | some true => true | _ => false) then covered
        else
          List.zipWith or covered
            ((List.range pageSize).map fun q =>
              decide (q ≥ startPos ∧ q < startPos +
                (match lengths[startPos]? with | some l => l | none => 0))))
      init).getD p false =
      (init.getD p false || positions.any (fun s =>
        (match selectedMask[s]? with | some true => true | _ => false) &&
        decide (p ≥ s ∧ p < s + (match lengths[s]? with | some l => l | none => 0)))) by
    rw [h (List.replicate pageSize false) (List.range pageSize) (by simp)]
    simp only [List.getD, List.getElem?_replicate, hp, ite_true, Option.getD, Bool.false_or]
  intro init positions h_init
  induction positions generalizing init with
  | nil => simp
  | cons s rest ih =>
    simp only [List.foldl, List.any_cons]
    by_cases h_sel : (match selectedMask[s]? with | some true => true | _ => false) = true
    · -- Selected position: fold ORs in the range mask
      simp only [h_sel, Bool.not_true, Bool.false_eq_true, ite_false, Bool.true_and]
      rw [ih _ (by simp [List.length_zipWith, h_init, List.length_map, List.length_range])]
      rw [getD_zipWith_or _ _ _ (by simp [List.length_zipWith, h_init, List.length_map, List.length_range])]
      rw [Bool.or_assoc]
      congr 1; congr 1
      -- Range mask at index p = decide(p ≥ s ∧ p < s + len)
      simp only [List.getD, List.getElem?_map, List.getElem?_range, hp, ite_true, Option.map_some']
      simp
    · -- Not selected: skip
      have h_false : (match selectedMask[s]? with | some true => true | _ => false) = false := by
        cases h : selectedMask[s]? with
        | none => rfl
        | some v => cases v <;> simp_all
      simp only [h_false, Bool.not_false, ite_true]
      rw [ih init h_init]
      simp only [h_false, Bool.false_and, Bool.false_or]

/-- Length of vectorizedCoverageMask is pageSize. -/
private theorem vectorizedCoverageMask_length (selectedMask : List Bool) (lengths : List Nat)
    (pageSize : Nat) :
    (vectorizedCoverageMask selectedMask lengths pageSize).length = pageSize := by
  simp only [vectorizedCoverageMask, arange, MLX.arange]
  suffices h : ∀ (init : List Bool) (positions : List Nat),
      init.length = pageSize →
      (positions.foldl (fun covered startPos =>
        if !(match selectedMask[startPos]? with | some true => true | _ => false) then covered
        else List.zipWith or covered
          ((List.range pageSize).map fun p =>
            decide (p ≥ startPos ∧ p < startPos +
              (match lengths[startPos]? with | some l => l | none => 0))))
      init).length = pageSize by
    exact h _ _ (by simp)
  intro init positions h_init
  induction positions generalizing init with
  | nil => simp [h_init]
  | cons s rest ih =>
    simp only [List.foldl_cons]
    by_cases h_sel : (match selectedMask[s]? with | some true => true | _ => false) = true
    · simp only [h_sel, Bool.not_true, Bool.false_eq_true, ite_false]
      exact ih _ (by simp [List.length_zipWith, h_init, List.length_map, List.length_range])
    · have h_false : (match selectedMask[s]? with | some true => true | _ => false) = false := by
        cases h : selectedMask[s]? with
        | none => rfl
        | some v => cases v <;> simp_all
      simp only [h_false, Bool.not_false, ite_true]
      exact ih init h_init

/-- Length of buildCoverageMask is pageSize. -/
private theorem buildCoverageMask_length (tokens : List (Nat × Nat)) (pageSize : Nat) :
    (buildCoverageMask tokens pageSize).length = pageSize := by
  unfold buildCoverageMask
  -- Extract the covered list from the fold result
  -- The fold over range pageSize starts with (0, []) and appends one Bool per step
  -- So the result has length pageSize
  generalize hd : tokens.foldl _ _ = delta
  -- Now prove the prefix-sum fold produces a list of length pageSize
  have : ∀ (positions : List Nat) (running : Int) (acc : List Bool),
      ((positions).foldl (fun acc i =>
        let r := acc.1 + (match delta[i]? with | some v => v | none => 0)
        (r, acc.2 ++ [decide (r > 0)])
      ) (running, acc)).2.length = acc.length + positions.length := by
    intro positions
    induction positions with
    | nil => intro _ _; simp
    | cons p rest ih =>
      intro running acc
      simp only [List.foldl_cons, List.length_cons]
      rw [ih]; simp [List.length_append]; omega
  simpa using this (List.range pageSize) 0 []

-- ── Helpers for buildCoverageMask_getD ──

private def bcm_cumSum (d : List Int) (p : Nat) : Int :=
  (List.range (p + 1)).foldl (fun acc j => acc + d.getD j 0) 0

private theorem bcm_cumSum_zero (d : List Int) : bcm_cumSum d 0 = d.getD 0 0 := by
  simp [bcm_cumSum, List.range_succ, List.range_zero]

private theorem bcm_cumSum_succ (d : List Int) (p : Nat) :
    bcm_cumSum d (p + 1) = bcm_cumSum d p + d.getD (p + 1) 0 := by
  simp only [bcm_cumSum, Nat.add_eq, Nat.add_zero]
  rw [List.range_succ, List.foldl_append]; simp

private theorem bcm_getD_replicate_zero (n j : Nat) :
    (List.replicate n (0 : Int)).getD j 0 = 0 := by
  simp [List.getD, List.getElem?_replicate]; split <;> simp

private theorem bcm_cumSum_zeros (n p : Nat) :
    bcm_cumSum (List.replicate n (0 : Int)) p = 0 := by
  induction p with
  | zero => rw [bcm_cumSum_zero, bcm_getD_replicate_zero]
  | succ p ih => rw [bcm_cumSum_succ, bcm_getD_replicate_zero, ih]; simp

private theorem bcm_getD_set_Int (d : List Int) (k j : Nat) (v : Int) :
    (d.set k v).getD j 0 =
    if j = k ∧ k < d.length then v else d.getD j 0 := by
  simp only [List.getD, List.getElem?_set]
  split <;> split <;> simp_all <;> omega

private theorem bcm_cumSum_set (d : List Int) (k : Nat) (v : Int) (p : Nat) :
    bcm_cumSum (d.set k v) p =
    bcm_cumSum d p + if k ≤ p ∧ k < d.length then v - d.getD k 0 else 0 := by
  induction p with
  | zero =>
    rw [bcm_cumSum_zero, bcm_cumSum_zero, bcm_getD_set_Int]
    split <;> split <;> simp_all <;> omega
  | succ p ih =>
    rw [bcm_cumSum_succ, bcm_cumSum_succ, ih, bcm_getD_set_Int]
    by_cases hle : k ≤ p
    · have hne : ¬(p + 1 = k ∧ k < d.length) := by omega
      simp only [hne, ite_false]
      by_cases hkl : k < d.length
      · simp [hle, hkl, show k ≤ p + 1 by omega]; omega
      · have : ¬(k ≤ p ∧ k < d.length) := fun h => hkl h.2
        have : ¬(k ≤ p + 1 ∧ k < d.length) := fun h => hkl h.2
        simp [*]
    · by_cases hke : k = p + 1
      · subst hke
        have hne : ¬(p + 1 ≤ p ∧ p + 1 < d.length) := by omega
        simp only [hne, ite_false, show (p + 1 = p + 1) from rfl, true_and]
        by_cases hkl : p + 1 < d.length
        · simp [hkl, show p + 1 ≤ p + 1 from le_refl _]; omega
        · have : ¬(p + 1 ≤ p + 1 ∧ p + 1 < d.length) := fun h => hkl h.2
          simp [hkl, this]
      · have h1 : ¬(k ≤ p ∧ k < d.length) := by omega
        have h2 : ¬(k ≤ p + 1 ∧ k < d.length) := by omega
        have h3 : ¬(p + 1 = k ∧ k < d.length) := by omega
        simp [h1, h2, h3]

private theorem bcm_match_eq_getD (l : List Int) (i : Nat) :
    (match l[i]? with | some v => v | none => 0) = l.getD i 0 := by
  simp only [List.getD]; cases l[i]? <;> rfl

private def bcm_deltaBody (d : List Int) (sl : Nat × Nat) : List Int :=
  let start := sl.1
  let length := sl.2
  let end_ := start + length
  let d1 := d.set start ((match d[start]? with | some v => v | none => 0) + 1)
  if end_ < d.length then
    d1.set end_ ((match d1[end_]? with | some v => v | none => 0) - 1)
  else d1

private theorem bcm_deltaBody_length (d : List Int) (sl : Nat × Nat) :
    (bcm_deltaBody d sl).length = d.length := by
  simp only [bcm_deltaBody]; split <;> simp [List.length_set]

private theorem bcm_cumSum_deltaBody (d : List Int) (s l p : Nat) :
    bcm_cumSum (bcm_deltaBody d (s, l)) p =
    bcm_cumSum d p + (if s ≤ p ∧ s < d.length then 1 else 0) +
    (if s + l ≤ p ∧ s + l < d.length then -1 else 0) := by
  simp only [bcm_deltaBody, bcm_match_eq_getD]
  split
  · rename_i h_end
    rw [bcm_cumSum_set, bcm_cumSum_set]
    simp only [List.length_set]
    by_cases hs : s ≤ p ∧ s < d.length
    · by_cases hsl : s + l ≤ p ∧ s + l < d.length
      · simp [hs, hsl]; omega
      · simp [hs, hsl]; omega
    · by_cases hsl : s + l ≤ p ∧ s + l < d.length
      · simp [hs, hsl]; omega
      · simp [hs, hsl]
  · rename_i h_end
    push_neg at h_end; rw [bcm_cumSum_set]
    by_cases hs : s ≤ p ∧ s < d.length
    · simp [hs]
      have : ¬(s + l ≤ p ∧ s + l < d.length) := by omega
      simp [this]; omega
    · simp [hs]
      have : ¬(s + l ≤ p ∧ s + l < d.length) := by
        intro ⟨h1, h2⟩; exact hs ⟨by omega, by omega⟩
      simp [this]

private def bcm_countCovering : List (Nat × Nat) → Nat → Int
  | [], _ => 0
  | (s, l) :: rest, p => (if s ≤ p ∧ p < s + l then 1 else 0) + bcm_countCovering rest p

private theorem bcm_cumSum_fold_eq (tokens : List (Nat × Nat)) (pageSize p : Nat) (hp : p < pageSize) :
    bcm_cumSum (tokens.foldl bcm_deltaBody (List.replicate (pageSize + 1) (0 : Int))) p =
    bcm_countCovering tokens p := by
  suffices h : ∀ (d : List Int), d.length = pageSize + 1 →
      bcm_cumSum (tokens.foldl bcm_deltaBody d) p = bcm_cumSum d p + bcm_countCovering tokens p by
    rw [h _ (by simp), bcm_cumSum_zeros]; simp
  intro d hd_len
  induction tokens generalizing d with
  | nil => simp [bcm_countCovering]
  | cons t rest ih =>
    obtain ⟨s, l⟩ := t
    simp only [List.foldl_cons, bcm_countCovering]
    rw [ih _ (by rw [bcm_deltaBody_length, hd_len])]
    rw [bcm_cumSum_deltaBody, hd_len]
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

private def bcm_prefSumStep (delta : List Int) (ra : Int × List Bool) (i : Nat) : Int × List Bool :=
  let r := ra.1 + (match delta[i]? with | some v => v | none => 0)
  (r, ra.2 ++ [decide (r > 0)])

private theorem bcm_getD_append_left' (l1 l2 : List Bool) (n : Nat) (d : Bool) (h : n < l1.length) :
    (l1 ++ l2).getD n d = l1.getD n d := by
  simp [List.getD, List.getElem?_append_left h]

private theorem bcm_getD_append_right' (l1 l2 : List Bool) (n : Nat) (d : Bool)
    (h : l1.length ≤ n) :
    (l1 ++ l2).getD n d = l2.getD (n - l1.length) d := by
  simp [List.getD, List.getElem?_append_right h]

private theorem bcm_prefSum_fold_inv (delta : List Int) (n : Nat) :
    let result := (List.range n).foldl (bcm_prefSumStep delta) ((0 : Int), ([] : List Bool))
    result.1 = (if n = 0 then 0 else bcm_cumSum delta (n - 1)) ∧
    result.2.length = n ∧
    ∀ j, j < n → result.2.getD j false = decide (bcm_cumSum delta j > 0) := by
  induction n with
  | zero => simp [bcm_prefSumStep]
  | succ k ih =>
    simp only [List.range_succ, List.foldl_append, List.foldl_cons, List.foldl_nil]
    set prev := (List.range k).foldl (bcm_prefSumStep delta) (0, [])
    obtain ⟨h_run, h_len, h_vals⟩ := ih
    simp only [bcm_prefSumStep]
    refine ⟨?_, ?_, ?_⟩
    · simp only [Nat.succ_ne_zero, ite_false, Nat.succ_sub_one, bcm_match_eq_getD]
      cases k with
      | zero => simp [h_run, bcm_cumSum_zero, List.getD]
      | succ m =>
        simp only [Nat.succ_ne_zero, ite_false, Nat.succ_sub_one] at h_run
        rw [h_run, bcm_cumSum_succ]
    · rw [List.length_append, h_len]; simp
    · intro j hj
      by_cases hjk : j < k
      · rw [bcm_getD_append_left' _ _ _ _ (by rw [h_len]; exact hjk)]
        exact h_vals j hjk
      · have hjk_eq : j = k := by omega
        rw [hjk_eq]
        rw [bcm_getD_append_right' _ _ _ _ (by rw [h_len])]
        have hcs : prev.1 + (match delta[k]? with | some v => v | none => 0) = bcm_cumSum delta k := by
          rw [bcm_match_eq_getD]
          cases k with
          | zero => simp [h_run, bcm_cumSum_zero, List.getD]
          | succ m =>
            simp only [Nat.succ_ne_zero, ite_false, Nat.succ_sub_one] at h_run
            rw [h_run, bcm_cumSum_succ]
        simp [h_len, List.getD, hcs]

private theorem bcm_prefSum_fold_getD (delta : List Int) (pageSize p : Nat) (hp : p < pageSize) :
    ((List.range pageSize).foldl (fun (ra : Int × List Bool) i =>
      let r := ra.1 + (match delta[i]? with | some v => v | none => 0)
      (r, ra.2 ++ [decide (r > 0)])
    ) ((0 : Int), ([] : List Bool))).2.getD p false =
    decide (bcm_cumSum delta p > 0) := by
  show ((List.range pageSize).foldl (bcm_prefSumStep delta) ((0 : Int), ([] : List Bool))).2.getD p false =
      decide (bcm_cumSum delta p > 0)
  exact (bcm_prefSum_fold_inv delta pageSize).2.2 p hp

private theorem bcm_countCovering_nonneg (tokens : List (Nat × Nat)) (p : Nat) :
    bcm_countCovering tokens p ≥ 0 := by
  induction tokens with
  | nil => simp [bcm_countCovering]
  | cons t rest ih =>
    obtain ⟨s, l⟩ := t; simp only [bcm_countCovering]; split <;> omega

private theorem bcm_decide_count_eq_any (tokens : List (Nat × Nat)) (p : Nat) :
    decide (bcm_countCovering tokens p > 0) =
    tokens.any (fun (s, l) => decide (p ≥ s ∧ p < s + l)) := by
  induction tokens with
  | nil => simp [bcm_countCovering]
  | cons t rest ih =>
    obtain ⟨s, l⟩ := t
    simp only [bcm_countCovering, List.any_cons]
    by_cases hcov : s ≤ p ∧ p < s + l
    · simp [hcov, show p ≥ s from hcov.1]
      have := bcm_countCovering_nonneg rest p; omega
    · have hncov : ¬(p ≥ s ∧ p < s + l) := by omega
      simp [hcov, hncov, ih]

-- ── Main theorem ──

/-- Characterization of buildCoverageMask at each position:
    position p is covered iff some token (s, l) has s ≤ p < s + l.
    This is the correctness of the delta-array + prefix-sum algorithm. -/
private theorem buildCoverageMask_getD (tokens : List (Nat × Nat)) (pageSize : Nat)
    (p : Nat) (hp : p < pageSize) :
    (buildCoverageMask tokens pageSize).getD p false =
    tokens.any (fun (s, l) => decide (p ≥ s ∧ p < s + l)) := by
  unfold buildCoverageMask
  show ((List.range pageSize).foldl (fun (ra : Int × List Bool) i =>
      let r := ra.1 + (match (tokens.foldl bcm_deltaBody (List.replicate (pageSize + 1) (0 : Int)))[i]?
        with | some v => v | none => 0)
      (r, ra.2 ++ [decide (r > 0)])
    ) ((0 : Int), ([] : List Bool))).2.getD p false =
    tokens.any (fun (s, l) => decide (p ≥ s ∧ p < s + l))
  set delta := tokens.foldl bcm_deltaBody (List.replicate (pageSize + 1) (0 : Int))
  rw [bcm_prefSum_fold_getD delta pageSize p hp]
  rw [bcm_cumSum_fold_eq tokens pageSize p hp]
  exact bcm_decide_count_eq_any tokens p

/-- Coverage equivalence: the vectorized and scalar coverage masks agree
    when tokens are exactly the selected positions with their lengths.
    Uses coverage_vectorized_correct + buildCoverageMask_getD. -/
theorem coverage_equiv (selectedMask : List Bool) (lengths : List Nat) (pageSize : Nat)
    (h_sel : selectedMask.length = pageSize)
    (h_len : lengths.length = pageSize) :
    let tokens := (List.range pageSize).filterMap (fun i =>
      if (match selectedMask[i]? with | some true => true | _ => false) then
        some (i, match lengths[i]? with | some v => v | none => 0)
      else none)
    vectorizedCoverageMask selectedMask lengths pageSize =
    buildCoverageMask tokens pageSize := by
  intro tokens
  apply List.ext_getElem?
  intro i
  by_cases hi : i < pageSize
  · -- Both in range: show they give the same Bool
    have hv_len : i < (vectorizedCoverageMask selectedMask lengths pageSize).length := by
      rw [vectorizedCoverageMask_length]; exact hi
    have hb_len : i < (buildCoverageMask tokens pageSize).length := by
      rw [buildCoverageMask_length]; exact hi
    rw [List.getElem?_eq_getElem hv_len, List.getElem?_eq_getElem hb_len]
    -- Convert the getD-based characterizations to getElem
    have lhs := coverage_vectorized_correct selectedMask lengths pageSize h_sel h_len i hi
    have rhs := buildCoverageMask_getD tokens pageSize i hi
    simp only [List.getD, List.getElem?_eq_getElem hv_len, Option.getD_some] at lhs
    simp only [List.getD, List.getElem?_eq_getElem hb_len, Option.getD_some] at rhs
    -- lhs : vcm[i] = (range pageSize).any (...)
    -- rhs : bcm[i] = tokens.any (...)
    rw [lhs, rhs]
    congr 1
    -- Both sides are "any" predicates — connect via filterMap/any
    simp only [tokens]
    rw [List.any_filterMap]
    congr 1; ext j
    cases h : (match selectedMask[j]? with | some true => true | _ => false) with
    | true => simp [h]
    | false => simp [h]
  · -- Both out of range
    have hv := List.getElem?_eq_none_iff.mpr
      (show (vectorizedCoverageMask selectedMask lengths pageSize).length ≤ i
        by rw [vectorizedCoverageMask_length]; omega)
    have hb := List.getElem?_eq_none_iff.mpr
      (show (buildCoverageMask tokens pageSize).length ≤ i
        by rw [buildCoverageMask_length]; omega)
    rw [hv, hb]

end Emission
