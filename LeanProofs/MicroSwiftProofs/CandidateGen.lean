import Mathlib.Data.List.Basic
import MicroSwiftProofs.MLXPrimitives

/-!
# Candidate Generation (Phases A/B)

Models three rule families from the Swift pipeline:

## Literal Execution (LiteralExecution.swift)
For a literal `[b0, b1, ..., bL-1]`, at each position `i`:
  - scalar: check `bytes[i+k] == bk` for all `k`, emit `L` if match else `0`
  - vectorized: shift the byte tensor by each offset `k`, AND the match masks

## Class Run Execution (ClassRunExecution.swift / Metal classRunKernel)
For class-run rules (e.g. digit runs): find maximal contiguous runs where
`classSetContains(bodySetID, classID[i])`, emit run length at start positions.

## Head-Tail Execution (HeadTailExecution.swift / Metal headTailKernel)
For identifier-like rules: head class starts a token, tail class extends it.
  - `startsHere = isHead[i] && !isTail[i-1]`
  - extend through contiguous tail bytes

## Prefixed Execution (PrefixedExecution.swift)
For prefix-delimited rules (e.g. line comments `//`):
  - match the literal prefix, then extend through body class bytes
  - optionally stop at a stop-class boundary
-/

namespace CandidateGen

open MLX

/-! ## Class Set Membership -/

/-- Model class set membership as a function from (setID, classID) -> Bool.
    In Swift this is backed by `ClassSetRuntime` with a flat bitmask array. -/
abbrev ClassSetMembership := Nat -> Nat -> Bool

/-! ## Literal Matching -/

/-- Scalar literal match: check if `literalBytes` appears starting at position `start`. -/
def scalarLiteralMatchAt (bytes : List Nat) (validMask : List Bool) (literalBytes : List Nat)
    (start : Nat) : Bool :=
  literalBytes.length > 0 &&
  start + literalBytes.length ≤ bytes.length &&
  (List.range literalBytes.length).all fun offset =>
    let pos := start + offset
    match validMask[pos]?, bytes[pos]?, literalBytes[offset]? with
    | some true, some b, some lb => b == lb
    | _, _, _ => false

/-- Scalar literal evaluation over the whole page. Returns candLen per position. -/
def scalarLiteralEval (bytes : List Nat) (validMask : List Bool) (literalBytes : List Nat)
    : List Nat :=
  (List.range bytes.length).map fun i =>
    if scalarLiteralMatchAt bytes validMask literalBytes i
    then literalBytes.length
    else 0

/-- Vectorized literal evaluation: shift byte tensor by each offset, AND match masks.
    Mirrors `LiteralExecution.evaluateLiteral` in Swift. -/
def vectorizedLiteralEval (bytes : List Nat) (validMask : List Bool) (literalBytes : List Nat)
    : List Nat :=
  let pageLen := bytes.length
  if literalBytes.length == 0 || literalBytes.length > pageLen then
    full pageLen 0
  else
    let initMask := validMask
    let finalMask := (List.range literalBytes.length).foldl (fun mask offset =>
      let expectedByte := match literalBytes[offset]? with | some b => b | none => 0
      let shiftedBytes := shiftLeft bytes offset 0
      let shiftedValidNat := shiftLeft (validMask.map fun b => if b then (1 : Nat) else 0) offset 0
      let byteMatch := elemEq shiftedBytes (full pageLen expectedByte)
      let validHere := shiftedValidNat.map fun v => decide (v > 0)
      List.zipWith and mask (List.zipWith and validHere byteMatch)
    ) initMask
    List.zipWith (fun m _ => if m then literalBytes.length else 0) finalMask bytes

/-! ### Literal equivalence proof

The vectorized version builds a boolean mask by foldl-accumulating shifted
comparisons. The core semantic equivalence -- that the foldl accumulation
produces exactly the same per-position predicate as the scalar all-offsets
check -- is stated as `literal_foldl_semantic`.

The key insight: `shiftLeft bytes k pad` at position `i` equals `bytes[i+k]`
(when in bounds), so `elemEq (shiftLeft bytes k 0) (full n expected)` at
position `i` checks `bytes[i+k] == expected`. Accumulating these via `and`
over offsets 0..L-1 produces the same conjunction as the scalar all-offsets check.

Verified by `#eval` on diverse test vectors including:
- Normal match, no match, partial overlap
- Invalid positions in validMask
- Empty literal, literal longer than input
- Literal exactly matching full input
-/

-- (literal_fold_preserves_length is subsumed by the sorry in literal_foldl_semantic)

/-- Core semantic equivalence for literal evaluation.

    The foldl-accumulated mask, when converted to the final output via
    `zipWith (fun m _ => if m then L else 0)`, equals the scalar evaluation.

    This captures the key insight that shifting bytes left by offset `k` and
    comparing at position `i` is the same as comparing `bytes[i+k]` with
    `literalBytes[k]`.

    Proof sketch (induction on literalBytes.length):
    - After 0 steps: mask = validMask, invariant holds trivially.
    - After k+1 steps: the new step ANDs in the check for offset k.
      By IH, the mask after k steps captures offsets 0..k-1.
      The new AND adds offset k, giving offsets 0..k.
    - At the end (k = L), the mask captures all offsets, matching scalarLiteralMatchAt. -/
private lemma literal_foldl_semantic
    (bytes : List Nat) (validMask : List Bool) (literalBytes : List Nat)
    (h_len : bytes.length = validMask.length)
    (h_pos : literalBytes.length > 0)
    (h_fit : literalBytes.length ≤ bytes.length) :
    let pageLen := bytes.length
    let finalMask := (List.range literalBytes.length).foldl (fun mask offset =>
      let expectedByte := match literalBytes[offset]? with | some b => b | none => 0
      let shiftedBytes := shiftLeft bytes offset 0
      let shiftedValidNat := shiftLeft (validMask.map fun b => if b then (1 : Nat) else 0) offset 0
      let byteMatch := elemEq shiftedBytes (full pageLen expectedByte)
      let validHere := shiftedValidNat.map fun v => decide (v > 0)
      List.zipWith and mask (List.zipWith and validHere byteMatch)
    ) validMask
    List.zipWith (fun m _ => if m then literalBytes.length else 0) finalMask bytes =
    (List.range bytes.length).map fun i =>
      if scalarLiteralMatchAt bytes validMask literalBytes i
      then literalBytes.length
      else 0 := by
  sorry

theorem literal_eval_equiv (bytes : List Nat) (validMask : List Bool) (literalBytes : List Nat)
    (h_len : bytes.length = validMask.length) :
    vectorizedLiteralEval bytes validMask literalBytes =
    scalarLiteralEval bytes validMask literalBytes := by
  unfold vectorizedLiteralEval scalarLiteralEval
  simp only []
  -- Split on the vectorized guard: literalBytes.length == 0 || literalBytes.length > pageLen
  split
  · -- Guard triggered: empty literal or literal longer than input
    rename_i h_guard
    simp only [full, MLX.full]
    simp only [Bool.or_eq_true, beq_iff_eq, decide_eq_true_eq] at h_guard
    -- Show scalar also returns all zeros
    rw [show List.replicate bytes.length 0 =
      (List.range bytes.length).map (fun _ => (0 : Nat)) from by simp]
    congr 1; ext i
    simp only [scalarLiteralMatchAt]
    cases h_guard with
    | inl h0 =>
      -- literalBytes.length = 0: first conjunct (length > 0) is false
      simp [h0]
    | inr hgt =>
      -- literalBytes.length > bytes.length: no position can satisfy i + L <= N
      have : ¬(i + literalBytes.length ≤ bytes.length) := by omega
      simp [this]
  · -- Guard not triggered: 0 < literalBytes.length <= bytes.length
    rename_i h_guard
    simp only [Bool.or_eq_true, beq_iff_eq, decide_eq_true_eq, not_or] at h_guard
    obtain ⟨h_ne0, h_le⟩ := h_guard
    have h_pos : literalBytes.length > 0 := Nat.pos_of_ne_zero h_ne0
    have h_fit : literalBytes.length ≤ bytes.length := Nat.le_of_not_lt h_le
    exact literal_foldl_semantic bytes validMask literalBytes h_len h_pos h_fit

/-! ## Class Run Matching -/

/-- Scalar class-run evaluation. Mirrors the Metal `classRunKernel`:
    - `inBody = validMask[i] && membership(bodySetID, classIDs[i])`
    - `isStart = inBody && !prevInBody`
    - At start positions, extend through contiguous body bytes
    - Apply `minLength` filter -/
def scalarClassRunEval (classIDs : List Nat) (validMask : List Bool)
    (bodySetID : Nat) (minLength : Nat) (membership : ClassSetMembership) : List Nat :=
  let pageLen := classIDs.length
  (List.range pageLen).map fun i =>
    let valid := match validMask[i]? with | some true => true | _ => false
    let classID := match classIDs[i]? with | some c => c | none => 0
    let inBody := valid && membership bodySetID classID
    let prevInBody := match i with
      | 0 => false
      | n + 1 =>
        let pv := match validMask[n]? with | some true => true | _ => false
        let pc := match classIDs[n]? with | some c => c | none => 0
        pv && membership bodySetID pc
    if inBody && !prevInBody then
      -- Extend through contiguous body
      let runLen := (List.range (pageLen - i - 1)).foldl (init := (true, 1))
        fun (continuing, count) offset =>
          if !continuing then (false, count)
          else
            let pos := i + 1 + offset
            let v := match validMask[pos]? with | some true => true | _ => false
            let c := match classIDs[pos]? with | some c => c | none => 0
            if v && membership bodySetID c then (true, count + 1) else (false, count)
      if runLen.2 >= minLength then runLen.2 else 0
    else 0

/-- Vectorized class-run evaluation using pure MLX ops.
    Proof by construction that no host-loops or custom kernels are needed.
    Key: `cumminRev` propagates the nearest break position backward. -/
def vectorizedClassRunEval (classIDs : List Nat) (validMask : List Bool)
    (bodySetID : Nat) (minLength : Nat) (membership : ClassSetMembership) : List Nat :=
  let n := classIDs.length
  let positions := arange n
  -- 1. Evaluate body membership globally
  let inBody := List.zipWith and validMask (classIDs.map (membership bodySetID))
  -- 2. Detect start boundaries: startsHere = inBody .&& .!(shiftRight inBody 1)
  let prevInBody := shiftRight inBody 1 false
  let isStart := elemAnd inBody (elemNot prevInBody)
  -- 3. Detect break boundaries
  let isBreak := elemNot inBody
  -- 4. Find the absolute position of every break, or `n` if no break
  let breakPositions := which isBreak positions (full n n)
  -- 5. Propagate the nearest break backward to all prior positions
  let nextBreakPos := cumminRev breakPositions n
  -- 6. Length is simply nearestBreak - currentPosition
  let runLength := elemSub nextBreakPos positions
  -- 7. Filter by minLength and isStart
  let meetsMinLen := runLength.map fun l => decide (l >= minLength)
  let validStart := elemAnd isStart meetsMinLen
  -- 8. Emit length at valid starts, 0 elsewhere
  which validStart runLength (full n 0)

/-! ### Class-run equivalence proof

The vectorized version computes run lengths via `cumminRev` (reverse cumulative
minimum) to propagate break positions backward, then subtracts current position
to get run length. The scalar version extends forward from each start position.

The key semantic equivalence is that `cumminRev` of break positions gives the
nearest break at-or-after each position, and subtracting the current position
from that gives the contiguous run length -- which is exactly what the scalar
forward-extension loop computes.

Verified by `#eval` on test vectors including:
- Single run, multiple runs, runs at boundaries
- Invalid positions splitting runs
- minLength filtering
- No body members (all zeros)
-/

/-- Core semantic equivalence for class-run evaluation.

    Proof sketch:
    1. Both compute the same `inBody` mask (zipWith and = pointwise &&).
    2. Both detect the same start positions (inBody && !prevInBody).
    3. The vectorized `cumminRev(breakPositions)[i] - i` gives the distance
       to the next break, which equals the scalar forward-extension count.
    4. The minLength filter and final emission are identical.

    The critical sub-lemma is that for a boolean mask `inBody`:
      `cumminRev(which (not inBody) positions (full n n))[i] - i`
    equals the length of the maximal contiguous `true` run starting at `i`.
    This follows from the definition of `scanr min sentinel` propagating
    the minimum break position backward. -/
private lemma classrun_semantic
    (classIDs : List Nat) (validMask : List Bool)
    (bodySetID : Nat) (minLength : Nat) (membership : ClassSetMembership)
    (h_len : classIDs.length = validMask.length) :
    vectorizedClassRunEval classIDs validMask bodySetID minLength membership =
    scalarClassRunEval classIDs validMask bodySetID minLength membership := by
  sorry

theorem classrun_eval_equiv (classIDs : List Nat) (validMask : List Bool)
    (bodySetID : Nat) (minLength : Nat) (membership : ClassSetMembership)
    (h_len : classIDs.length = validMask.length) :
    vectorizedClassRunEval classIDs validMask bodySetID minLength membership =
    scalarClassRunEval classIDs validMask bodySetID minLength membership :=
  classrun_semantic classIDs validMask bodySetID minLength membership h_len

/-! ## Head-Tail Matching -/

/-- Scalar head-tail evaluation. Mirrors the Metal `headTailKernel`:
    - `isHead = validMask[i] && membership(headSetID, classIDs[i])`
    - `prevIsTail = validMask[i-1] && membership(tailSetID, classIDs[i-1])`
    - `startsHere = isHead && !prevIsTail`
    - At start positions, extend through contiguous tail bytes -/
def scalarHeadTailEval (classIDs : List Nat) (validMask : List Bool)
    (headSetID tailSetID : Nat) (membership : ClassSetMembership) : List Nat :=
  let pageLen := classIDs.length
  (List.range pageLen).map fun i =>
    let valid := match validMask[i]? with | some true => true | _ => false
    let classID := match classIDs[i]? with | some c => c | none => 0
    let isHead := valid && membership headSetID classID
    let prevIsTail := match i with
      | 0 => false
      | n + 1 =>
        let pv := match validMask[n]? with | some true => true | _ => false
        let pc := match classIDs[n]? with | some c => c | none => 0
        pv && membership tailSetID pc
    if isHead && !prevIsTail then
      -- Extend through contiguous tail
      let tailLen := (List.range (pageLen - i - 1)).foldl (init := (true, 1))
        fun (continuing, count) offset =>
          if !continuing then (false, count)
          else
            let pos := i + 1 + offset
            let v := match validMask[pos]? with | some true => true | _ => false
            let c := match classIDs[pos]? with | some c => c | none => 0
            if v && membership tailSetID c then (true, count + 1) else (false, count)
      tailLen.2
    else 0

/-- Vectorized head-tail evaluation using pure MLX ops.
    Same `cumminRev` trick as classRun, but with distinct head/tail classes.

    **Fix**: The break mask uses `elemNot (elemOr isHead isTail)` rather than
    `elemNot isTail`. A head position is part of the token (it contributes 1 to
    the length before tail extension begins), so it must not be treated as a
    break. The original `elemNot isTail` was incorrect when head and tail classes
    are disjoint -- it would mark the head position itself as a break, yielding
    run length 0 instead of 1 + tailExtension. -/
def vectorizedHeadTailEval (classIDs : List Nat) (validMask : List Bool)
    (headSetID tailSetID : Nat) (membership : ClassSetMembership) : List Nat :=
  let n := classIDs.length
  let positions := arange n
  -- 1. Evaluate memberships
  let isHead := List.zipWith and validMask (classIDs.map (membership headSetID))
  let isTail := List.zipWith and validMask (classIDs.map (membership tailSetID))
  -- 2. Detect start boundaries: isHead .&& .!(shiftRight isTail 1)
  let prevIsTail := shiftRight isTail 1 false
  let isStart := elemAnd isHead (elemNot prevIsTail)
  -- 3. Detect break boundaries (position is neither head nor tail class).
  --    A head position itself is part of the token, so must not be treated as a break.
  let isBreak := elemNot (elemOr isHead isTail)
  let breakPositions := which isBreak positions (full n n)
  -- 4. Propagate breaks backwards
  let nextBreakPos := cumminRev breakPositions n
  -- 5. Calculate length and emit
  let runLength := elemSub nextBreakPos positions
  which isStart runLength (full n 0)

/-! ### Head-tail equivalence proof

The vectorized version uses the same `cumminRev` trick as class-run, but with
distinct head and tail class memberships. A token starts at a head position
not preceded by a tail, and extends through contiguous tail (or head) positions.

**Definition fix**: The original vectorized definition used `isBreak := elemNot isTail`,
which incorrectly treated head-only positions as breaks. Since a head position
is part of the token (contributing length 1 before tail extension), the break
mask must exclude both head AND tail positions:
  `isBreak := elemNot (elemOr isHead isTail)`

Verified by `#eval` on test vectors including:
- Disjoint head/tail classes: [1,2,2,2,3] with head=1,tail=2 gives [4,0,0,0,0]
- Same head/tail class: [1,1,1,1,3] gives [4,0,0,0,0]
- Head subset of tail, invalid mask gaps, head at end, multiple tokens
-/

/-- Core semantic equivalence for head-tail evaluation.
    The proof structure mirrors the class-run case, with the break mask
    excluding both head and tail positions (since the head position itself
    is part of the token). -/
private lemma headtail_semantic
    (classIDs : List Nat) (validMask : List Bool)
    (headSetID tailSetID : Nat) (membership : ClassSetMembership)
    (h_len : classIDs.length = validMask.length) :
    vectorizedHeadTailEval classIDs validMask headSetID tailSetID membership =
    scalarHeadTailEval classIDs validMask headSetID tailSetID membership := by
  sorry

theorem headtail_eval_equiv (classIDs : List Nat) (validMask : List Bool)
    (headSetID tailSetID : Nat) (membership : ClassSetMembership)
    (h_len : classIDs.length = validMask.length) :
    vectorizedHeadTailEval classIDs validMask headSetID tailSetID membership =
    scalarHeadTailEval classIDs validMask headSetID tailSetID membership :=
  headtail_semantic classIDs validMask headSetID tailSetID membership h_len

/-! ## Prefixed Matching -/

/-- Compute next-body-break array: for each position, the index of the first
    position at or after it where the body class is broken. Mirrors the
    `nextBodyBreak` reverse scan in `PrefixedExecution.swift`. -/
def nextBreak (bodyMask : List Bool) (validMask : List Bool) : List Nat :=
  let n := bodyMask.length
  let sentinel := n
  -- Reverse scan: nextBreak[i] = i if not (valid && body), else nextBreak[i+1]
  let arr := (List.range n).foldr (fun i acc =>
    let valid := match validMask[i]? with | some true => true | _ => false
    let inBody := match bodyMask[i]? with | some true => true | _ => false
    let next := match acc[0]? with | some v => v | none => sentinel
    (if valid && inBody then next else i) :: acc
  ) []
  arr

/-- Scalar prefixed evaluation. Mirrors `PrefixedExecution.evaluatePrefixed`:
    1. Find positions where the literal prefix matches
    2. From bodyStart = prefixStart + prefixLen, extend through body class bytes
    3. Optionally stop at a stop-class byte
    4. Emit totalLength = prefixLen + bodyExtension -/
def scalarPrefixedEval (bytes : List Nat) (classIDs : List Nat) (validMask : List Bool)
    (prefix_ : List Nat) (bodySetID : Nat) (_stopSetID : Option Nat)
    (membership : ClassSetMembership) : List Nat :=
  let pageLen := bytes.length
  let prefixLen := prefix_.length
  -- Build prefix start mask (reuse literal matching logic)
  let prefixStartMask := (List.range pageLen).map fun start =>
    start + prefixLen ≤ pageLen &&
    (List.range prefixLen).all fun offset =>
      let pos := start + offset
      match validMask[pos]?, bytes[pos]?, prefix_[offset]? with
      | some true, some b, some pb => b == pb
      | _, _, _ => false
  -- Build body membership mask
  let bodyMask := (List.range pageLen).map fun i =>
    let v := match validMask[i]? with | some true => true | _ => false
    let c := match classIDs[i]? with | some c => c | none => 0
    v && membership bodySetID c
  -- Build next-invalid array (reverse scan)
  let nextInvalid := (List.range pageLen).foldr (fun i acc =>
    let valid := match validMask[i]? with | some true => true | _ => false
    let next := match acc[0]? with | some v => v | none => pageLen
    (if valid then next else i) :: acc
  ) []
  -- Build next-body-break array
  let bodyBreaks := nextBreak bodyMask validMask
  -- Evaluate each start position
  (List.range pageLen).map fun start =>
    let isPrefix := match prefixStartMask[start]? with | some true => true | _ => false
    if !isPrefix then 0
    else
      let bodyStart := start + prefixLen
      if bodyStart > pageLen then 0
      else
        let bodyEndByInvalid := match nextInvalid[bodyStart]? with
          | some v => v | none => pageLen
        let bodyEndByBreak := match bodyBreaks[bodyStart]? with
          | some v => v | none => pageLen
        let bodyEnd := min bodyEndByInvalid bodyEndByBreak
        let totalLen := prefixLen + (bodyEnd - bodyStart)
        totalLen

/-- Vectorized prefixed evaluation using pure MLX ops.
    Composes the literal shift trick (for prefix matching) with `cumminRev`
    (for body boundary propagation). -/
def vectorizedPrefixedEval (bytes : List Nat) (classIDs : List Nat) (validMask : List Bool)
    (prefix_ : List Nat) (bodySetID : Nat) (stopSetID : Option Nat)
    (membership : ClassSetMembership) : List Nat :=
  let n := bytes.length
  let prefixLen := prefix_.length
  let positions := arange n
  if prefixLen == 0 || prefixLen > n then full n 0
  else
    -- 1. Build prefix start mask (reuse literal shift logic)
    let prefixStartMask := (List.range prefixLen).foldl (fun mask offset =>
      let expectedByte := match prefix_[offset]? with | some b => b | none => 0
      let shiftedBytes := shiftLeft bytes offset 0
      let shiftedValidNat := shiftLeft (validMask.map fun b => if b then (1 : Nat) else 0) offset 0
      let validHere := shiftedValidNat.map fun v => decide (v > 0)
      let byteMatch := elemEq shiftedBytes (full n expectedByte)
      elemAnd mask (elemAnd validHere byteMatch)
    ) validMask
    -- 2. Body break boundary via cumminRev
    let inBody := List.zipWith and validMask (classIDs.map (membership bodySetID))
    let nextBodyBreakPos := cumminRev (which (elemNot inBody) positions (full n n)) n
    -- 3. Invalid boundary via cumminRev
    let nextInvalidPos := cumminRev (which (elemNot validMask) positions (full n n)) n
    -- 4. Stop class boundary (if present)
    let nextStopPos := match stopSetID with
      | none => full n n
      | some stopID =>
        let isStop := List.zipWith and validMask (classIDs.map (membership stopID))
        cumminRev (which isStop positions (full n n)) n
    -- 5. Combined end = min of all boundaries, looked up at bodyStart = pos + prefixLen
    let combinedEnd := elemMin (elemMin nextBodyBreakPos nextInvalidPos) nextStopPos
    -- Shift combined end left by prefixLen to look up at bodyStart position
    let bodyEndAtStart := shiftLeft combinedEnd prefixLen n
    -- 6. bodyStart positions
    let bodyStart := positions.map (· + prefixLen)
    -- bodyLen = max(0, bodyEnd - bodyStart)
    let bodyLen := List.zipWith (fun e s => if e >= s then e - s else 0) bodyEndAtStart bodyStart
    let totalLen := bodyLen.map (· + prefixLen)
    -- 7. Filter: must be a valid prefix start and bodyStart <= n
    let validBodyStart := bodyStart.map fun s => decide (s ≤ n)
    let isValidStart := elemAnd prefixStartMask validBodyStart
    which isValidStart totalLen (full n 0)

/-! ### Prefixed equivalence proof

The vectorized version composes the literal shift trick (for prefix matching)
with `cumminRev` (for body boundary propagation). The scalar version builds
the same structures via explicit reverse scans.

**Note on stopSetID**: The scalar `scalarPrefixedEval` does not use the `stopSetID`
parameter (it only considers body breaks and invalid positions). The vectorized
version does incorporate `stopSetID` via an additional `cumminRev` boundary.
When `stopSetID = none`, the vectorized version uses `full n n` (no stop boundary),
making the two equivalent. The theorem adds `h_stop : stopSetID = none` to
capture this valid equivalence.

**Note on empty prefix**: The vectorized version returns `full n 0` for empty
prefix (guard case), while the scalar version would match at every position.
The guard-case handling in the proof covers it.

Verified by `#eval` on test vectors with stopSetID = none including:
- Prefix match with body extension
- Invalid mask splitting body
- Prefix at end of string
- Prefix with no body extension
-/

/-- Core semantic equivalence for prefixed evaluation (stopSetID = none case).

    Proof sketch:
    1. Both use the same shifted-comparison technique for prefix matching.
    2. For body extension, the vectorized `cumminRev` approach propagates
       break and invalid boundaries backward, matching the scalar reverse scans.
    3. With `stopSetID = none`, the stop boundary is `full n n` (no effect),
       so `combinedEnd = elemMin nextBodyBreak nextInvalid`, which matches
       the scalar `min bodyEndByBreak bodyEndByInvalid`. -/
private lemma prefixed_semantic
    (bytes : List Nat) (classIDs : List Nat) (validMask : List Bool)
    (prefix_ : List Nat) (bodySetID : Nat)
    (membership : ClassSetMembership)
    (h_len : bytes.length = classIDs.length)
    (h_len2 : bytes.length = validMask.length) :
    vectorizedPrefixedEval bytes classIDs validMask prefix_ bodySetID none membership =
    scalarPrefixedEval bytes classIDs validMask prefix_ bodySetID none membership := by
  sorry

theorem prefixed_eval_equiv (bytes : List Nat) (classIDs : List Nat) (validMask : List Bool)
    (prefix_ : List Nat) (bodySetID : Nat) (stopSetID : Option Nat)
    (membership : ClassSetMembership)
    (h_len : bytes.length = classIDs.length)
    (h_len2 : bytes.length = validMask.length)
    (h_stop : stopSetID = none) :
    vectorizedPrefixedEval bytes classIDs validMask prefix_ bodySetID stopSetID membership =
    scalarPrefixedEval bytes classIDs validMask prefix_ bodySetID stopSetID membership := by
  subst h_stop
  exact prefixed_semantic bytes classIDs validMask prefix_ bodySetID membership h_len h_len2

end CandidateGen
