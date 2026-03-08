import MicroSwiftFrontend
import Testing

@testable import MicroSwiftTensorCore

@Suite
struct SpanReporterTests {
  @Test(.enabled(if: requiresMLXEval))
  func errorSpansAreOffsetByBaseOffset() {
    let spans = [
      ErrorSpan(start: 0, end: 2),
      ErrorSpan(start: 5, end: 9),
    ]
    let fileID = FileID(rawValue: 11)

    let resolved = SpanReporter.resolveErrorSpans(
      errorSpans: spans,
      baseOffset: 100,
      fileID: fileID
    )

    #expect(resolved.count == 2)
    #expect(resolved[0].fileID == fileID)
    #expect(resolved[0].start == ByteOffset(rawValue: 100))
    #expect(resolved[0].end == ByteOffset(rawValue: 102))
    #expect(resolved[1].start == ByteOffset(rawValue: 105))
    #expect(resolved[1].end == ByteOffset(rawValue: 109))
  }

  @Test(.enabled(if: requiresMLXEval))
  func emptyErrorSpansReturnEmptyResult() {
    let resolved = SpanReporter.resolveErrorSpans(
      errorSpans: [],
      baseOffset: 42,
      fileID: FileID(rawValue: 1)
    )

    #expect(resolved.isEmpty)
  }
}
