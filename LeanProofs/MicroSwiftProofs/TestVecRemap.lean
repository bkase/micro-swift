-- Test file for vectorizedRemap_at_pos helper lemmas
import Mathlib.Data.List.Basic
import MicroSwiftProofs.MLXPrimitives
import MicroSwiftProofs.KeywordRemap

namespace TestVecRemap

open MLX

-- Helper: shiftLeft getElem? when i + offset < length
private theorem shiftLeft_getElem?_lt (xs : List Nat) (offset : Nat) (padVal : Nat)
    (i : Nat) (h_sum : i + offset < xs.length) :
    (MLX.shiftLeft xs offset padVal)[i]? = xs[i + offset]? := by
  simp only [MLX.shiftLeft]
  rw [List.getElem?_append_left (by simp; omega)]
  rw [List.getElem?_drop]

-- Helper: full getElem?
private theorem full_getElem?_lt (n : Nat) (val : Nat) (i : Nat) (hi : i < n) :
    (MLX.full n val)[i]? = some val := by
  simp [MLX.full, List.getElem?_replicate]

-- Helper: the matchMask step preserves length
private theorem matchStep_len (bytes : List Nat) (validMask : List Bool)
    (entry : KeywordRemap.RemapEntry) (n : Nat)
    (mask : List Bool) (offset : Nat)
    (h_mask : mask.length = n) (h_bytes : bytes.length = n) (h_valid : validMask.length = n) :
    (List.zipWith and mask (List.zipWith and
      ((MLX.shiftLeft (validMask.map fun b => if b then (1 : Nat) else 0) offset 0).map
        fun v => decide (v > 0))
      (elemEq (MLX.shiftLeft bytes offset 0)
        (MLX.full n (match entry.lexeme[offset]? with | some b => b | none => 0))))).length = n := by
  simp [List.length_zipWith, elemEq, MLX.full, MLX.shiftLeft, h_mask, h_bytes, h_valid]
  omega

-- foldl of matchStep preserves length
private theorem matchFoldl_len (bytes : List Nat) (validMask : List Bool)
    (entry : KeywordRemap.RemapEntry) (n : Nat)
    (offsets : List Nat) (mask : List Bool)
    (h_mask : mask.length = n) (h_bytes : bytes.length = n) (h_valid : validMask.length = n) :
    (offsets.foldl (fun mask offset =>
      let expectedByte := match entry.lexeme[offset]? with | some b => b | none => 0
      let shiftedBytes := MLX.shiftLeft bytes offset 0
      let shiftedValidNat := MLX.shiftLeft (validMask.map fun b => if b then (1 : Nat) else 0) offset 0
      let validHere := shiftedValidNat.map fun v => decide (v > 0)
      let byteMatch := elemEq shiftedBytes (MLX.full n expectedByte)
      List.zipWith and mask (List.zipWith and validHere byteMatch)) mask).length = n := by
  induction offsets generalizing mask with
  | nil => simpa
  | cons o rest ih =>
    simp only [List.foldl_cons]
    exact ih _ (matchStep_len bytes validMask entry n mask o h_mask h_bytes h_valid)

-- When init[i]? = some false, foldl stays false
private theorem matchFoldl_false (bytes : List Nat) (validMask : List Bool)
    (entry : KeywordRemap.RemapEntry) (n : Nat)
    (offsets : List Nat) (mask : List Bool) (i : Nat)
    (h_mask : mask.length = n) (h_bytes : bytes.length = n) (h_valid : validMask.length = n)
    (h_false : mask[i]? = some false) :
    (offsets.foldl (fun mask offset =>
      let expectedByte := match entry.lexeme[offset]? with | some b => b | none => 0
      let shiftedBytes := MLX.shiftLeft bytes offset 0
      let shiftedValidNat := MLX.shiftLeft (validMask.map fun b => if b then (1 : Nat) else 0) offset 0
      let validHere := shiftedValidNat.map fun v => decide (v > 0)
      let byteMatch := elemEq shiftedBytes (MLX.full n expectedByte)
      List.zipWith and mask (List.zipWith and validHere byteMatch)) mask)[i]? = some false := by
  induction offsets generalizing mask with
  | nil => simpa
  | cons o rest ih =>
    simp only [List.foldl_cons]
    apply ih _ (matchStep_len bytes validMask entry n mask o h_mask h_bytes h_valid)
    -- step[i]? = zipWith and at i = mask[i] && inner[i]
    -- mask[i]? = some false, so result is false regardless of inner
    simp only [List.getElem?_zipWith, h_false]
    simp

-- When init[i]? = some true and all conditions hold, foldl gives all byte matches
private theorem matchFoldl_true (bytes : List Nat) (validMask : List Bool)
    (entry : KeywordRemap.RemapEntry) (n : Nat)
    (offsets : List Nat) (mask : List Bool) (i : Nat)
    (h_mask : mask.length = n) (h_bytes : bytes.length = n) (h_valid : validMask.length = n)
    (h_true : mask[i]? = some true)
    (h_bound : ∀ o ∈ offsets, i + o < n)
    (h_valid_at : ∀ o ∈ offsets, validMask[i + o]? = some true) :
    (offsets.foldl (fun mask offset =>
      let expectedByte := match entry.lexeme[offset]? with | some b => b | none => 0
      let shiftedBytes := MLX.shiftLeft bytes offset 0
      let shiftedValidNat := MLX.shiftLeft (validMask.map fun b => if b then (1 : Nat) else 0) offset 0
      let validHere := shiftedValidNat.map fun v => decide (v > 0)
      let byteMatch := elemEq shiftedBytes (MLX.full n expectedByte)
      List.zipWith and mask (List.zipWith and validHere byteMatch)) mask)[i]? =
    some (offsets.all fun offset =>
      match bytes[i + offset]?, entry.lexeme[offset]? with
      | some b, some lb => b == lb
      | _, _ => false) := by
  induction offsets generalizing mask with
  | nil => simpa
  | cons o rest ih =>
    simp only [List.foldl_cons, List.all_cons]
    have h_o_bound := h_bound o (List.mem_cons_self o rest)
    have h_o_valid := h_valid_at o (List.mem_cons_self o rest)
    have h_step_len := matchStep_len bytes validMask entry n mask o h_mask h_bytes h_valid
    -- Compute step[i]? by unfolding zipWith
    -- step = zipWith and mask (zipWith and validHere byteMatch)
    -- step[i]? = match mask[i]?, (zipWith and validHere byteMatch)[i]? with
    --            | some a, some b => some (a && b) | ...
    -- mask[i]? = some true
    -- validHere[i]? = some true (from validity)
    -- byteMatch[i]? = some (decide(bytes[i+o] = expected))
    -- So step[i]? = some (true && (true && decide(...))) = some decide(...)
    -- which equals the byte match function

    -- First compute what step[i]? equals
    have h_step_val : (List.zipWith and mask (List.zipWith and
        ((MLX.shiftLeft (validMask.map fun b => if b then (1 : Nat) else 0) o 0).map
          fun v => decide (v > 0))
        (elemEq (MLX.shiftLeft bytes o 0)
          (MLX.full n (match entry.lexeme[o]? with | some b => b | none => 0)))))[i]? =
      some (match bytes[i + o]?, entry.lexeme[o]? with
        | some b, some lb => b == lb
        | _, _ => false) := by
      -- outer zipWith and
      simp only [List.getElem?_zipWith, h_true]
      -- Now need: (zipWith and validHere byteMatch)[i]? = some (byte_compare)
      -- inner zipWith and
      simp only [List.getElem?_zipWith]
      -- validHere[i]?
      have h_vh : ((MLX.shiftLeft (validMask.map fun b => if b then (1 : Nat) else 0) o 0).map
          fun v => decide (v > 0))[i]? = some true := by
        rw [List.getElem?_map]
        rw [shiftLeft_getElem?_lt _ o 0 i (by simp [h_valid]; omega)]
        rw [List.getElem?_map, h_o_valid]
        simp
      rw [h_vh]
      -- byteMatch[i]?
      simp only [elemEq, List.getElem?_zipWith]
      rw [shiftLeft_getElem?_lt bytes o 0 i (by omega)]
      rw [full_getElem?_lt n _ i (by omega)]
      cases h_bio : bytes[i + o]? with
      | none => simp; cases entry.lexeme[o]? <;> simp
      | some bv =>
        cases h_lex : entry.lexeme[o]? with
        | none => simp
        | some lv => simp [beq_iff_eq]

    -- Case split on byte match result
    set bm := (match bytes[i + o]?, entry.lexeme[o]? with
        | some b, some lb => (b == lb)
        | _, _ => false : Bool) with hbm_def
    cases hbm : bm
    · -- byte doesn't match: step[i]? = some false
      simp only [hbm, false_and, Bool.false_and]
      have h_step_false : (List.zipWith and mask (List.zipWith and
          ((MLX.shiftLeft (validMask.map fun b => if b then (1 : Nat) else 0) o 0).map
            fun v => decide (v > 0))
          (elemEq (MLX.shiftLeft bytes o 0)
            (MLX.full n (match entry.lexeme[o]? with | some b => b | none => 0)))))[i]? = some false := by
        rw [h_step_val, ← hbm_def, hbm]
      exact matchFoldl_false bytes validMask entry n rest _ i h_step_len h_bytes h_valid h_step_false
    · -- byte matches: step[i]? = some true
      simp only [hbm, true_and, Bool.true_and]
      have h_step_true : (List.zipWith and mask (List.zipWith and
          ((MLX.shiftLeft (validMask.map fun b => if b then (1 : Nat) else 0) o 0).map
            fun v => decide (v > 0))
          (elemEq (MLX.shiftLeft bytes o 0)
            (MLX.full n (match entry.lexeme[o]? with | some b => b | none => 0)))))[i]? = some true := by
        rw [h_step_val, ← hbm_def, hbm]
      exact ih _ h_step_len h_step_true
        (fun o' ho' => h_bound o' (List.mem_cons_of_mem o ho'))
        (fun o' ho' => h_valid_at o' (List.mem_cons_of_mem o ho'))

end TestVecRemap
