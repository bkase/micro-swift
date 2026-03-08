import MicroSwiftProofs.Pipeline

namespace TestPipeline
open Pipeline

private theorem scalarRemap_preserves_positions (tokens : List Selection.SelectedToken)
    (bytes : List Nat) (tables : List KeywordRemap.RemapTable) :
    (KeywordRemap.scalarRemap tokens bytes tables).map (fun t => (t.startPos, t.length)) =
    tokens.map (fun t => (t.startPos, t.length)) :=
  KeywordRemap.scalarRemap_preserves_pairs tokens bytes tables

private theorem extractSelected_pairs_eq_filterMap (merged : List Reduction.Winner)
    (selectedMask : List Bool) (h_len : selectedMask.length = merged.length) :
    (Selection.extractSelected merged selectedMask).map (fun t => (t.startPos, t.length)) =
    (List.range merged.length).filterMap (fun i =>
      if (match selectedMask[i]? with | some true => true | _ => false) then
        some (i, match (merged.map (·.len))[i]? with | some v => v | none => 0)
      else none) :=
  Selection.extractSelected_pairs merged selectedMask h_len

end TestPipeline
