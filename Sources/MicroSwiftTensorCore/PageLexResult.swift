import MLX

public struct PageLexResult: @unchecked Sendable, Equatable {
  public let packedRows: MLXArray
  private let hostPackedRowsStorage: [UInt64]
  public let rowCount: Int32
  public let errorSpans: [ErrorSpan]
  public let overflowDiagnostic: OverflowDiagnostic?

  public init(
    packedRows: [UInt64],
    rowCount: Int32,
    errorSpans: [ErrorSpan],
    overflowDiagnostic: OverflowDiagnostic?
  ) {
    self.packedRows = withMLXCPU { MLXArray(packedRows) }
    self.hostPackedRowsStorage = packedRows
    self.rowCount = rowCount
    self.errorSpans = errorSpans
    self.overflowDiagnostic = overflowDiagnostic
  }

  public func hostPackedRows() -> [UInt64] {
    hostPackedRowsStorage
  }

  public static func == (lhs: PageLexResult, rhs: PageLexResult) -> Bool {
    lhs.hostPackedRows() == rhs.hostPackedRows()
      && lhs.rowCount == rhs.rowCount
      && lhs.errorSpans == rhs.errorSpans
      && lhs.overflowDiagnostic == rhs.overflowDiagnostic
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
