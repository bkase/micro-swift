import MicroSwiftFrontend

public enum OverflowHandler {
  /// Check a prepared page for overflow. Returns diagnostic if overflow detected.
  public static func checkOverflow(
    page: PreparedPage,
    maxBucketSize: Int32
  ) -> OverflowDiagnostic? {
    guard page.bucket == nil else { return nil }
    return OverflowDiagnostic(
      message: "lex-page-overflow: line exceeds maximum supported page bucket",
      pageByteCount: page.validLen,
      maxBucketSize: maxBucketSize
    )
  }

  /// Build a source span for the overflow region.
  public static func overflowSpan(
    page: PreparedPage,
    fileID: FileID
  ) -> Span {
    Span(
      fileID: fileID,
      start: ByteOffset(rawValue: page.baseOffset),
      end: ByteOffset(rawValue: page.baseOffset + Int64(page.validLen))
    )
  }
}
