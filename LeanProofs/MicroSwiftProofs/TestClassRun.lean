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

private theorem vec_runLength_at (inBody : List Bool) (i : Nat)
    (hi : i < inBody.length) :
    let n := inBody.length
    let isBreak := elemNot inBody
    let breakPositions := which isBreak (arange n) (full n n)
    let nextBreakPos := cumminRev breakPositions n
    let runLength := elemSub nextBreakPos (arange n)
    runLength.getD i 0 = runLenFrom inBody i := by
  sorry

end TestClassRun
