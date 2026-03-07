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

theorem coverage_equiv (tokens : List (Nat × Nat)) (selectedMask : List Bool)
    (lengths : List Nat) (pageSize : Nat)
    (h_aligned : selectedMask.length = pageSize)
    (h_consistent : ∀ (i : Nat), (match selectedMask[i]? with | some true => true | _ => false) →
      tokens.any (fun (s, l) => s == i && l == (match lengths[i]? with | some v => v | none => 0))) :
    vectorizedCoverageMask selectedMask lengths pageSize =
    buildCoverageMask tokens pageSize := by
  sorry

end Emission
