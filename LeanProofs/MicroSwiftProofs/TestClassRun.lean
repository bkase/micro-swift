import Mathlib.Data.List.Basic
import Mathlib.Data.List.Scan
import MicroSwiftProofs.CandidateGen

namespace TestClassRun
open CandidateGen MLX

/-! ### scanr min characterization -/

private theorem scanr_getD_eq_foldr_drop (xs : List Nat) (s : Nat) (i : Nat)
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

/-! ### Run length helpers -/

private def runLenFrom (mask : List Bool) (i : Nat) : Nat :=
  if h : i < mask.length then
    if mask[i] then 1 + runLenFrom mask (i + 1) else 0
  else 0
termination_by mask.length - i

private theorem runLenFrom_true (mask : List Bool) (i : Nat) (h : i < mask.length)
    (hm : mask[i] = true) :
    runLenFrom mask i = 1 + runLenFrom mask (i + 1) := by
  rw [runLenFrom]; simp [h, hm]

private theorem runLenFrom_false (mask : List Bool) (i : Nat) (h : i < mask.length)
    (hm : mask[i] = false) :
    runLenFrom mask i = 0 := by
  rw [runLenFrom]; simp [h, hm]

private theorem runLenFrom_ge (mask : List Bool) (i : Nat) (h : i ≥ mask.length) :
    runLenFrom mask i = 0 := by
  rw [runLenFrom]; simp [show ¬(i < mask.length) by omega]

/-! ### Scalar loop = runLenFrom -/

-- Abstracted fold step
private def foldStep (inBody : List Bool) (base : Nat) (acc : Bool × Nat) (offset : Nat)
    : Bool × Nat :=
  if !acc.1 then (false, acc.2)
  else if inBody.getD (base + offset) false then (true, acc.2 + 1)
  else (false, acc.2)

private theorem foldStep_shift (inBody : List Bool) (base : Nat) (acc : Bool × Nat)
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

private theorem fold_range_eq_runLen (inBody : List Bool) (k base count : Nat)
    (h_eq : base + k = inBody.length) :
    ((List.range k).foldl (foldStep inBody base) (true, count)).2
    = count + runLenFrom inBody base := by
  induction k generalizing base count with
  | zero =>
    simp; rw [runLenFrom]; simp [show ¬(base < inBody.length) by omega]
  | succ m ih =>
    -- Split range (m+1) = 0 :: map succ (range m)
    rw [List.range_succ_eq_map, List.foldl_cons]
    -- Branch on inBody at base
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

-- The actual scalar loop theorem
private theorem scalar_loop_eq_runLen (inBody : List Bool) (i n count : Nat)
    (hi : i < n) (h_len : inBody.length = n) :
    ((List.range (n - i - 1)).foldl (foldStep inBody (i + 1)) (true, count)).2
    = count + runLenFrom inBody (i + 1) :=
  fold_range_eq_runLen inBody (n - i - 1) (i + 1) count (by omega)

/-! ### Vectorized runLength = runLenFrom -/

-- Helper: bp length
private theorem bp_length (inBody : List Bool) :
    (which (elemNot inBody) (arange inBody.length) (full inBody.length inBody.length)).length
    = inBody.length := by
  simp [which, elemNot, arange, full, List.length_map, List.length_zip]

-- Helper: bp getElem characterization
private theorem bp_getElem (inBody : List Bool) (i : Nat) (hi : i < inBody.length) :
    let bp := which (elemNot inBody) (arange inBody.length) (full inBody.length inBody.length)
    bp[i]'(by rw [bp_length]; exact hi) = if inBody[i] then inBody.length else i := by
  simp only [which, elemNot, arange, full]
  simp only [List.getElem_map, List.getElem_zip, List.getElem_zip,
    List.getElem_range, List.getElem_replicate]
  cases inBody[i] <;> simp

-- Helper: runLenFrom bound
private theorem runLenFrom_le (mask : List Bool) (i : Nat) :
    runLenFrom mask i ≤ mask.length - i := by
  unfold runLenFrom
  split
  · rename_i h
    split
    · have ih := runLenFrom_le mask (i + 1)
      omega
    · omega
  · omega
termination_by mask.length - i

-- Key: foldr min n of bp[i..] = i + runLenFrom inBody i
private theorem foldr_break_eq (inBody : List Bool) (i : Nat) (hi : i ≤ inBody.length) :
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

private theorem vec_runLength_at (inBody : List Bool) (i : Nat)
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

/-! ### MLX primitive helpers for classrun/remap proofs -/

-- shiftLeft at position i gives bytes[i+offset]
private theorem shiftLeft_getD (bytes : List Nat) (offset i : Nat) :
    (shiftLeft bytes offset (0 : Nat)).getD i 0 =
    bytes.getD (i + offset) 0 := by
  simp only [shiftLeft, List.getD, List.getElem?_append, List.length_drop]
  by_cases h : i < bytes.length - offset
  · simp only [h, ite_true, List.getElem?_drop]
    conv_rhs => rw [show i + offset = offset + i from by omega]
  · simp only [h, ite_false, List.getElem?_replicate]
    have h2 : bytes.length ≤ i + offset := by omega
    simp only [List.getElem?_eq_none h2]
    split <;> simp

-- Bridge: match validMask[i]? pattern = validMask.getD i false
private theorem match_valid_eq_getD (validMask : List Bool) (i : Nat) :
    (match validMask[i]? with | some true => true | _ => false) =
    validMask.getD i false := by
  simp only [List.getD]
  cases validMask[i]? with
  | none => rfl
  | some v => cases v <;> rfl

-- Bridge: match classIDs[i]? pattern = classIDs.getD i 0
private theorem match_classID_eq_getD (classIDs : List Nat) (i : Nat) :
    (match classIDs[i]? with | some c => c | none => 0) =
    classIDs.getD i 0 := by
  simp only [List.getD]; cases classIDs[i]? <;> rfl

-- inBody at position i equals scalar computation
private theorem inBody_getD (classIDs : List Nat) (validMask : List Bool)
    (bodySetID : Nat) (membership : CandidateGen.ClassSetMembership) (i : Nat)
    (h_len : classIDs.length = validMask.length) (hi : i < classIDs.length) :
    (List.zipWith and validMask (classIDs.map (membership bodySetID))).getD i false =
    (validMask.getD i false && membership bodySetID (classIDs.getD i 0)) := by
  simp only [List.getD, List.getElem?_zipWith, List.getElem?_map]
  rw [List.getElem?_eq_getElem (by omega : i < validMask.length)]
  rw [List.getElem?_eq_getElem hi]
  simp

end TestClassRun
