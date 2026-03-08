import Testing

@testable import MicroSwiftTensorCore

@Suite
struct CoverageMaskTests {
  @Test(.enabled(if: requiresMLXEval))
  func allBytesCoveredProducesNoErrorSpans() {
    let tokens = [
      token(start: 0, length: 3),
      token(start: 3, length: 2),
      token(start: 5, length: 3),
    ]

    let covered = CoverageMask.build(tokens: tokens, pageSize: 8, validLen: 8)
    let unknown = CoverageMask.unknownBytes(covered: covered, validLen: 8)
    let spans = CoverageMask.errorSpans(unknown: unknown)

    #expect(covered == Array(repeating: true, count: 8))
    #expect(spans.isEmpty)
  }

  @Test(.enabled(if: requiresMLXEval))
  func gapBetweenTokensProducesSingleErrorSpan() {
    let tokens = [
      token(start: 0, length: 2),
      token(start: 4, length: 2),
    ]

    let covered = CoverageMask.build(tokens: tokens, pageSize: 6, validLen: 6)
    let unknown = CoverageMask.unknownBytes(covered: covered, validLen: 6)
    let spans = CoverageMask.errorSpans(unknown: unknown)

    #expect(covered == [true, true, false, false, true, true])
    #expect(spans == [ErrorSpan(start: 2, end: 4)])
  }

  @Test(.enabled(if: requiresMLXEval))
  func uncoveredPrefixProducesErrorSpan() {
    let tokens = [token(start: 2, length: 3)]

    let covered = CoverageMask.build(tokens: tokens, pageSize: 5, validLen: 5)
    let unknown = CoverageMask.unknownBytes(covered: covered, validLen: 5)
    let spans = CoverageMask.errorSpans(unknown: unknown)

    #expect(covered == [false, false, true, true, true])
    #expect(spans == [ErrorSpan(start: 0, end: 2)])
  }

  @Test(.enabled(if: requiresMLXEval))
  func uncoveredSuffixProducesErrorSpan() {
    let tokens = [token(start: 0, length: 3)]

    let covered = CoverageMask.build(tokens: tokens, pageSize: 5, validLen: 5)
    let unknown = CoverageMask.unknownBytes(covered: covered, validLen: 5)
    let spans = CoverageMask.errorSpans(unknown: unknown)

    #expect(covered == [true, true, true, false, false])
    #expect(spans == [ErrorSpan(start: 3, end: 5)])
  }

  @Test(.enabled(if: requiresMLXEval))
  func multipleGapsProduceMultipleErrorSpans() {
    let tokens = [
      token(start: 1, length: 1),
      token(start: 3, length: 1),
      token(start: 6, length: 1),
    ]

    let covered = CoverageMask.build(tokens: tokens, pageSize: 8, validLen: 8)
    let unknown = CoverageMask.unknownBytes(covered: covered, validLen: 8)
    let spans = CoverageMask.errorSpans(unknown: unknown)

    #expect(covered == [false, true, false, true, false, false, true, false])
    #expect(
      spans == [
        ErrorSpan(start: 0, end: 1),
        ErrorSpan(start: 2, end: 3),
        ErrorSpan(start: 4, end: 6),
        ErrorSpan(start: 7, end: 8),
      ])
  }

  @Test(.enabled(if: requiresMLXEval))
  func emptyTokensMakeAllValidBytesUnknown() {
    let covered = CoverageMask.build(tokens: [], pageSize: 6, validLen: 4)
    let unknown = CoverageMask.unknownBytes(covered: covered, validLen: 4)
    let spans = CoverageMask.errorSpans(unknown: unknown)

    #expect(covered == Array(repeating: false, count: 6))
    #expect(unknown == [true, true, true, true, false, false])
    #expect(spans == [ErrorSpan(start: 0, end: 4)])
  }

  @Test(.enabled(if: requiresMLXEval))
  func skipTokensStillContributeToCoverage() {
    let tokens = [
      token(start: 0, length: 2, mode: 1),  // skip token
      token(start: 2, length: 2, mode: 0),
    ]

    let covered = CoverageMask.build(tokens: tokens, pageSize: 4, validLen: 4)
    let unknown = CoverageMask.unknownBytes(covered: covered, validLen: 4)
    let spans = CoverageMask.errorSpans(unknown: unknown)

    #expect(covered == [true, true, true, true])
    #expect(spans.isEmpty)
  }

  private func token(start: Int32, length: UInt16, mode: UInt8 = 0) -> GreedySelector.SelectedToken
  {
    GreedySelector.SelectedToken(
      startPos: start,
      length: length,
      ruleID: 1,
      tokenKindID: 1,
      mode: mode
    )
  }
}
