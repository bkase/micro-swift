import Mathlib.Data.List.Basic
import MicroSwiftProofs.MLXPrimitives

/-!
# Winner Reduction (Phase C)

Models `WinnerReduction.swift`. Given candidate lengths from all rules at every
position, pick the winner at each position using tie-breaking:
  1. Longer length wins
  2. Smaller priorityRank wins
  3. Smaller ruleID wins

The scalar version folds over rules per-position.
The vectorized version folds over rules across the whole page using element-wise ops.
-/

namespace Reduction

open MLX

/-! ## Shared Types -/

structure Winner where
  len : Nat
  priorityRank : Nat
  ruleID : Nat
  tokenKindID : Nat
  mode : Nat
  deriving Repr, DecidableEq

/-- Matches `WinnerTuple.empty` in Swift: len=0, priorityRank=max, ruleID=max. -/
def emptyWinner : Winner := ⟨0, 65535, 65535, 0, 0⟩

/-! ## Tie-breaking Logic -/

/-- Matches `isBetterThan` / `isBetterCandidate` in Swift.
    Tie-break: longer > smaller priority > smaller ruleID. -/
def isBetter (cand best : Winner) : Bool :=
  if cand.len != best.len then
    cand.len > best.len
  else if cand.len == 0 then
    false
  else if cand.priorityRank != best.priorityRank then
    cand.priorityRank < best.priorityRank
  else
    cand.ruleID < best.ruleID

/-! ## Scalar Model -/

/-- Scalar: fold over rules at a single position to find the best. -/
def scalarReducePosition (candidatesAtPos : List Winner) : Winner :=
  candidatesAtPos.foldl (fun best cand =>
    if isBetter cand best then cand else best
  ) emptyWinner

/-- Scalar: map the position reducer over every position in the page. -/
def scalarReducePage (pageCandidates : List (List Winner)) : List Winner :=
  pageCandidates.map scalarReducePosition

/-! ## Vectorized Model -/

/-- Per-element vectorized comparison expression. -/
def compareExpr (cand best : Winner) : Bool :=
  let longer := cand.len > best.len
  let sameLen := cand.len == best.len
  let positiveLen := cand.len > 0
  let betterPriority := cand.priorityRank < best.priorityRank
  let samePriority := cand.priorityRank == best.priorityRank
  let betterRuleID := cand.ruleID < best.ruleID
  let tieBreak := sameLen && positiveLen && (betterPriority || (samePriority && betterRuleID))
  longer || tieBreak

/-- Vectorized tie-breaking: mirrors the `.>`, `.==`, `.&&`, `.||` chain in Swift. -/
def vectorizedCompare (candTensors bestTensors : List Winner) : List Bool :=
  List.zipWith compareExpr candTensors bestTensors

/-- Vectorized `which` over Winner structs. -/
def winnerWhich (mask : List Bool) (tVals fVals : List Winner) : List Winner :=
  List.zip mask (List.zip tVals fVals) |>.map fun ⟨m, ⟨t, f⟩⟩ =>
    if m then t else f

/-- Vectorized: fold over rule rows, updating best-so-far for the whole page.
    Directly mirrors `WinnerReduction.reduce` loop in Swift. -/
def vectorizedReducePage (ruleBatches : List (List Winner)) (pageSize : Nat) : List Winner :=
  let initialBest := full pageSize emptyWinner
  ruleBatches.foldl (fun bestTensors candTensors =>
    let mask := vectorizedCompare candTensors bestTensors
    winnerWhich mask candTensors bestTensors
  ) initialBest

/-! ## Equivalence Theorem -/

/-- Transpose: convert from [Rules × Positions] to [Positions × Rules]. -/
def transpose {α : Type} (matrix : List (List α)) : List (List α) :=
  match matrix with
  | [] => []
  | row :: _ =>
    (List.range row.length).map fun col =>
      matrix.filterMap (·[col]?)

/-! ## Pointwise Lemmas -/

/-- Per-position lemma: isBetter is consistent with the vectorized compare mask. -/
theorem isBetter_iff_compare (cand best : Winner) :
    isBetter cand best = true ↔
    (cand.len > best.len ∨
      (cand.len = best.len ∧ cand.len > 0 ∧
        (cand.priorityRank < best.priorityRank ∨
          (cand.priorityRank = best.priorityRank ∧ cand.ruleID < best.ruleID)))) := by
  unfold isBetter
  simp only [bne_iff_ne, beq_iff_eq, Bool.ite_eq_true_distrib, decide_eq_true_eq, ne_eq]
  by_cases h1 : cand.len = best.len <;>
    by_cases h2 : cand.len = 0 <;>
    by_cases h3 : cand.priorityRank = best.priorityRank <;>
    simp_all [Nat.pos_iff_ne_zero] <;>
    omega

/-- Pointwise: the vectorized compare expression equals isBetter. -/
theorem compare_eq_isBetter (cand best : Winner) :
    compareExpr cand best = isBetter cand best := by
  unfold compareExpr isBetter
  by_cases h1 : cand.len = best.len <;>
    by_cases h2 : cand.len = 0 <;>
    by_cases h3 : cand.priorityRank = best.priorityRank <;>
    simp_all [bne_iff_ne, beq_iff_eq, ne_eq, Nat.pos_iff_ne_zero]

/-! ## Reduction Equivalence Helper Lemmas -/

/-- winnerWhich with vectorizedCompare equals zipWith of the isBetter-based selection. -/
theorem winnerWhich_vectorizedCompare_eq (cands bests : List Winner) :
    winnerWhich (vectorizedCompare cands bests) cands bests =
    List.zipWith (fun c b => if isBetter c b then c else b) cands bests := by
  unfold winnerWhich vectorizedCompare
  induction cands generalizing bests with
  | nil => simp [List.zipWith, List.zip, List.map]
  | cons c cs ih =>
    cases bests with
    | nil => simp [List.zipWith, List.zip, List.map]
    | cons b bs =>
      simp only [List.zipWith, List.zip, List.map]
      exact congr_arg₂ List.cons (by rw [compare_eq_isBetter]) (ih bs)

/-- The foldl in vectorizedReducePage uses the same step function as isBetter selection. -/
private theorem vectorizedReducePage_foldl_eq (ruleBatches : List (List Winner)) (pageSize : Nat) :
    vectorizedReducePage ruleBatches pageSize =
    ruleBatches.foldl (fun best cand =>
      List.zipWith (fun c b => if isBetter c b then c else b) cand best)
      (List.replicate pageSize emptyWinner) := by
  simp only [vectorizedReducePage, full, MLX.full]
  congr 1
  funext best cand
  exact winnerWhich_vectorizedCompare_eq cand best

/-- Length is preserved through the foldl of zipWith. -/
private theorem length_foldl_zipWith
    (f : Winner → Winner → Winner)
    (rows : List (List Winner)) (init : List Winner) (n : Nat)
    (h_init : init.length = n)
    (h_rows : ∀ row ∈ rows, row.length = n) :
    (rows.foldl (fun acc row => List.zipWith f row acc) init).length = n := by
  induction rows generalizing init with
  | nil => simpa
  | cons row rows ih =>
    simp only [List.foldl]
    apply ih
    · simp [List.length_zipWith, h_rows row (by simp), h_init, Nat.min_self]
    · exact fun r hr => h_rows r (by simp [hr])

/-- Indexing into the foldl of zipWith distributes to a per-position foldl.
    Key structural lemma: vectorized fold = per-position fold after indexing. -/
private theorem getElem_foldl_zipWith
    (f : Winner → Winner → Winner)
    (rows : List (List Winner)) (init : List Winner) (n : Nat)
    (h_init : init.length = n)
    (h_rows : ∀ row ∈ rows, row.length = n)
    (i : Nat) (hi : i < n) :
    (rows.foldl (fun acc row => List.zipWith f row acc) init)[i]'(by
      rw [length_foldl_zipWith f rows init n h_init h_rows]; exact hi) =
    (rows.filterMap (·[i]?)).foldl (fun best cand => f cand best) (init[i]'(by omega)) := by
  induction rows generalizing init with
  | nil => simp
  | cons row rows ih =>
    simp only [List.foldl]
    have h_row : row.length = n := by apply h_rows; simp
    have h_rows' : ∀ r ∈ rows, r.length = n := by intro r hr; apply h_rows; simp [hr]
    have h_init' : (List.zipWith f row init).length = n := by
      simp [List.length_zipWith, h_row, h_init]
    rw [ih _ h_init' h_rows']
    -- Simplify filterMap on cons: row[i]? = some row[i] since i < n = row.length
    have h_get : row[i]? = some (row[i]'(by omega)) := List.getElem?_eq_getElem (by omega)
    simp only [List.filterMap, h_get, Option.some_bind]
    simp only [List.foldl]
    congr 1
    -- (zipWith f row init)[i] = f row[i] init[i]
    rw [List.getElem_zipWith]

/-- Length of transpose for nonempty uniform matrices. -/
private theorem length_transpose (matrix : List (List Winner)) (n : Nat)
    (h_ne : matrix ≠ []) (h_shape : ∀ row ∈ matrix, row.length = n) :
    (transpose matrix).length = n := by
  obtain ⟨r, rs, rfl⟩ := List.exists_cons_of_ne_nil h_ne
  simp [transpose, h_shape r (by simp), List.length_map, List.length_range]

/-- Indexing into transpose gives the column via filterMap. -/
private theorem getElem_transpose (matrix : List (List Winner)) (n : Nat)
    (h_ne : matrix ≠ []) (h_shape : ∀ row ∈ matrix, row.length = n)
    (i : Nat) (hi : i < n) :
    (transpose matrix)[i]'(by rw [length_transpose matrix n h_ne h_shape]; exact hi) =
    matrix.filterMap (·[i]?) := by
  obtain ⟨r, rs, rfl⟩ := List.exists_cons_of_ne_nil h_ne
  simp only [transpose, List.getElem_map, List.getElem_range]

/-- The core reduction equivalence. Requires nonempty ruleBatches since
    vectorizedReducePage produces `full pageSize emptyWinner` for [] but
    scalarReducePage (transpose []) = []. -/
theorem reduction_equiv (ruleBatches : List (List Winner)) (pageSize : Nat)
    (h_nonempty : ruleBatches ≠ [])
    (h_shape : ∀ batch ∈ ruleBatches, batch.length = pageSize) :
    vectorizedReducePage ruleBatches pageSize =
    scalarReducePage (transpose ruleBatches) := by
  rw [vectorizedReducePage_foldl_eq]
  simp only [scalarReducePage, scalarReducePosition]
  apply List.ext_getElem
  · rw [length_foldl_zipWith _ _ _ _ (by simp) h_shape]
    rw [List.length_map, length_transpose _ _ h_nonempty h_shape]
  · intro i h1 h2
    have hi : i < pageSize := by
      rwa [length_foldl_zipWith _ _ _ _ (by simp) h_shape] at h1
    rw [getElem_foldl_zipWith _ _ _ pageSize (by simp) h_shape i hi]
    rw [List.getElem_map]
    rw [getElem_transpose _ pageSize h_nonempty h_shape i hi]
    congr 1
    simp [List.getElem_replicate]

end Reduction
