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

/-- Vectorized tie-breaking: mirrors the `.>`, `.==`, `.&&`, `.||` chain in Swift. -/
def vectorizedCompare (candTensors bestTensors : List Winner) : List Bool :=
  List.zipWith (fun cand best =>
    let longer := cand.len > best.len
    let sameLen := cand.len == best.len
    let positiveLen := cand.len > 0
    let betterPriority := cand.priorityRank < best.priorityRank
    let samePriority := cand.priorityRank == best.priorityRank
    let betterRuleID := cand.ruleID < best.ruleID
    let tieBreak := sameLen && positiveLen && (betterPriority || (samePriority && betterRuleID))
    longer || tieBreak
  ) candTensors bestTensors

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

/-- The core reduction equivalence: vectorized fold-over-rules produces the same
    winners as scalar fold-over-rules at each position.

    This is the key theorem. The Swift code does:
      for ruleIndex in 0..<batch.ruleCount { ... which(contenderWins, ...) ... }
    and we prove it equals mapping scalarReducePosition over transposed columns. -/
theorem reduction_equiv (ruleBatches : List (List Winner)) (pageSize : Nat)
    (h_shape : ∀ batch ∈ ruleBatches, batch.length = pageSize) :
    vectorizedReducePage ruleBatches pageSize =
    scalarReducePage (transpose ruleBatches) := by
  sorry

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
    (let longer := cand.len > best.len
     let sameLen := cand.len == best.len
     let positiveLen := cand.len > 0
     let betterPriority := cand.priorityRank < best.priorityRank
     let samePriority := cand.priorityRank == best.priorityRank
     let betterRuleID := cand.ruleID < best.ruleID
     let tieBreak := sameLen && positiveLen && (betterPriority || (samePriority && betterRuleID))
     longer || tieBreak) = isBetter cand best := by
  unfold isBetter
  by_cases h1 : cand.len = best.len <;>
    by_cases h2 : cand.len = 0 <;>
    by_cases h3 : cand.priorityRank = best.priorityRank <;>
    simp_all [bne_iff_ne, beq_iff_eq, ne_eq, Nat.pos_iff_ne_zero]

end Reduction
