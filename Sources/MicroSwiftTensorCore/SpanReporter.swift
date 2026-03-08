import MicroSwiftFrontend

public enum SpanReporter {
  /// Convert page-local error spans to source-level Spans.
  public static func resolveErrorSpans(
    errorSpans: [ErrorSpan],
    baseOffset: Int64,
    fileID: FileID
  ) -> [Span] {
    errorSpans.map { error in
      let start = ByteOffset(rawValue: baseOffset + Int64(error.start))
      let end = ByteOffset(rawValue: baseOffset + Int64(error.end))
      return try! Span.validated(
        fileID: fileID,
        start: start,
        end: end,
        byteCount: end.rawValue
      )
    }
  }
}
