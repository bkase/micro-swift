import MLX

public enum ResultExtractionBoundary: Sendable {
  case finalTransport
  case testInspection
}

public struct PageLexResult: Sendable, Equatable {
  private let hostPackedRowsStorage: [UInt64]
  public let rowCount: Int32
  public let errorSpans: [ErrorSpan]
  public let overflowDiagnostic: OverflowDiagnostic?

  public init(
    packedRows: [UInt64],
    rowCount: Int32,
    errorSpans: [ErrorSpan] = [],
    overflowDiagnostic: OverflowDiagnostic? = nil
  ) {
    self.hostPackedRowsStorage = packedRows
    self.rowCount = rowCount
    self.errorSpans = errorSpans
    self.overflowDiagnostic = overflowDiagnostic
  }

  public init(
    packedRowsTensor: MLXArray,
    rowCount: Int32,
    errorSpans: [ErrorSpan] = [],
    overflowDiagnostic: OverflowDiagnostic? = nil
  ) {
    self.hostPackedRowsStorage = packedRowsTensor.asType(.uint64).asArray(UInt64.self)
    self.rowCount = rowCount
    self.errorSpans = errorSpans
    self.overflowDiagnostic = overflowDiagnostic
  }

  public func hostPackedRows() -> [UInt64] {
    extractHostPackedRows(at: .finalTransport)
  }

  public func extractHostPackedRows(at boundary: ResultExtractionBoundary) -> [UInt64] {
    _ = boundary
    return hostPackedRowsStorage
  }

  /// MLX-backed packed rows for device execution. Created on demand.
  public func mlxPackedRows() -> MLXArray {
    withMLXCPU { MLXArray(hostPackedRowsStorage).asType(.uint64) }
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
