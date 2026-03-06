import Testing

@testable import MicroSwiftTensorCore

@Suite
struct TransportEmitterTests {
  @Test
  func tokensRoundtripThroughPackedRows() {
    let selected = [
      token(start: 0, length: 2, kind: 10, mode: 0),
      token(start: 3, length: 4, kind: 22, mode: 2),
    ]

    let result = TransportEmitter.emit(
      selectedTokens: selected,
      bytes: Array("abcdefghij".utf8),
      validLen: 10,
      remapTables: [],
      options: LexOptions(emitSkipTokens: false),
      maxRowCapacity: 4
    )
    let unpacked = TokenUnpacker.unpack(result: result, baseOffset: 0)

    #expect(result.rowCount == 2)
    #expect(unpacked == [
      LogicalToken(kind: 10, flags: 0, startByte: 0, endByte: 2, payloadA: 0, payloadB: 0),
      LogicalToken(kind: 22, flags: 2, startByte: 3, endByte: 7, payloadA: 0, payloadB: 0),
    ])
  }

  @Test
  func skipTokensAreFilteredWhenEmitSkipTokensIsFalse() {
    let selected = [
      token(start: 0, length: 2, kind: 11, mode: 1),
      token(start: 2, length: 1, kind: 12, mode: 0),
    ]

    let result = TransportEmitter.emit(
      selectedTokens: selected,
      bytes: Array("abc".utf8),
      validLen: 3,
      remapTables: [],
      options: LexOptions(emitSkipTokens: false),
      maxRowCapacity: 3
    )
    let unpacked = TokenUnpacker.unpack(result: result, baseOffset: 0)

    #expect(result.rowCount == 1)
    #expect(unpacked == [
      LogicalToken(kind: 12, flags: 0, startByte: 2, endByte: 3, payloadA: 0, payloadB: 0)
    ])
    #expect(result.errorSpans.isEmpty)
  }

  @Test
  func skipTokensAreKeptWhenEmitSkipTokensIsTrue() {
    let selected = [
      token(start: 0, length: 2, kind: 11, mode: 1),
      token(start: 2, length: 1, kind: 12, mode: 0),
    ]

    let result = TransportEmitter.emit(
      selectedTokens: selected,
      bytes: Array("abc".utf8),
      validLen: 3,
      remapTables: [],
      options: LexOptions(emitSkipTokens: true),
      maxRowCapacity: 3
    )
    let unpacked = TokenUnpacker.unpack(result: result, baseOffset: 0)

    #expect(result.rowCount == 2)
    #expect(unpacked == [
      LogicalToken(kind: 11, flags: 1, startByte: 0, endByte: 2, payloadA: 0, payloadB: 0),
      LogicalToken(kind: 12, flags: 0, startByte: 2, endByte: 3, payloadA: 0, payloadB: 0),
    ])
  }

  @Test
  func errorSpansAreIncludedInResult() {
    let selected = [
      token(start: 1, length: 1, kind: 55, mode: 0)
    ]

    let result = TransportEmitter.emit(
      selectedTokens: selected,
      bytes: Array("abcd".utf8),
      validLen: 4,
      remapTables: [],
      options: LexOptions(emitSkipTokens: false),
      maxRowCapacity: 4
    )

    #expect(result.errorSpans == [
      ErrorSpan(start: 0, end: 1),
      ErrorSpan(start: 2, end: 4),
    ])
  }

  @Test
  func unusedRowsAreZeroPadded() {
    let selected = [
      token(start: 0, length: 1, kind: 99, mode: 0)
    ]

    let result = TransportEmitter.emit(
      selectedTokens: selected,
      bytes: Array("ab".utf8),
      validLen: 2,
      remapTables: [],
      options: LexOptions(emitSkipTokens: false),
      maxRowCapacity: 5
    )

    #expect(result.rowCount == 1)
    #expect(result.packedRows[0] != 0)
    #expect(result.packedRows[1] == 0)
    #expect(result.packedRows[2] == 0)
    #expect(result.packedRows[3] == 0)
    #expect(result.packedRows[4] == 0)
  }

  @Test
  func unpackAppliesBaseOffset() {
    let rows: [UInt64] = [
      PackedToken.pack(localStart: 1, length: 2, tokenKindID: 7, flags: 3),
      PackedToken.pack(localStart: 4, length: 1, tokenKindID: 8, flags: 0),
      0,
    ]
    let result = PageLexResult(
      packedRows: rows,
      rowCount: 2,
      errorSpans: [],
      overflowDiagnostic: nil
    )

    let unpacked = TokenUnpacker.unpack(result: result, baseOffset: 100)

    #expect(unpacked == [
      LogicalToken(kind: 7, flags: 3, startByte: 101, endByte: 103, payloadA: 0, payloadB: 0),
      LogicalToken(kind: 8, flags: 0, startByte: 104, endByte: 105, payloadA: 0, payloadB: 0),
    ])
  }

  private func token(start: Int32, length: UInt16, kind: UInt16, mode: UInt8) -> GreedySelector.SelectedToken {
    GreedySelector.SelectedToken(
      startPos: start,
      length: length,
      ruleID: 1,
      tokenKindID: kind,
      mode: mode
    )
  }
}
