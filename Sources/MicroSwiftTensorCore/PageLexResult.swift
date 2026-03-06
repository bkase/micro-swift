public struct PageLexResult: Sendable {
  public let packedRows: [UInt64]
  public let rowCount: Int32
  public let errorSpans: [ErrorSpan]
  public let overflowDiagnostic: OverflowDiagnostic?

  public init(
    packedRows: [UInt64],
    rowCount: Int32,
    errorSpans: [ErrorSpan],
    overflowDiagnostic: OverflowDiagnostic?
  ) {
    self.packedRows = packedRows
    self.rowCount = rowCount
    self.errorSpans = errorSpans
    self.overflowDiagnostic = overflowDiagnostic
  }
}

public struct ErrorSpan: Sendable, Equatable {
  public let start: Int32
  public let end: Int32

  public init(start: Int32, end: Int32) {
    self.start = start
    self.end = end
  }
}

public struct OverflowDiagnostic: Sendable, Equatable {
  public let message: String
  public let pageByteCount: Int32
  public let maxBucketSize: Int32

  public init(message: String, pageByteCount: Int32, maxBucketSize: Int32) {
    self.message = message
    self.pageByteCount = pageByteCount
    self.maxBucketSize = maxBucketSize
  }
}
