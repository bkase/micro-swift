import Foundation
import MLX

public enum ResultExtractionBoundary: Sendable {
  case finalTransport
  case testInspection
}

public struct ResultHostMaterializationCounts: Sendable, Equatable {
  public let finalTransport: Int
  public let testInspection: Int

  public init(finalTransport: Int, testInspection: Int) {
    self.finalTransport = finalTransport
    self.testInspection = testInspection
  }
}

public struct PageLexResult: Sendable, Equatable {
  private static let hostMaterializationCounter = ResultHostMaterializationCounter()

  private let packedRowStorage: PackedRowStorageBox
  public let rowCount: Int32
  public let errorSpans: [ErrorSpan]
  public let overflowDiagnostic: OverflowDiagnostic?

  public init(
    packedRows: [UInt64],
    rowCount: Int32,
    errorSpans: [ErrorSpan] = [],
    overflowDiagnostic: OverflowDiagnostic? = nil
  ) {
    self.packedRowStorage = PackedRowStorageBox(hostPackedRows: packedRows)
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
    self.packedRowStorage = PackedRowStorageBox(devicePackedRows: packedRowsTensor.asType(.uint64))
    self.rowCount = rowCount
    self.errorSpans = errorSpans
    self.overflowDiagnostic = overflowDiagnostic
  }

  public func hostPackedRows() -> [UInt64] {
    extractHostPackedRows(at: .finalTransport)
  }

  public func extractHostPackedRows(at boundary: ResultExtractionBoundary) -> [UInt64] {
    packedRowStorage.hostPackedRows(boundary: boundary)
  }

  /// MLX-backed packed rows for device execution. Created on demand.
  public func mlxPackedRows() -> MLXArray {
    packedRowStorage.mlxPackedRows()
  }

  public static func resetHostMaterializationCounts() {
    hostMaterializationCounter.reset()
  }

  public static func hostMaterializationCounts() -> ResultHostMaterializationCounts {
    ResultHostMaterializationCounts(
      finalTransport: hostMaterializationCounter.count(for: .finalTransport),
      testInspection: hostMaterializationCounter.count(for: .testInspection)
    )
  }

  public static func == (lhs: PageLexResult, rhs: PageLexResult) -> Bool {
    lhs.hostPackedRows() == rhs.hostPackedRows()
      && lhs.rowCount == rhs.rowCount
      && lhs.errorSpans == rhs.errorSpans
      && lhs.overflowDiagnostic == rhs.overflowDiagnostic
  }

  private static func recordHostMaterialization(_ boundary: ResultExtractionBoundary) {
    hostMaterializationCounter.record(boundary)
  }

  private final class PackedRowStorageBox: @unchecked Sendable {
    private let lock = NSLock()
    private var hostPackedRows: [UInt64]?
    private let devicePackedRows: MLXArray?

    init(hostPackedRows: [UInt64]) {
      self.hostPackedRows = hostPackedRows
      self.devicePackedRows = nil
    }

    init(devicePackedRows: MLXArray) {
      self.hostPackedRows = nil
      self.devicePackedRows = devicePackedRows
    }

    func hostPackedRows(boundary: ResultExtractionBoundary) -> [UInt64] {
      lock.lock()
      if let hostPackedRows {
        lock.unlock()
        return hostPackedRows
      }
      let devicePackedRows = self.devicePackedRows
      lock.unlock()

      let materialized = devicePackedRows?.asType(.uint64).asArray(UInt64.self) ?? []
      lock.lock()
      if hostPackedRows == nil {
        hostPackedRows = materialized
        PageLexResult.recordHostMaterialization(boundary)
      }
      let snapshot = hostPackedRows ?? materialized
      lock.unlock()
      return snapshot
    }

    func mlxPackedRows() -> MLXArray {
      lock.lock()
      let hostPackedRows = self.hostPackedRows
      let devicePackedRows = self.devicePackedRows
      lock.unlock()

      if let devicePackedRows {
        return devicePackedRows.asType(.uint64)
      }
      return MLXArray(hostPackedRows ?? []).asType(.uint64)
    }
  }
}

private final class ResultHostMaterializationCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var counts: [ResultExtractionBoundary: Int] = [:]

  func reset() {
    lock.lock()
    counts.removeAll(keepingCapacity: true)
    lock.unlock()
  }

  func record(_ boundary: ResultExtractionBoundary) {
    lock.lock()
    counts[boundary, default: 0] += 1
    lock.unlock()
  }

  func count(for boundary: ResultExtractionBoundary) -> Int {
    lock.lock()
    let value = counts[boundary] ?? 0
    lock.unlock()
    return value
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
