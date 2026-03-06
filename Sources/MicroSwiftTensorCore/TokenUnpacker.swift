public enum TokenUnpacker {
  /// Unpack a PageLexResult's packed rows into LogicalTokens.
  /// Applies baseOffset to convert page-local starts to source-level byte offsets.
  public static func unpack(
    result: PageLexResult,
    baseOffset: Int64
  ) -> [LogicalToken] {
    precondition(result.rowCount >= 0, "rowCount must be non-negative")
    precondition(Int(result.rowCount) <= result.packedRows.count, "rowCount must not exceed packedRows.count")

    var tokens: [LogicalToken] = []
    tokens.reserveCapacity(Int(result.rowCount))

    for rowIndex in 0..<Int(result.rowCount) {
      let packed = result.packedRows[rowIndex]
      let localStart = Int64(PackedToken.unpackLocalStart(packed))
      let length = Int64(PackedToken.unpackLength(packed))
      let startByte = baseOffset + localStart

      tokens.append(
        LogicalToken(
          kind: PackedToken.unpackTokenKindID(packed),
          flags: PackedToken.unpackFlags(packed),
          startByte: startByte,
          endByte: startByte + length,
          payloadA: 0,
          payloadB: 0
        ))
    }

    return tokens
  }
}
