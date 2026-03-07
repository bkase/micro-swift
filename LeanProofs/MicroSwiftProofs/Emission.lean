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

theorem coverage_equiv (tokens : List (Nat × Nat)) (selectedMask : List Bool)
    (lengths : List Nat) (pageSize : Nat)
    (h_aligned : selectedMask.length = pageSize)
    (h_consistent : ∀ (i : Nat), (match selectedMask[i]? with | some true => true | _ => false) →
      tokens.any (fun (s, l) => s == i && l == (match lengths[i]? with | some v => v | none => 0))) :
    vectorizedCoverageMask selectedMask lengths pageSize =
    buildCoverageMask tokens pageSize := by
  sorry

end Emission
