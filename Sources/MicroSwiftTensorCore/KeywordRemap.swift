import MicroSwiftLexerGen

public enum KeywordRemap {
  /// Apply keyword remaps to selected tokens.
  /// For each selected token, check if its ruleID matches a remap table's baseRuleID.
  /// If so, compare the token's byte slice against remap entries.
  /// On exact match, replace the tokenKindID.
  ///
  /// Returns new array of selected tokens with remapped kinds.
  public static func apply(
    tokens: [GreedySelector.SelectedToken],
    bytes: [UInt8],
    remapTables: [KeywordRemapTable]
  ) -> [GreedySelector.SelectedToken] {
    guard !tokens.isEmpty, !remapTables.isEmpty else { return tokens }

    var remapped = tokens

    for index in remapped.indices {
      let token = remapped[index]
      let start = Int(token.startPos)
      let length = Int(token.length)
      let end = start + length

      guard start >= 0, end <= bytes.count else { continue }

      for table in remapTables where table.baseRuleID == token.ruleID {
        if token.length > UInt16(table.maxKeywordLength) {
          continue
        }

        let slice = bytes[start..<end]

        for entry in table.entries {
          if entry.lexeme.count == length, entry.lexeme.elementsEqual(slice) {
            remapped[index] = GreedySelector.SelectedToken(
              startPos: token.startPos,
              length: token.length,
              ruleID: token.ruleID,
              tokenKindID: entry.tokenKindID,
              mode: token.mode
            )
            break
          }
        }
      }
    }

    return remapped
  }
}
