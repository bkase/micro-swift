import MLX
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

    let covered = CoverageMask.build(
      tokens: remappedTokens, pageSize: bytes.count, validLen: validLen)
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

  /// Tensor-first transport pipeline used by the production fast path.
  public static func emit(
    selectedTokenTensors: GreedySelector.SelectedTokenTensors,
    byteTensor: MLXArray,
    validLen: Int32,
    remapTables: [KeywordRemapTable],
    options: LexOptions,
    maxRowCapacity: Int32
  ) -> PageLexResult {
    precondition(validLen >= 0, "validLen must be non-negative")
    precondition(maxRowCapacity >= 0, "maxRowCapacity must be non-negative")

    let pageSize = Int(byteTensor.shape.first ?? 0)
    let boundedValidLen = max(0, min(Int(validLen), pageSize))
    let capacity = Int(maxRowCapacity)

    guard pageSize > 0, boundedValidLen > 0 else {
      return PageLexResult(
        packedRows: Array(repeating: 0, count: capacity),
        rowCount: 0,
        errorSpans: [],
        overflowDiagnostic: nil
      )
    }

    let remappedTokenKind = applyKeywordRemap(
      tokenTensors: selectedTokenTensors,
      byteTensor: byteTensor,
      validLen: boundedValidLen,
      remapTables: remapTables
    )

    let coveredMask = buildCoverageMask(
      selectedTokenTensors: selectedTokenTensors,
      validLen: boundedValidLen
    )
    let validMask = withMLXCPU {
      arange(pageSize, dtype: .int32) .< Int32(boundedValidLen)
    }
    let unknownMask = withMLXCPU { validMask .&& .!(coveredMask) }
    let errorSpans = CoverageMask.errorSpans(
      unknown: unknownMask.asType(.bool).asArray(Bool.self)
    )

    let keepMask = withMLXCPU {
      options.emitSkipTokens
        ? selectedTokenTensors.selectedMask
        : selectedTokenTensors.selectedMask .&& (selectedTokenTensors.mode .!= skipMode)
    }

    let keptStart = selectedTokenTensors.startPos.asType(.int32).asArray(Int32.self)
    let keptLength = selectedTokenTensors.length.asType(.uint16).asArray(UInt16.self)
    let keptKind = remappedTokenKind.asType(.uint16).asArray(UInt16.self)
    let keptMode = selectedTokenTensors.mode.asType(.uint8).asArray(UInt8.self)
    let keptMaskHost = keepMask.asType(.bool).asArray(Bool.self)

    var packedRows = Array(repeating: UInt64.zero, count: capacity)
    var emitted = 0
    for index in 0..<min(pageSize, keptMaskHost.count) where keptMaskHost[index] {
      precondition(emitted < capacity, "kept tokens exceed maxRowCapacity")
      guard let localStart = UInt16(exactly: keptStart[index]) else {
        preconditionFailure("token startPos must fit in UInt16")
      }
      packedRows[emitted] = PackedToken.pack(
        localStart: localStart,
        length: keptLength[index],
        tokenKindID: keptKind[index],
        flags: keptMode[index]
      )
      emitted += 1
    }

    return PageLexResult(
      packedRows: packedRows,
      rowCount: Int32(emitted),
      errorSpans: errorSpans,
      overflowDiagnostic: nil
    )
  }

  private static func applyKeywordRemap(
    tokenTensors: GreedySelector.SelectedTokenTensors,
    byteTensor: MLXArray,
    validLen: Int,
    remapTables: [KeywordRemapTable]
  ) -> MLXArray {
    guard !remapTables.isEmpty else { return tokenTensors.tokenKindID }

    let pageSize = Int(byteTensor.shape.first ?? 0)
    let boundedValidLen = max(0, min(validLen, pageSize))
    guard boundedValidLen > 0 else { return tokenTensors.tokenKindID }

    return withMLXCPU {
      let validMask = arange(pageSize, dtype: .int32) .< Int32(boundedValidLen)
      var remapped = tokenTensors.tokenKindID.asType(.uint16)

      for table in remapTables {
        let baseRuleMask =
          tokenTensors.selectedMask
          .&& validMask
          .&& (tokenTensors.ruleID.asType(.uint16) .== table.baseRuleID)

        for entry in table.entries {
          let keywordLength = Int(entry.lexeme.count)
          guard keywordLength > 0 else { continue }

          var matchMask =
            baseRuleMask
            .&& (tokenTensors.length.asType(.uint16) .== UInt16(keywordLength))

          for (offset, expectedByte) in entry.lexeme.enumerated() {
            let shiftedBytes = ShiftedTensorView.forward(
              byteTensor.asType(.uint8),
              by: offset,
              padValue: PageBucket.neutralPaddingByte
            )
            let shiftedValid = ShiftedTensorView.forwardValidMask(validMask, by: offset)
            let nextMatchMask = matchMask .&& shiftedValid .&& (shiftedBytes .== expectedByte)
            matchMask = nextMatchMask
          }

          remapped = which(matchMask, UInt16(entry.tokenKindID), remapped).asType(.uint16)
        }
      }

      return remapped
    }
  }

  private static func buildCoverageMask(
    selectedTokenTensors: GreedySelector.SelectedTokenTensors,
    validLen: Int
  ) -> MLXArray {
    let pageSize = Int(selectedTokenTensors.length.shape.first ?? 0)
    guard pageSize > 0, validLen > 0 else {
      return withMLXCPU { zeros([max(pageSize, 0)], dtype: .bool) }
    }

    return withMLXCPU {
      let positions = arange(pageSize, dtype: .int32)
      let selectedMask = selectedTokenTensors.selectedMask.asType(.bool)
      let lengths = selectedTokenTensors.length.asType(.int32)
      var covered = zeros([pageSize], dtype: .bool)

      for start in 0..<min(validLen, pageSize) {
        let startMask = selectedMask .&& (positions .== Int32(start))
        let hasSelection = startMask.any()
        let lengthAtStart = which(
          startMask,
          lengths,
          zeros([pageSize], dtype: .int32)
        ).sum()
        let tokenEnd = MLXArray(Int32(start)) + lengthAtStart
        let rangeMask = (positions .>= Int32(start)) .&& (positions .< tokenEnd)
        let nextCovered = covered .|| (hasSelection .&& rangeMask)
        covered = nextCovered
      }

      let validMask = positions .< Int32(validLen)
      return covered .&& validMask
    }
  }
}
