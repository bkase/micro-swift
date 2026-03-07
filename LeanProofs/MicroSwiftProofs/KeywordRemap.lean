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

/-! ## Equivalence -/

theorem remap_equiv (tokens : List Selection.SelectedToken) (bytes : List Nat)
    (validMask : List Bool) (tables : List RemapTable)
    (h_bounds : ∀ t ∈ tokens, t.startPos + t.length ≤ bytes.length) :
    -- The vectorized remap, when projected back to selected positions,
    -- yields the same tokenKindIDs as scalar remap.
    -- (Full statement requires aligning page-wide vs sparse representations.)
    True := by
  sorry

end KeywordRemap
