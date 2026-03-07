import MicroSwiftProofs.Pipeline

namespace TestPipeline
open Pipeline

-- Lemma: scalarRemap only changes tokenKindID, not startPos or length
private theorem scalarRemap_preserves_positions (tokens : List Selection.SelectedToken)
    (bytes : List Nat) (tables : List KeywordRemap.RemapTable) :
    (KeywordRemap.scalarRemap tokens bytes tables).map (fun t => (t.startPos, t.length)) =
    tokens.map (fun t => (t.startPos, t.length)) := by
  simp only [KeywordRemap.scalarRemap, List.map_map]
  congr 1; ext tok
  suffices h : ∀ (tbls : List KeywordRemap.RemapTable) (t : Selection.SelectedToken),
      (tbls.foldl (fun tok table =>
        if tok.ruleID != table.baseRuleID then tok
        else if tok.length > table.maxKeywordLength then tok
        else match table.entries.find? (fun entry =>
            KeywordRemap.sliceMatches bytes tok.startPos tok.length entry.lexeme) with
          | some entry => { tok with tokenKindID := entry.tokenKindID }
          | none => tok) t).startPos = t.startPos ∧
      (tbls.foldl (fun tok table =>
        if tok.ruleID != table.baseRuleID then tok
        else if tok.length > table.maxKeywordLength then tok
        else match table.entries.find? (fun entry =>
            KeywordRemap.sliceMatches bytes tok.startPos tok.length entry.lexeme) with
          | some entry => { tok with tokenKindID := entry.tokenKindID }
          | none => tok) t).length = t.length by
    exact Prod.ext (this tables tok).1 (this tables tok).2
  intro tbls
  induction tbls with
  | nil => intro t; simp
  | cons tbl rest ih =>
    intro t; simp only [List.foldl_cons]
    set t' := (if t.ruleID != tbl.baseRuleID then t
      else if t.length > tbl.maxKeywordLength then t
      else match tbl.entries.find? (fun entry =>
          KeywordRemap.sliceMatches bytes t.startPos t.length entry.lexeme) with
        | some entry => { t with tokenKindID := entry.tokenKindID }
        | none => t)
    have ht' : t'.startPos = t.startPos ∧ t'.length = t.length := by
      simp only [t']
      by_cases h1 : t.ruleID != tbl.baseRuleID
      · simp [h1]
      · simp only [h1, ite_false]
        by_cases h2 : t.length > tbl.maxKeywordLength
        · simp [h2]
        · simp only [h2, ite_false]
          cases tbl.entries.find? (fun entry =>
              KeywordRemap.sliceMatches bytes t.startPos t.length entry.lexeme) with
          | none => simp
          | some entry => simp [Selection.SelectedToken.startPos, Selection.SelectedToken.length]
    obtain ⟨hs, hl⟩ := ih t'
    exact ⟨hs.trans ht'.1, hl.trans ht'.2⟩

-- Lemma: extractSelected token pairs = filterMap from selectedMask + lengths
private theorem extractSelected_pairs_eq_filterMap (merged : List Reduction.Winner)
    (selectedMask : List Bool) (h_len : selectedMask.length = merged.length) :
    (Selection.extractSelected merged selectedMask).map (fun t => (t.startPos, t.length)) =
    (List.range merged.length).filterMap (fun i =>
      if (match selectedMask[i]? with | some true => true | _ => false) then
        some (i, match (merged.map (·.len))[i]? with | some v => v | none => 0)
      else none) := by
  simp only [Selection.extractSelected]
  -- Both construct lists from positions where selectedMask is true
  sorry

end TestPipeline
