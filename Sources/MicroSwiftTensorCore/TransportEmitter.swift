import MicroSwiftLexerGen

public enum TransportEmitter {
  private static let skipMode: UInt8 = 1

  /// Build the final PageLexResult from selected tokens after all phases.
  ///
  /// 1. Apply keyword remap
  /// 2. Compute coverage from ALL selected tokens (before skip filtering)
  /// 3. Compute error spans from unknown bytes
  /// 4. Filter: keep non-skip tokens (or all if emitSkipTokens)
  /// 5. Keep error spans
  /// 6. Pack kept tokens into UInt64 rows
  /// 7. Zero-pad unused rows
  public static func emit(
    selectedTokens: [GreedySelector.SelectedToken],
    bytes: [UInt8],
    validLen: Int32,
    remapTables: [KeywordRemapTable],
    options: LexOptions,
    maxRowCapacity: Int32
  ) -> PageLexResult {
    precondition(validLen >= 0, "validLen must be non-negative")
    precondition(Int(validLen) <= bytes.count, "validLen must not exceed bytes.count")
    precondition(maxRowCapacity >= 0, "maxRowCapacity must be non-negative")

    let remappedTokens = KeywordRemap.apply(
      tokens: selectedTokens,
      bytes: bytes,
      remapTables: remapTables
    )

    let covered = CoverageMask.build(tokens: remappedTokens, pageSize: bytes.count, validLen: validLen)
    let unknown = CoverageMask.unknownBytes(covered: covered, validLen: validLen)
    let errorSpans = CoverageMask.errorSpans(unknown: unknown)

    let keptTokens: [GreedySelector.SelectedToken]
    if options.emitSkipTokens {
      keptTokens = remappedTokens
    } else {
      keptTokens = remappedTokens.filter { $0.mode != skipMode }
    }

    let capacity = Int(maxRowCapacity)
    precondition(keptTokens.count <= capacity, "kept tokens exceed maxRowCapacity")

    var packedRows = Array(repeating: UInt64.zero, count: capacity)
    for (rowIndex, token) in keptTokens.enumerated() {
      guard let localStart = UInt16(exactly: token.startPos) else {
        preconditionFailure("token startPos must fit in UInt16")
      }

      packedRows[rowIndex] = PackedToken.pack(
        localStart: localStart,
        length: token.length,
        tokenKindID: token.tokenKindID,
        flags: token.mode
      )
    }

    return PageLexResult(
      packedRows: packedRows,
      rowCount: Int32(keptTokens.count),
      errorSpans: errorSpans,
      overflowDiagnostic: nil
    )
  }
}
