import Mathlib.Data.List.Basic
import MicroSwiftProofs.MLXPrimitives
import MicroSwiftProofs.RunLenHelpers
import MicroSwiftProofs.CandidateGen

open MLX RunLenHelpers CandidateGen

-- Bridge: scalar inBody match = canonical getD
set_option linter.unusedSimpArgs false in
private lemma cr_inBody_matches2
    (validMask : List Bool) (classIDs : List Nat)
    (bodySetID : Nat) (membership : ClassSetMembership)
    (h_len : classIDs.length = validMask.length)
    (i : Nat) (hi : i < classIDs.length) :
    ((match validMask[i]? with | some true => true | _ => false) &&
     membership bodySetID (match classIDs[i]? with | some c => c | none => 0)) =
    (List.zipWith and validMask (classIDs.map (membership bodySetID))).getD i false := by
  have := RunLenHelpers.inBody_getD validMask classIDs (membership bodySetID) i h_len hi
  simp only [List.getD, List.getElem?_eq_getElem (show i < validMask.length from by omega),
              List.getElem?_eq_getElem hi, List.getElem?_zipWith, List.getElem?_map] at this ⊢
  cases validMask[i] <;> simp_all

-- Foldl = runLenFrom (variant with x.fst = false and ∧)
set_option linter.unusedSimpArgs false in
private lemma cr_foldl_eq_runLen_v1
    (validMask : List Bool) (classIDs : List Nat)
    (bodySetID : Nat) (membership : ClassSetMembership)
    (h_len : classIDs.length = validMask.length)
    (i : Nat) (hi : i < classIDs.length)
    (inBody : List Bool)
    (h_inBody : inBody = List.zipWith and validMask (classIDs.map (membership bodySetID)))
    (h_inBody_i : inBody.getD i false = true) :
    (List.foldl
      (fun x offset =>
        if x.fst = false then (false, x.snd)
        else
          if (match validMask[i + 1 + offset]? with | some true => true | x => false) = true ∧
             membership bodySetID (match classIDs[i + 1 + offset]? with | some c => c | none => 0) = true
          then (true, x.snd + 1) else (false, x.snd))
      (true, 1) (List.range (classIDs.length - i - 1))).2 =
    RunLenHelpers.runLenFrom inBody i := by
  have h_funs_eq : (fun x offset =>
        if x.fst = false then (false, x.snd)
        else
          if (match validMask[i + 1 + offset]? with | some true => true | x => false) = true ∧
             membership bodySetID (match classIDs[i + 1 + offset]? with | some c => c | none => 0) = true
          then (true, x.snd + 1) else (false, x.snd)) =
      RunLenHelpers.foldStep (List.zipWith and validMask (classIDs.map (membership bodySetID))) (i + 1) := by
    funext ⟨a, b⟩ offset
    simp only [RunLenHelpers.foldStep, Bool.not_eq_true',
      List.getD, List.getElem?_zipWith, List.getElem?_map]
    cases a
    · simp
    · simp only [ite_false, Bool.true_eq_false]
      cases h1 : validMask[i + 1 + offset]? with
      | none => simp
      | some v =>
        cases h2 : classIDs[i + 1 + offset]? with
        | none =>
          exfalso
          have hv : i + 1 + offset < validMask.length := by
            by_contra hc; push_neg at hc
            rw [List.getElem?_eq_none (by omega)] at h1; exact Option.noConfusion h1
          have hc : ¬(i + 1 + offset < classIDs.length) := by
            intro h; rw [List.getElem?_eq_getElem h] at h2; exact Option.noConfusion h2
          omega
        | some c => cases v <;> simp [Bool.and_eq_true]
  rw [h_funs_eq]
  subst h_inBody
  set ib := List.zipWith and validMask (classIDs.map (membership bodySetID))
  have h_ib_len : ib.length = classIDs.length := by
    simp [ib, List.length_zipWith, h_len]
  have h_eq : i + 1 + (classIDs.length - i - 1) = ib.length := by omega
  rw [RunLenHelpers.fold_range_eq_runLen ib (classIDs.length - i - 1) (i + 1) 1 h_eq]
  have h_lt : i < ib.length := by omega
  have h_mask_true : ib[i] = true := by
    have := h_inBody_i
    simp only [List.getD, List.getElem?_eq_getElem h_lt] at this; exact this
  rw [RunLenHelpers.runLenFrom_true ib i h_lt h_mask_true]

-- Foldl = runLenFrom (variant with (!x.fst) = true and && = true)
set_option linter.unusedSimpArgs false in
private lemma cr_foldl_eq_runLen2
    (validMask : List Bool) (classIDs : List Nat)
    (bodySetID : Nat) (membership : ClassSetMembership)
    (h_len : classIDs.length = validMask.length)
    (i : Nat) (hi : i < classIDs.length)
    (inBody : List Bool)
    (h_inBody : inBody = List.zipWith and validMask (classIDs.map (membership bodySetID)))
    (h_inBody_i : inBody.getD i false = true) :
    (List.foldl
      (fun x offset =>
        if (!x.fst) = true then (false, x.snd)
        else
          if ((match validMask[i + 1 + offset]? with | some true => true | x => false) &&
             membership bodySetID (match classIDs[i + 1 + offset]? with | some c => c | none => 0)) = true
          then (true, x.snd + 1) else (false, x.snd))
      (true, 1) (List.range (classIDs.length - i - 1))).2 =
    RunLenHelpers.runLenFrom inBody i := by
  have h_funs_eq : (fun x offset =>
        if (!x.fst) = true then (false, x.snd)
        else
          if ((match validMask[i + 1 + offset]? with | some true => true | x => false) &&
             membership bodySetID (match classIDs[i + 1 + offset]? with | some c => c | none => 0)) = true
          then (true, x.snd + 1) else (false, x.snd)) =
      RunLenHelpers.foldStep (List.zipWith and validMask (classIDs.map (membership bodySetID))) (i + 1) := by
    funext ⟨a, b⟩ offset
    simp only [RunLenHelpers.foldStep, Bool.not_eq_true',
      List.getD, List.getElem?_zipWith, List.getElem?_map]
    cases a
    · simp
    · simp only [ite_false, Bool.true_eq_false, Bool.not_true, Bool.false_eq_true]
      cases h1 : validMask[i + 1 + offset]? with
      | none => simp
      | some v =>
        cases h2 : classIDs[i + 1 + offset]? with
        | none =>
          exfalso
          have hv : i + 1 + offset < validMask.length := by
            by_contra hc; push_neg at hc
            rw [List.getElem?_eq_none (by omega)] at h1; exact Option.noConfusion h1
          have hc : ¬(i + 1 + offset < classIDs.length) := by
            intro h; rw [List.getElem?_eq_getElem h] at h2; exact Option.noConfusion h2
          omega
        | some c => cases v <;> simp [Bool.and_eq_true]
  rw [h_funs_eq]
  subst h_inBody
  set ib := List.zipWith and validMask (classIDs.map (membership bodySetID))
  have h_ib_len : ib.length = classIDs.length := by
    simp [ib, List.length_zipWith, h_len]
  have h_eq : i + 1 + (classIDs.length - i - 1) = ib.length := by omega
  rw [RunLenHelpers.fold_range_eq_runLen ib (classIDs.length - i - 1) (i + 1) 1 h_eq]
  have h_lt : i < ib.length := by omega
  have h_mask_true : ib[i] = true := by
    have := h_inBody_i
    simp only [List.getD, List.getElem?_eq_getElem h_lt] at this; exact this
  rw [RunLenHelpers.runLenFrom_true ib i h_lt h_mask_true]

-- Helper: compute inBody.getD from raw validMask and classIDs values
private lemma inBody_getD_eq
    (validMask : List Bool) (classIDs : List Nat)
    (bodySetID : Nat) (membership : ClassSetMembership)
    (h_len : classIDs.length = validMask.length)
    (j : Nat) (hj : j < classIDs.length)
    (inBody : List Bool)
    (inBody_def : inBody = List.zipWith and validMask (classIDs.map (membership bodySetID))) :
    inBody.getD j false = ((validMask[j]'(by omega)) && membership bodySetID (classIDs[j]'hj)) := by
  rw [inBody_def]
  simp [List.getD, List.getElem?_zipWith,
    List.getElem?_eq_getElem (show j < validMask.length from by omega),
    List.getElem?_map, List.getElem?_eq_getElem hj]

-- Full proof: use the approach from CRTest.lean but fix the elaboration issue
-- by working directly with the canonical form and using cases on i for prevInBody
set_option maxHeartbeats 6400000 in
set_option linter.unusedSimpArgs false in
private theorem classrun_semantic_test
    (classIDs : List Nat) (validMask : List Bool)
    (bodySetID : Nat) (minLength : Nat) (membership : ClassSetMembership)
    (h_len : classIDs.length = validMask.length) :
    vectorizedClassRunEval classIDs validMask bodySetID minLength membership =
    scalarClassRunEval classIDs validMask bodySetID minLength membership := by
  open RunLenHelpers MLX in
  unfold vectorizedClassRunEval scalarClassRunEval
  simp only []
  set inBody := List.zipWith and validMask (classIDs.map (membership bodySetID)) with inBody_def
  have h_ib_len : inBody.length = classIDs.length := by
    rw [inBody_def]; simp [List.length_zipWith, h_len]
  have h_rl_len : (elemSub (cumminRev (which (elemNot inBody) (arange classIDs.length)
      (full classIDs.length classIDs.length)) classIDs.length)
      (arange classIDs.length)).length = classIDs.length := by
    simp only [elemSub, List.length_zipWith, cumminRev, List.length_scanr,
      which, List.length_map, List.length_zip, elemNot, arange, List.length_range,
      full, List.length_replicate, h_ib_len]; omega
  have h_enot_sr_len : (elemNot (shiftRight inBody 1 false)).length = max 1 classIDs.length := by
    rw [elemNot_length, shiftRight_length, h_ib_len]
  have h_isStart_len : (elemAnd inBody (elemNot (shiftRight inBody 1 false))).length
      = classIDs.length := by
    simp only [elemAnd, List.length_zipWith, h_ib_len, h_enot_sr_len]; omega
  have h_mml_len : ((elemSub (cumminRev (which (elemNot inBody) (arange classIDs.length)
      (full classIDs.length classIDs.length)) classIDs.length)
      (arange classIDs.length)).map fun l => decide (l ≥ minLength)).length
      = classIDs.length := by simp [h_rl_len]
  have h_vs_len : (elemAnd (elemAnd inBody (elemNot (shiftRight inBody 1 false)))
      ((elemSub (cumminRev (which (elemNot inBody) (arange classIDs.length)
        (full classIDs.length classIDs.length)) classIDs.length)
        (arange classIDs.length)).map fun l => decide (l ≥ minLength))).length
      = classIDs.length := by
    rw [elemAnd_length _ _ (by rw [h_isStart_len, h_mml_len])]; exact h_isStart_len
  have h_vec_len : (which (elemAnd (elemAnd inBody (elemNot (shiftRight inBody 1 false)))
      ((elemSub (cumminRev (which (elemNot inBody) (arange classIDs.length)
        (full classIDs.length classIDs.length)) classIDs.length)
        (arange classIDs.length)).map fun l => decide (l ≥ minLength)))
      (elemSub (cumminRev (which (elemNot inBody) (arange classIDs.length)
        (full classIDs.length classIDs.length)) classIDs.length) (arange classIDs.length))
      (full classIDs.length 0)).length = classIDs.length := by
    rw [which_length _ _ _ (by rw [h_vs_len, h_rl_len]) (by rw [h_rl_len, full_length])]
    exact h_vs_len
  apply List.ext_getElem
  · simp [h_vec_len]
  · intro i h1 h2
    have hi : i < classIDs.length := by rw [h_vec_len] at h1; exact h1
    rw [List.getElem_map, List.getElem_range]
    have h_getElem_eq_getD : ∀ (l : List Nat) (h' : i < l.length),
        l[i]'h' = l.getD i 0 := fun l h' => by
      simp [List.getD, List.getElem?_eq_getElem h']
    rw [h_getElem_eq_getD _ h1]
    rw [which_getD_nat _ _ _ i (by rw [h_vs_len, h_rl_len])
      (by rw [h_rl_len, full_length]) (by rw [h_vs_len]; omega)]
    rw [full_getD _ 0 0 i hi]
    rw [elemAnd_getD _ _ i (by rw [h_isStart_len, h_mml_len]) (by rw [h_isStart_len]; omega)]
    rw [elemAnd_getD _ _ i (by rw [h_ib_len, h_enot_sr_len]; omega) (by rw [h_ib_len]; omega)]
    rw [elemNot_getD _ i (by rw [shiftRight_length, h_ib_len]; omega)]
    rw [shiftRight_getD inBody i (by rw [h_ib_len]; omega)]
    rw [map_decide_ge_getD _ minLength i (by rw [h_rl_len]; omega)]
    have h_rl_eq : (elemSub (cumminRev (which (elemNot inBody) (arange classIDs.length)
        (full classIDs.length classIDs.length)) classIDs.length)
        (arange classIDs.length)).getD i 0 = runLenFrom inBody i := by
      rw [show classIDs.length = inBody.length from h_ib_len.symm]
      exact vec_runLength_at inBody i (by omega)
    rw [h_rl_eq]
    -- LHS: if (inBody.getD i false && !(if i=0 then false else inBody.getD (i-1) false) &&
    --         decide(runLenFrom inBody i ≥ minLength)) = true
    --      then runLenFrom inBody i else 0
    -- RHS: scalar expression with match validMask[i]?, match classIDs[i]?, match i with..., foldl
    -- Strategy: normalize scalar getElem? to concrete values, then use inBody_getD_eq
    -- to align scalar inBody check with canonical, and case-split
    simp only [List.getElem?_eq_getElem (show i < validMask.length from by omega),
               List.getElem?_eq_getElem hi]
    -- Now scalar side has validMask[i] and classIDs[i] as concrete getElems
    -- Replace inBody.getD with concrete validMask/membership expression
    rw [inBody_getD_eq validMask classIDs bodySetID membership h_len i hi inBody inBody_def]
    cases h_vm : (validMask[i]'(by omega))
    · -- validMask[i] = false: both sides = 0
      simp
    · -- validMask[i] = true
      cases h_mem : membership bodySetID (classIDs[i]'hi)
      · -- membership = false: both sides = 0
        simp [h_mem]
      · -- Both true: inBody[i] = true
        simp only [Bool.true_and, h_mem, Bool.and_true]
        have h_ib_t : inBody.getD i false = true := by
          rw [inBody_getD_eq validMask classIDs bodySetID membership h_len i hi inBody inBody_def]
          simp [h_vm, h_mem]
        -- Use cr_inBody_matches2 and cr_prevInBody to bridge
        have h_ib_eq := cr_inBody_matches2 validMask classIDs bodySetID membership h_len i hi
        rw [show List.zipWith and validMask (classIDs.map (membership bodySetID)) = inBody
          from inBody_def.symm] at h_ib_eq
        -- Case split on canonical prevInBody
        by_cases h_prev : (if i = 0 then false else inBody.getD (i - 1) false) = true
        · -- prevInBody = true: not a start position, both sides = 0
          rw [h_prev]; simp only [Bool.not_true, Bool.false_and, Bool.and_false, ite_false]
          -- RHS: show the scalar prevInBody is also true
          -- cases i to evaluate match i with ...
          cases i with
          | zero => simp at h_prev
          | succ n =>
            simp only [show n + 1 ≠ 0 from by omega, ite_false, show n + 1 - 1 = n from by omega] at h_prev
            rw [inBody_getD_eq validMask classIDs bodySetID membership h_len n (by omega) inBody inBody_def] at h_prev
            simp only [List.getElem?_eq_getElem (show n < validMask.length from by omega),
                        List.getElem?_eq_getElem (show n < classIDs.length from by omega)]
            simp [h_prev]
        · -- prevInBody = false: start position
          have h_prev_f : (if i = 0 then false else inBody.getD (i - 1) false) = false := by
            cases (if i = 0 then false else inBody.getD (i - 1) false) <;> simp_all
          rw [h_prev_f]
          simp only [Bool.not_false, Bool.and_true, ite_true, decide_eq_true_eq]
          -- Now LHS: if runLenFrom ≥ minLength then runLenFrom else 0
          -- RHS: scalar expression with match prevInBody and foldl
          -- Show scalar prevInBody = false and bridge foldl to runLenFrom
          -- Use the cr_elaborated_foldl_eq_runLen2 for the foldl bridge
          have hf := cr_foldl_eq_runLen2 validMask classIDs bodySetID membership h_len i hi
              inBody inBody_def h_ib_t
          -- RHS prevInBody: show match i with ... = false
          cases i with
          | zero =>
            -- foldl bridge
            simp only [hf]
          | succ n =>
            simp only [show n + 1 ≠ 0 from by omega, ite_false, show n + 1 - 1 = n from by omega] at h_prev_f
            rw [inBody_getD_eq validMask classIDs bodySetID membership h_len n (by omega) inBody inBody_def] at h_prev_f
            simp only [List.getElem?_eq_getElem (show n < validMask.length from by omega),
                        List.getElem?_eq_getElem (show n < classIDs.length from by omega)]
            simp only [h_prev_f, Bool.not_false, ite_true]
            -- foldl bridge
            simp only [hf]
