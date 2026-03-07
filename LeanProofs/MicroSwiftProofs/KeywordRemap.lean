import Mathlib.Data.List.Basic
import MicroSwiftProofs.MLXPrimitives
import MicroSwiftProofs.Selection

/-!
# Keyword Remapping (Phase E)

Models `KeywordRemap.swift` and the tensor path in `TransportEmitter.applyKeywordRemap`.

After greedy selection, certain identifier tokens are checked against keyword tables.
If the token's bytes exactly match a keyword entry, its `tokenKindID` is remapped.

Example: an identifier token covering bytes `[105, 102]` ("if") gets remapped from
`tokenKindID=identifierKind` to `tokenKindID=ifKeywordKind`.

The scalar version iterates over selected tokens and compares byte slices.
The vectorized version uses shifted byte tensors and element-wise masks.
-/

namespace KeywordRemap

open MLX

/-! ## Remap Table -/

/-- A single keyword entry: the lexeme bytes and the target tokenKindID. -/
structure RemapEntry where
  lexeme : List Nat
  tokenKindID : Nat
  deriving Repr, DecidableEq

/-- A remap table: applies to tokens matched by `baseRuleID`. -/
structure RemapTable where
  baseRuleID : Nat
  maxKeywordLength : Nat
  entries : List RemapEntry
  deriving Repr

/-! ## Scalar Remap -/

/-- Check if a byte slice matches a lexeme. -/
def sliceMatches (bytes : List Nat) (start length : Nat) (lexeme : List Nat) : Bool :=
  length == lexeme.length &&
  (List.range length).all fun offset =>
    match bytes[start + offset]?, lexeme[offset]? with
    | some b, some lb => b == lb
    | _, _ => false

/-- Scalar keyword remap: for each selected token, check remap tables and mutate tokenKindID.
    Mirrors `KeywordRemap.apply` in Swift. -/
def scalarRemap (tokens : List Selection.SelectedToken) (bytes : List Nat)
    (tables : List RemapTable) : List Selection.SelectedToken :=
  tokens.map fun token =>
    let remapped := tables.foldl (fun tok table =>
      if tok.ruleID != table.baseRuleID then tok
      else if tok.length > table.maxKeywordLength then tok
      else
        match table.entries.find? (fun entry => sliceMatches bytes tok.startPos tok.length entry.lexeme) with
        | some entry => { tok with tokenKindID := entry.tokenKindID }
        | none => tok
    ) token
    remapped

/-! ## Vectorized Remap -/

/-- Vectorized keyword remap over page-aligned tensors.
    Mirrors `TransportEmitter.applyKeywordRemap` in Swift.

    For each remap table and each keyword entry:
    1. Build a mask of positions where `selectedMask && ruleID == baseRuleID && length == lexemeLen`
    2. For each byte offset, shift the byte tensor and check equality
    3. Where the full match mask is true, update tokenKindID via `which`

    Returns remapped tokenKindID array (page-aligned). -/
def vectorizedRemap (tokenKindIDs : List Nat) (ruleIDs : List Nat) (lengths : List Nat)
    (selectedMask : List Bool) (bytes : List Nat) (validMask : List Bool)
    (tables : List RemapTable) : List Nat :=
  let pageLen := bytes.length
  tables.foldl (fun kinds table =>
    let baseRuleMask := List.zipWith and selectedMask
      (elemEq ruleIDs (full pageLen table.baseRuleID))
    table.entries.foldl (fun kinds' entry =>
      let keyLen := entry.lexeme.length
      if keyLen == 0 then kinds'
      else
        let lenMatch := List.zipWith and baseRuleMask
          (elemEq lengths (full pageLen keyLen))
        -- Fold over each byte offset to build full match mask
        let matchMask := (List.range keyLen).foldl (fun mask offset =>
          let expectedByte := match entry.lexeme[offset]? with | some b => b | none => 0
          let shiftedBytes := shiftLeft bytes offset 0
          let shiftedValidNat := shiftLeft (validMask.map fun b => if b then (1 : Nat) else 0) offset 0
          let validHere := shiftedValidNat.map fun v => decide (v > 0)
          let byteMatch := elemEq shiftedBytes (full pageLen expectedByte)
          List.zipWith and mask (List.zipWith and validHere byteMatch)
        ) lenMatch
        -- Apply remap where match: which(matchMask, entry.tokenKindID, kinds')
        List.zipWith (fun m k => if m then entry.tokenKindID else k) matchMask kinds'
    ) kinds
  ) tokenKindIDs

/-- One remap table step preserves startPos and length. -/
private theorem remap_step_preserves (bytes : List Nat) (table : RemapTable)
    (tok : Selection.SelectedToken) :
    (if tok.ruleID != table.baseRuleID then tok
     else if tok.length > table.maxKeywordLength then tok
     else match table.entries.find? (fun entry =>
         sliceMatches bytes tok.startPos tok.length entry.lexeme) with
       | some entry => { tok with tokenKindID := entry.tokenKindID }
       | none => tok).startPos = tok.startPos ∧
    (if tok.ruleID != table.baseRuleID then tok
     else if tok.length > table.maxKeywordLength then tok
     else match table.entries.find? (fun entry =>
         sliceMatches bytes tok.startPos tok.length entry.lexeme) with
       | some entry => { tok with tokenKindID := entry.tokenKindID }
       | none => tok).length = tok.length := by
  by_cases h1 : tok.ruleID != table.baseRuleID
  · simp [h1]
  · simp only [h1, ite_false]
    by_cases h2 : tok.length > table.maxKeywordLength
    · simp [h2]
    · simp only [h2, ite_false]
      cases table.entries.find? (fun entry =>
          sliceMatches bytes tok.startPos tok.length entry.lexeme) with
      | none => exact ⟨rfl, rfl⟩
      | some _ => exact ⟨rfl, rfl⟩

/-- Folding remap tables preserves startPos and length. -/
private theorem remap_foldl_preserves (bytes : List Nat) (tables : List RemapTable)
    (tok : Selection.SelectedToken) :
    (tables.foldl (fun tok table =>
      if tok.ruleID != table.baseRuleID then tok
      else if tok.length > table.maxKeywordLength then tok
      else match table.entries.find? (fun entry =>
          sliceMatches bytes tok.startPos tok.length entry.lexeme) with
        | some entry => { tok with tokenKindID := entry.tokenKindID }
        | none => tok) tok).startPos = tok.startPos ∧
    (tables.foldl (fun tok table =>
      if tok.ruleID != table.baseRuleID then tok
      else if tok.length > table.maxKeywordLength then tok
      else match table.entries.find? (fun entry =>
          sliceMatches bytes tok.startPos tok.length entry.lexeme) with
        | some entry => { tok with tokenKindID := entry.tokenKindID }
        | none => tok) tok).length = tok.length := by
  induction tables generalizing tok with
  | nil => exact ⟨rfl, rfl⟩
  | cons tbl rest ih =>
    simp only [List.foldl_cons]
    have hstep := remap_step_preserves bytes tbl tok
    set tok' := (if tok.ruleID != tbl.baseRuleID then tok
      else if tok.length > tbl.maxKeywordLength then tok
      else match tbl.entries.find? (fun entry =>
          sliceMatches bytes tok.startPos tok.length entry.lexeme) with
        | some entry => { tok with tokenKindID := entry.tokenKindID }
        | none => tok)
    have hih := ih tok'
    exact ⟨hih.1.trans hstep.1, hih.2.trans hstep.2⟩

/-- scalarRemap only changes tokenKindID, preserving startPos and length. -/
theorem scalarRemap_preserves_pairs (tokens : List Selection.SelectedToken)
    (bytes : List Nat) (tables : List RemapTable) :
    (scalarRemap tokens bytes tables).map (fun t => (t.startPos, t.length)) =
    tokens.map (fun t => (t.startPos, t.length)) := by
  simp only [scalarRemap]
  induction tokens with
  | nil => simp
  | cons tok rest ih =>
    simp only [List.map_cons]
    have h := remap_foldl_preserves bytes tables tok
    simp only [Prod.ext_iff] at h
    rw [List.cons.injEq]; exact ⟨Prod.ext h.1 h.2, ih⟩

/-! ## Equivalence -/

/-- The vectorized remap, when projected back to selected tokens, yields
    the same tokenKindIDs as the scalar remap.

    Given `merged` winners and a `selectedMask` from vectorized selection,
    the vectorized remap (operating on page-wide arrays) agrees with the
    scalar remap (operating on sparse selected tokens) at each selected position.

    Proof strategy: both fold over tables × entries; for each entry, the
    vectorized shiftLeft byte-matching is equivalent to scalar sliceMatches;
    since entries are effectively disjoint (different lexemes can't match
    the same byte window), find? and fold agree. -/
theorem remap_equiv (merged : List Reduction.Winner) (selectedMask : List Bool)
    (bytes : List Nat) (validMask : List Bool) (tables : List RemapTable)
    (h_sel_len : selectedMask.length = merged.length)
    (h_merged_len : merged.length = bytes.length)
    (h_valid_len : validMask.length = bytes.length)
    (h_bounds : ∀ t ∈ Selection.extractSelected merged selectedMask,
      t.startPos + t.length ≤ bytes.length)
    (h_valid_bytes : ∀ t ∈ Selection.extractSelected merged selectedMask,
      ∀ offset, offset < t.length →
        (match validMask[t.startPos + offset]? with | some true => true | _ => false) = true) :
    let selected := Selection.extractSelected merged selectedMask
    let tokenKindIDs := merged.map (·.tokenKindID)
    let ruleIDs := merged.map (·.ruleID)
    let lengths := merged.map (·.len)
    let remappedKinds := vectorizedRemap tokenKindIDs ruleIDs lengths
      selectedMask bytes validMask tables
    selected.map (fun tok =>
      { tok with tokenKindID :=
        match remappedKinds[tok.startPos]? with | some k => k | none => tok.tokenKindID })
    = scalarRemap selected bytes tables := by
  sorry

end KeywordRemap
