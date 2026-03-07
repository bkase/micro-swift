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

/-- Model class set membership as a function from (setID, classID) → Bool.
    In Swift this is backed by `ClassSetRuntime` with a flat bitmask array. -/
abbrev ClassSetMembership := Nat → Nat → Bool

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

theorem literal_eval_equiv (bytes : List Nat) (validMask : List Bool) (literalBytes : List Nat)
    (h_len : bytes.length = validMask.length) :
    vectorizedLiteralEval bytes validMask literalBytes =
    scalarLiteralEval bytes validMask literalBytes := by
  sorry

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
      if runLen.2 ≥ minLength then runLen.2 else 0
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
  let meetsMinLen := runLength.map fun l => decide (l ≥ minLength)
  let validStart := elemAnd isStart meetsMinLen
  -- 8. Emit length at valid starts, 0 elsewhere
  which validStart runLength (full n 0)

theorem classrun_eval_equiv (classIDs : List Nat) (validMask : List Bool)
    (bodySetID : Nat) (minLength : Nat) (membership : ClassSetMembership)
    (h_len : classIDs.length = validMask.length) :
    vectorizedClassRunEval classIDs validMask bodySetID minLength membership =
    scalarClassRunEval classIDs validMask bodySetID minLength membership := by
  sorry

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
    Same `cumminRev` trick as classRun, but with distinct head/tail classes. -/
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
  -- 3. Detect tail break boundaries
  let isBreak := elemNot isTail
  let breakPositions := which isBreak positions (full n n)
  -- 4. Propagate breaks backwards
  let nextBreakPos := cumminRev breakPositions n
  -- 5. Calculate length and emit
  let runLength := elemSub nextBreakPos positions
  which isStart runLength (full n 0)

theorem headtail_eval_equiv (classIDs : List Nat) (validMask : List Bool)
    (headSetID tailSetID : Nat) (membership : ClassSetMembership)
    (h_len : classIDs.length = validMask.length) :
    vectorizedHeadTailEval classIDs validMask headSetID tailSetID membership =
    scalarHeadTailEval classIDs validMask headSetID tailSetID membership := by
  sorry

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
    (prefix_ : List Nat) (bodySetID : Nat) (stopSetID : Option Nat)
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
    let bodyLen := List.zipWith (fun e s => if e ≥ s then e - s else 0) bodyEndAtStart bodyStart
    let totalLen := bodyLen.map (· + prefixLen)
    -- 7. Filter: must be a valid prefix start and bodyStart <= n
    let validBodyStart := bodyStart.map fun s => decide (s ≤ n)
    let isValidStart := elemAnd prefixStartMask validBodyStart
    which isValidStart totalLen (full n 0)

theorem prefixed_eval_equiv (bytes : List Nat) (classIDs : List Nat) (validMask : List Bool)
    (prefix_ : List Nat) (bodySetID : Nat) (stopSetID : Option Nat)
    (membership : ClassSetMembership)
    (h_len : bytes.length = classIDs.length)
    (h_len2 : bytes.length = validMask.length) :
    vectorizedPrefixedEval bytes classIDs validMask prefix_ bodySetID stopSetID membership =
    scalarPrefixedEval bytes classIDs validMask prefix_ bodySetID stopSetID membership := by
  sorry

end CandidateGen
