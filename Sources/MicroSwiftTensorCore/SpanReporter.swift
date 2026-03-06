import MicroSwiftFrontend

public enum SpanReporter {
  /// Convert page-local error spans to source-level Spans.
  public static func resolveErrorSpans(
    errorSpans: [ErrorSpan],
    baseOffset: Int64,
    fileID: FileID
  ) -> [Span] {
    errorSpans.map { error in
      Span(
        fileID: fileID,
        start: ByteOffset(rawValue: baseOffset + Int64(error.start)),
        end: ByteOffset(rawValue: baseOffset + Int64(error.end))
      )
    }
  }
}
