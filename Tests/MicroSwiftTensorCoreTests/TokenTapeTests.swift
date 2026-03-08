import Testing

@testable import MicroSwiftTensorCore

@Suite
struct TokenTapeTests {
  @Test(.enabled(if: requiresMLXEval))
  func assembleSinglePage() {
    let result = PageLexResult(
      packedRows: [
        PackedToken.pack(localStart: 0, length: 3, tokenKindID: 10, flags: 0),
        PackedToken.pack(localStart: 4, length: 1, tokenKindID: 11, flags: 0),
      ],
      rowCount: 2,
      errorSpans: [ErrorSpan(start: 6, end: 7)],
      overflowDiagnostic: nil
    )

    let tape = TokenTape.assemble(
      pageResults: [(result: result, baseOffset: 100)],
      overflows: []
    )

    #expect(
      tape.tokens == [
        LogicalToken(kind: 10, flags: 0, startByte: 100, endByte: 103, payloadA: 0, payloadB: 0),
        LogicalToken(kind: 11, flags: 0, startByte: 104, endByte: 105, payloadA: 0, payloadB: 0),
      ])
    #expect(tape.errorSpans == [ErrorSpan(start: 106, end: 107)])
    #expect(tape.overflows.isEmpty)
  }

  @Test(.enabled(if: requiresMLXEval))
  func assembleMultiplePagesAdjustsOffsets() {
    let page0 = PageLexResult(
      packedRows: [
        PackedToken.pack(localStart: 1, length: 2, tokenKindID: 1, flags: 0)
      ],
      rowCount: 1,
      errorSpans: [ErrorSpan(start: 3, end: 5)],
      overflowDiagnostic: nil
    )
    let page1 = PageLexResult(
      packedRows: [
        PackedToken.pack(localStart: 0, length: 4, tokenKindID: 2, flags: 0)
      ],
      rowCount: 1,
      errorSpans: [ErrorSpan(start: 7, end: 8)],
      overflowDiagnostic: nil
    )

    let overflow = OverflowDiagnostic(
      message: "lex-page-overflow: line exceeds maximum supported page bucket",
      pageByteCount: 70000,
      maxBucketSize: 65536
    )

    let tape = TokenTape.assemble(
      pageResults: [
        (result: page0, baseOffset: 0),
        (result: page1, baseOffset: 50),
      ],
      overflows: [overflow]
    )

    #expect(
      tape.tokens == [
        LogicalToken(kind: 1, flags: 0, startByte: 1, endByte: 3, payloadA: 0, payloadB: 0),
        LogicalToken(kind: 2, flags: 0, startByte: 50, endByte: 54, payloadA: 0, payloadB: 0),
      ])
    #expect(
      tape.errorSpans == [
        ErrorSpan(start: 3, end: 5),
        ErrorSpan(start: 57, end: 58),
      ])
    #expect(tape.overflows == [overflow])
  }

  @Test(.enabled(if: requiresMLXEval))
  func assembleEmptyPages() {
    let tape = TokenTape.assemble(pageResults: [], overflows: [])

    #expect(tape.tokens.isEmpty)
    #expect(tape.errorSpans.isEmpty)
    #expect(tape.overflows.isEmpty)
  }
}
