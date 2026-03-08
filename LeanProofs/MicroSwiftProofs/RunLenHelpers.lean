import Mathlib.Data.List.Basic
import Mathlib.Data.List.Scan
import MicroSwiftProofs.MLXPrimitives

/-!
# Run Length Helpers

Shared definitions and lemmas for proving candidate generation equivalences.
Used by CandidateGen.lean for classrun_semantic and related proofs.
-/

namespace RunLenHelpers
open MLX

/-! ### Run length from a position -/

/-- Length of the maximal contiguous `true` run starting at position `i`. -/
def runLenFrom (mask : List Bool) (i : Nat) : Nat :=
  if h : i < mask.length then
    if mask[i] then 1 + runLenFrom mask (i + 1) else 0
  else 0
termination_by mask.length - i

theorem runLenFrom_true (mask : List Bool) (i : Nat) (h : i < mask.length)
    (hm : mask[i] = true) :
    runLenFrom mask i = 1 + runLenFrom mask (i + 1) := by
  rw [runLenFrom]; simp [h, hm]

theorem runLenFrom_false (mask : List Bool) (i : Nat) (h : i < mask.length)
    (hm : mask[i] = false) :
    runLenFrom mask i = 0 := by
  rw [runLenFrom]; simp [h, hm]

theorem runLenFrom_ge (mask : List Bool) (i : Nat) (h : i ≥ mask.length) :
    runLenFrom mask i = 0 := by
  rw [runLenFrom]; simp [show ¬(i < mask.length) by omega]

theorem runLenFrom_le (mask : List Bool) (i : Nat) :
    runLenFrom mask i ≤ mask.length - i := by
  unfold runLenFrom
  split
  · rename_i h
    split
    · have ih := runLenFrom_le mask (i + 1); omega
    · omega
  · omega
termination_by mask.length - i

/-! ### Abstract fold step (bridges scalar inline body to runLenFrom) -/

/-- Abstracted fold step matching the scalar class-run extension loop body. -/
def foldStep (inBody : List Bool) (base : Nat) (acc : Bool × Nat) (offset : Nat)
    : Bool × Nat :=
  if !acc.1 then (false, acc.2)
  else if inBody.getD (base + offset) false then (true, acc.2 + 1)
  else (false, acc.2)

theorem foldStep_shift (inBody : List Bool) (base : Nat) (acc : Bool × Nat)
    (offset : Nat) :
    foldStep inBody base acc (offset + 1) = foldStep inBody (base + 1) acc offset := by
  simp only [foldStep, show base + (offset + 1) = base + 1 + offset by omega]

private theorem getD_eq_getElem_getD (l : List Bool) (i : Nat) :
    l.getD i false = l[i]?.getD false := by
  simp [List.getD]

private theorem foldStep_true_true (inBody : List Bool) (base count : Nat)
    (h : inBody.getD base false = true) :
    foldStep inBody base (true, count) 0 = (true, count + 1) := by
  simp only [foldStep, Nat.add_zero, Bool.not_true, Bool.false_eq_true, ite_false,
    getD_eq_getElem_getD] at h ⊢
  simp [h]

private theorem foldStep_true_false (inBody : List Bool) (base count : Nat)
    (h : inBody.getD base false = false) :
    foldStep inBody base (true, count) 0 = (false, count) := by
  simp only [foldStep, Nat.add_zero, Bool.not_true, Bool.false_eq_true, ite_false,
    getD_eq_getElem_getD] at h ⊢
  simp [h]

private theorem foldl_false_skip (inBody : List Bool) (base : Nat) (offsets : List Nat)
    (count : Nat) :
    (offsets.foldl (foldStep inBody base) (false, count)).2 = count := by
  induction offsets generalizing count with
  | nil => simp
  | cons o rest ih =>
    simp only [List.foldl_cons, foldStep, Bool.not_false, ite_true]
    exact ih count

/-! ### Scalar fold = runLenFrom -/

theorem fold_range_eq_runLen (inBody : List Bool) (k base count : Nat)
    (h_eq : base + k = inBody.length) :
    ((List.range k).foldl (foldStep inBody base) (true, count)).2
    = count + runLenFrom inBody base := by
  induction k generalizing base count with
  | zero =>
    simp; rw [runLenFrom]; simp [show ¬(base < inBody.length) by omega]
  | succ m ih =>
    rw [List.range_succ_eq_map, List.foldl_cons]
    cases h_pos : inBody.getD base false with
    | true =>
      rw [foldStep_true_true inBody base count h_pos, List.foldl_map]
      simp only [Nat.succ_eq_add_one, foldStep_shift]
      rw [ih (base + 1) (count + 1) (by omega)]
      have h_lt : base < inBody.length := by omega
      have hm : inBody[base] = true := by
        simp only [List.getD, List.getElem?_eq_getElem h_lt] at h_pos; exact h_pos
      rw [runLenFrom_true inBody base h_lt hm]; omega
    | false =>
      rw [foldStep_true_false inBody base count h_pos, List.foldl_map]
      simp only [Nat.succ_eq_add_one, foldStep_shift]
      rw [foldl_false_skip inBody (base + 1) (List.range m) count]
      by_cases h_lt : base < inBody.length
      · have hm : inBody[base] = false := by
          simp only [List.getD, List.getElem?_eq_getElem h_lt] at h_pos; exact h_pos
        rw [runLenFrom_false inBody base h_lt hm]; omega
      · rw [runLenFrom_ge inBody base (by omega)]; omega

/-! ### Vectorized run length = runLenFrom -/

theorem scanr_getD_eq_foldr_drop (xs : List Nat) (s : Nat) (i : Nat)
    (hi : i ≤ xs.length) :
    (xs.scanr min s).getD i 0 =
    (xs.drop i).foldr min s := by
  induction xs generalizing i with
  | nil => simp at hi; subst hi; simp [List.scanr]
  | cons x rest ih =>
    cases i with
    | zero =>
      simp only [List.drop_zero, List.foldr_cons, List.getD_cons_zero, List.scanr_cons]
    | succ n =>
      simp only [List.drop_succ_cons, List.scanr_cons, List.getD_cons_succ]
      apply ih; simp [List.length_cons] at hi; omega

theorem bp_length (inBody : List Bool) :
    (which (elemNot inBody) (arange inBody.length) (full inBody.length inBody.length)).length
    = inBody.length := by
  simp [which, elemNot, arange, full, List.length_map, List.length_zip]

theorem bp_getElem (inBody : List Bool) (i : Nat) (hi : i < inBody.length) :
    let bp := which (elemNot inBody) (arange inBody.length) (full inBody.length inBody.length)
    bp[i]'(by rw [bp_length]; exact hi) = if inBody[i] then inBody.length else i := by
  simp only [which, elemNot, arange, full]
  simp only [List.getElem_map, List.getElem_zip, List.getElem_zip,
    List.getElem_range, List.getElem_replicate]
  cases inBody[i] <;> simp

theorem foldr_break_eq (inBody : List Bool) (i : Nat) (hi : i ≤ inBody.length) :
    ((which (elemNot inBody) (arange inBody.length) (full inBody.length inBody.length)).drop i).foldr
      min inBody.length
    = i + runLenFrom inBody i := by
  by_cases h_lt : i < inBody.length
  · have h_bp_lt : i < (which (elemNot inBody) (arange inBody.length)
        (full inBody.length inBody.length)).length := by rw [bp_length]; exact h_lt
    rw [List.drop_eq_getElem_cons h_bp_lt, List.foldr_cons, bp_getElem inBody i h_lt]
    rw [foldr_break_eq inBody (i + 1) (by omega)]
    cases h_mask : inBody[i]
    · simp [h_mask]
      rw [show runLenFrom inBody i = 0 from by rw [runLenFrom]; simp [h_lt, h_mask]]
      omega
    · simp [h_mask]
      rw [show runLenFrom inBody i = 1 + runLenFrom inBody (i + 1) from by
        rw [runLenFrom]; simp [h_lt, h_mask]]
      have bound := runLenFrom_le inBody (i + 1)
      omega
  · have h_eq : i = inBody.length := by omega
    subst h_eq
    have h1 := bp_length inBody
    have : (which (elemNot inBody) (arange inBody.length) (full inBody.length inBody.length)).drop
        inBody.length = [] := by simp [List.drop_eq_nil_iff, h1]
    rw [this, List.foldr_nil]
    have : runLenFrom inBody inBody.length = 0 := by rw [runLenFrom]; simp
    omega
termination_by inBody.length - i

theorem vec_runLength_at (inBody : List Bool) (i : Nat)
    (hi : i < inBody.length) :
    let n := inBody.length
    let isBreak := elemNot inBody
    let breakPositions := which isBreak (arange n) (full n n)
    let nextBreakPos := cumminRev breakPositions n
    let runLength := elemSub nextBreakPos (arange n)
    runLength.getD i 0 = runLenFrom inBody i := by
  simp only []
  simp only [elemSub, List.getD, List.getElem?_zipWith, cumminRev]
  set bp := which (elemNot inBody) (arange inBody.length) (full inBody.length inBody.length)
  have h_bp_len : bp.length = inBody.length := bp_length inBody
  have h_scanr_len : (bp.scanr min inBody.length).length = bp.length + 1 := List.length_scanr ..
  have h_i_lt_scanr : i < (bp.scanr min inBody.length).length := by omega
  rw [List.getElem?_eq_getElem h_i_lt_scanr]
  simp only [arange]
  rw [List.getElem?_eq_getElem (by simp; exact hi)]
  simp only [List.getElem_range]
  have h_scanr_val : (bp.scanr min inBody.length)[i] = (bp.drop i).foldr min inBody.length := by
    have := scanr_getD_eq_foldr_drop bp inBody.length i (by omega)
    simp only [List.getD, List.getElem?_eq_getElem h_i_lt_scanr] at this
    simpa using this
  simp only [h_scanr_val]
  rw [foldr_break_eq inBody i (by omega)]
  simp

/-! ### Bridge lemmas (match patterns ↔ getD) -/

theorem match_valid_eq_getD (validMask : List Bool) (i : Nat) :
    (match validMask[i]? with | some true => true | _ => false) =
    validMask.getD i false := by
  simp only [List.getD]
  cases validMask[i]? with
  | none => rfl
  | some v => cases v <;> rfl

theorem match_classID_eq_getD (classIDs : List Nat) (i : Nat) :
    (match classIDs[i]? with | some c => c | none => 0) =
    classIDs.getD i 0 := by
  simp only [List.getD]; cases classIDs[i]? <;> rfl

/-! ### shiftRight characterization -/

theorem shiftRight_getD (xs : List Bool) (i : Nat) (hi : i < xs.length) :
    (shiftRight xs 1 false).getD i false =
    if i = 0 then false else xs.getD (i - 1) false := by
  simp only [shiftRight]
  cases i with
  | zero =>
    simp [List.getD, List.getElem?_append, List.length_replicate]
  | succ n =>
    have hn : n < xs.length := by omega
    simp [List.getD, List.length_replicate,
      List.getElem?_take, show n < xs.length - 1 from by omega,
      List.getElem?_eq_getElem hn]

/-! ### MLX primitive characterization at position i -/

theorem inBody_length (validMask : List Bool) (classIDs : List Nat) (f : Nat → Bool)
    (h_len : classIDs.length = validMask.length) :
    (List.zipWith and validMask (classIDs.map f)).length = classIDs.length := by
  simp [List.length_zipWith, h_len]

theorem inBody_getD (validMask : List Bool) (classIDs : List Nat) (f : Nat → Bool)
    (i : Nat) (h_len : classIDs.length = validMask.length) (hi : i < classIDs.length) :
    (List.zipWith and validMask (classIDs.map f)).getD i false =
    (validMask.getD i false && f (classIDs.getD i 0)) := by
  simp only [List.getD, List.getElem?_zipWith, List.getElem?_map]
  rw [List.getElem?_eq_getElem (by omega : i < validMask.length)]
  rw [List.getElem?_eq_getElem hi]
  simp

-- which at position i
theorem which_getD_nat (mask : List Bool) (tVals fVals : List Nat) (i : Nat)
    (h1 : mask.length = tVals.length) (h2 : tVals.length = fVals.length)
    (hi : i < mask.length) :
    (which mask tVals fVals).getD i 0 =
    if mask.getD i false then tVals.getD i 0 else fVals.getD i 0 := by
  simp only [which, List.getD]
  rw [List.getElem?_map]
  have h_zip_len : (List.zip mask (List.zip tVals fVals)).length = mask.length := by
    simp [h1, h2]
  rw [List.getElem?_eq_getElem (by omega : i < (List.zip mask (List.zip tVals fVals)).length)]
  simp only [Option.map_some']
  rw [List.getElem?_eq_getElem hi]
  rw [show (List.zip mask (List.zip tVals fVals))[i]'(by omega) =
    (mask[i]'hi, (List.zip tVals fVals)[i]'(by simp [h2]; omega)) from List.getElem_zip ..]
  rw [show (List.zip tVals fVals)[i]'(by simp [h2]; omega) =
    (tVals[i]'(by omega), fVals[i]'(by omega)) from List.getElem_zip ..]
  rw [List.getElem?_eq_getElem (by omega : i < tVals.length)]
  rw [List.getElem?_eq_getElem (by omega : i < fVals.length)]
  simp

theorem which_length (mask : List Bool) (tVals fVals : List Nat)
    (h1 : mask.length = tVals.length) (h2 : tVals.length = fVals.length) :
    (which mask tVals fVals).length = mask.length := by
  simp [which, List.length_map, List.length_zip, h1, h2]

-- elemAnd at position i
theorem elemAnd_getD (a b : List Bool) (i : Nat) (h : a.length = b.length)
    (hi : i < a.length) :
    (elemAnd a b).getD i false = (a.getD i false && b.getD i false) := by
  simp only [elemAnd, List.getD, List.getElem?_zipWith]
  rw [List.getElem?_eq_getElem hi]
  rw [List.getElem?_eq_getElem (by omega : i < b.length)]
  simp

theorem elemAnd_length (a b : List Bool) (h : a.length = b.length) :
    (elemAnd a b).length = a.length := by
  simp [elemAnd, List.length_zipWith, h]

-- elemNot at position i
theorem elemNot_getD (a : List Bool) (i : Nat) (hi : i < a.length) :
    (elemNot a).getD i false = !a.getD i false := by
  simp only [elemNot, List.getD, List.getElem?_map]
  rw [List.getElem?_eq_getElem hi]
  simp

theorem elemNot_length (a : List Bool) : (elemNot a).length = a.length := by
  simp [elemNot]

-- map decide at position i
theorem map_decide_ge_getD (xs : List Nat) (m : Nat) (i : Nat) (hi : i < xs.length) :
    (xs.map fun l => decide (l ≥ m)).getD i false = decide (xs.getD i 0 ≥ m) := by
  simp [List.getD, List.getElem?_map, List.getElem?_eq_getElem hi]

-- elemSub length
theorem elemSub_length (a b : List Nat) (h : a.length = b.length) :
    (elemSub a b).length = a.length := by
  simp [elemSub, List.length_zipWith, h]

-- full
theorem full_getD (n : Nat) (v d : Nat) (i : Nat) (hi : i < n) :
    (full n v).getD i d = v := by
  simp [full, List.getD, List.getElem?_replicate, hi]

theorem full_length (n : Nat) (v : Nat) : (full n v).length = n := by
  simp [full]

-- arange
theorem arange_getD (n : Nat) (i : Nat) (hi : i < n) :
    (arange n).getD i 0 = i := by
  simp [arange, List.getD, List.getElem?_range, hi]

theorem arange_length (n : Nat) : (arange n).length = n := by
  simp [arange]

-- shiftRight length
theorem shiftRight_length (xs : List Bool) :
    (shiftRight xs 1 false).length = max 1 xs.length := by
  simp [shiftRight, List.length_append, List.length_replicate, List.length_take]
  omega

-- cumminRev length
theorem cumminRev_length (xs : List Nat) (s : Nat) :
    (cumminRev xs s).length = xs.length + 1 := by
  simp [cumminRev, List.length_scanr]

/-! ### Shifted run length (for head-tail evaluation) -/

/-- When we shift breakPositions left by 1, the foldr over the dropped list
    still reduces to foldr_break_eq but at i+1 instead of i. -/
private theorem shiftLeft_drop_foldr (bp : List Nat) (n : Nat) (i : Nat)
    (h_bp_len : bp.length = n) (hi : i < n) :
    ((shiftLeft bp 1 n).drop i).foldr min n =
    (bp.drop (i + 1)).foldr min n := by
  simp only [shiftLeft]
  -- shiftLeft bp 1 n = bp.drop 1 ++ List.replicate 1 n
  -- (bp.drop 1 ++ [n]).drop i
  have h_drop1_len : (bp.drop 1).length = n - 1 := by simp [h_bp_len]
  -- i < n, so i ≤ n - 1 = (bp.drop 1).length
  have h_i_le : i ≤ (bp.drop 1).length := by omega
  rw [List.drop_append_of_le_length h_i_le]
  -- Now: (bp.drop 1).drop i ++ [n] = bp.drop (1+i) ++ [n]
  rw [List.drop_drop, show 1 + i = i + 1 from Nat.add_comm 1 i]
  -- foldr min n (bp.drop (i+1) ++ [n]) = foldr min n (bp.drop (i+1))
  -- because appending [n] doesn't change foldr min n
  rw [List.foldr_append]
  -- The RHS fold produces min n n = n as initial value
  change (List.drop (i + 1) bp).foldr min (min n n) = _
  rw [Nat.min_self]

/-- Shifted variant of vec_runLength_at for head-tail evaluation.
    With shiftLeft of breakPositions by 1, the run length at position i
    equals 1 + runLenFrom mask (i+1). -/
theorem vec_runLength_at_shifted (mask : List Bool) (i : Nat)
    (hi : i < mask.length) :
    let n := mask.length
    let isBreak := elemNot mask
    let breakPositions := which isBreak (arange n) (full n n)
    let shiftedBreaks := shiftLeft breakPositions 1 n
    let nextBreakPos := cumminRev shiftedBreaks n
    let runLength := elemSub nextBreakPos (arange n)
    runLength.getD i 0 = 1 + runLenFrom mask (i + 1) := by
  simp only []
  set bp := which (elemNot mask) (arange mask.length) (full mask.length mask.length)
  have h_bp_len : bp.length = mask.length := bp_length mask
  -- shiftLeft length
  have h_sl_len : (shiftLeft bp 1 mask.length).length = mask.length := by
    simp only [shiftLeft, List.length_append, List.length_drop, List.length_replicate, h_bp_len]
    omega
  -- elemSub getD
  simp only [elemSub, List.getD, List.getElem?_zipWith, cumminRev]
  -- scanr getD → foldr drop
  have h_scanr_len : (List.scanr min mask.length (shiftLeft bp 1 mask.length)).length =
      (shiftLeft bp 1 mask.length).length + 1 := List.length_scanr ..
  have h_i_lt_scanr : i < (List.scanr min mask.length (shiftLeft bp 1 mask.length)).length := by
    omega
  rw [List.getElem?_eq_getElem h_i_lt_scanr]
  simp only [arange]
  rw [List.getElem?_eq_getElem (by simp; exact hi)]
  simp only [List.getElem_range]
  -- scanr value = foldr of drop
  have h_scanr_val : (List.scanr min mask.length (shiftLeft bp 1 mask.length))[i] =
      ((shiftLeft bp 1 mask.length).drop i).foldr min mask.length := by
    have := scanr_getD_eq_foldr_drop (shiftLeft bp 1 mask.length) mask.length i (by omega)
    simp only [List.getD, List.getElem?_eq_getElem h_i_lt_scanr] at this
    simpa using this
  simp only [h_scanr_val]
  -- Reduce shifted foldr to unshifted foldr at i+1
  rw [shiftLeft_drop_foldr bp mask.length i h_bp_len hi]
  -- Use foldr_break_eq at i+1
  rw [foldr_break_eq mask (i + 1) (by omega)]
  simp only [Option.getD]
  omega

end RunLenHelpers
