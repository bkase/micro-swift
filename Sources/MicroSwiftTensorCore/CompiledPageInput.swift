import Foundation
import MLX

public enum HostExtractionBoundary: Sendable {
  case finalPackedRows
  case testInspection
  case transitionalFamilyExecution
}

public struct HostExtractionCounts: Sendable, Equatable {
  public let finalPackedRows: Int
  public let testInspection: Int
  public let transitionalFamilyExecution: Int

  public init(finalPackedRows: Int, testInspection: Int, transitionalFamilyExecution: Int) {
    self.finalPackedRows = finalPackedRows
    self.testInspection = testInspection
    self.transitionalFamilyExecution = transitionalFamilyExecution
  }
}

public struct HostPageExecutionView: Sendable {
  public let bytes: [UInt8]
  public let classIDs: [UInt8]
  public let validMask: [Bool]

  public init(bytes: [UInt8], classIDs: [UInt8], validMask: [Bool]) {
    self.bytes = bytes
    self.classIDs = classIDs
    self.validMask = validMask
  }
}

public struct CompiledPageInput {
  private static let hostExtractionCounter = HostExtractionCounter()

  public let bucket: PageBucket
  public let validLen: Int32
  public let baseOffset: Int64

  public let byteTensor: MLXArray?
  public let classIDTensor: MLXArray?
  public let validMaskTensor: MLXArray?
  public let byteTensorShape: [Int]
  public let classIDTensorShape: [Int]
  public let validMaskTensorShape: [Int]
  public let byteTensorDType: DType
  public let classIDTensorDType: DType
  public let validMaskTensorDType: DType

  private let hostPaddedBytesStorage: [UInt8]
  private let hostClassIDsStorage: [UInt8]
  private let hostValidMaskStorage: [Bool]

  public var byteCapacity: Int {
    Int(bucket.byteCapacity)
  }

  public init(
    bytes: [UInt8],
    validLen: Int32,
    baseOffset: Int64,
    bucket: PageBucket,
    artifact: ArtifactRuntime
  ) {
    precondition(validLen >= 0, "validLen must be non-negative")
    precondition(Int(validLen) <= bytes.count, "validLen must be <= bytes.count")

    let capacity = Int(bucket.byteCapacity)
    precondition(capacity > 0, "bucket capacity must be positive")
    precondition(bytes.count <= capacity, "bytes.count must be <= bucket capacity")

    self.bucket = bucket
    self.validLen = min(validLen, bucket.byteCapacity)
    self.baseOffset = baseOffset

    let paddedBytes = Self.padToBucket(bytes: bytes, bucket: bucket)
    self.hostPaddedBytesStorage = paddedBytes
    let hostClassIDs = ByteClassifier.classify(
      bytes: paddedBytes,
      byteToClassLUT: artifact.hostByteToClassLUT()
    )
    self.hostClassIDsStorage = hostClassIDs
    let hostValidMask = Self.validMask(pageSize: capacity, validLen: self.validLen)
    self.hostValidMaskStorage = hostValidMask

    self.byteTensorShape = [capacity]
    self.byteTensorDType = .uint8

    self.validMaskTensorShape = [capacity]
    self.validMaskTensorDType = .bool

    if Self.shouldUseHostClassificationFallback() {
      self.byteTensor = nil
      self.validMaskTensor = nil
      self.classIDTensor = nil
    } else {
      let byteTensor = withMLXCPU {
        MLXArray(paddedBytes, [capacity]).asType(.uint8)
      }
      let validMaskTensor = withMLXCPU {
        MLXArray(hostValidMask, [capacity]).asType(.bool)
      }
      let classIDTensor = withMLXCPU {
        let byteIndices = byteTensor.asType(.int32)
        return artifact.mlxByteToClassLUT().take(byteIndices).asType(.uint16)
      }
      self.byteTensor = byteTensor
      self.validMaskTensor = validMaskTensor
      self.classIDTensor = classIDTensor
    }
    self.classIDTensorShape = [capacity]
    self.classIDTensorDType = .uint16
  }

  public init(preparedPage: PreparedPage, artifact: ArtifactRuntime) {
    precondition(preparedPage.bucket != nil, "overflow pages cannot be compiled")
    self.init(
      bytes: preparedPage.byteSlice,
      validLen: preparedPage.validLen,
      baseOffset: preparedPage.baseOffset,
      bucket: preparedPage.bucket!,
      artifact: artifact
    )
  }

  public static func padToBucket(bytes: [UInt8], bucket: PageBucket) -> [UInt8] {
    let capacity = Int(bucket.byteCapacity)
    precondition(bytes.count <= capacity, "bytes.count must be <= bucket capacity")

    guard bytes.count < capacity else { return bytes }
    let padCount = capacity - bytes.count
    return bytes + [UInt8](repeating: PageBucket.neutralPaddingByte, count: padCount)
  }

  public static func validMask(pageSize: Int, validLen: Int32) -> [Bool] {
    precondition(pageSize >= 0, "pageSize must be non-negative")
    precondition(validLen >= 0, "validLen must be non-negative")
    return (0..<pageSize).map { $0 < Int(validLen) }
  }

  public func shiftedByteTensor(by shift: Int) -> MLXArray {
    guard let byteTensor else {
      return withMLXCPU { MLXArray(hostPaddedBytesStorage, [byteCapacity]).asType(.uint8) }
    }
    return ShiftedTensorView.forward(
      byteTensor,
      by: shift,
      padValue: PageBucket.neutralPaddingByte
    )
  }

  public func shiftedValidMaskTensor(by shift: Int) -> MLXArray {
    let mask = validRangeMask(dtype: .bool)
    return ShiftedTensorView.forwardValidMask(mask, by: shift)
  }

  public func deterministicTailZeroed(_ tensor: MLXArray) -> MLXArray {
    guard let validMaskTensor else { return tensor }
    return withMLXCPU {
      let zerosTensor = zeros(like: tensor)
      return which(validMaskTensor, tensor, zerosTensor)
    }
  }

  public func validRangeMask(dtype: DType = .bool) -> MLXArray {
    guard let validMaskTensor else {
      return withMLXCPU { MLXArray(hostValidMaskStorage, [byteCapacity]).asType(dtype) }
    }
    if dtype == .bool {
      return validMaskTensor
    }
    return validMaskTensor.asType(dtype)
  }

  public func extractHostExecutionView(at boundary: HostExtractionBoundary) -> HostPageExecutionView
  {
    Self.recordHostExtraction(boundary)
    return HostPageExecutionView(
      bytes: hostPaddedBytesStorage,
      classIDs: hostClassIDsStorage,
      validMask: hostValidMaskStorage
    )
  }

  public func hostPaddedBytesForInspection() -> [UInt8] {
    hostPaddedBytesStorage
  }

  static func hostExecutionViewForPipeline(_ page: CompiledPageInput) -> HostPageExecutionView {
    HostPageExecutionView(
      bytes: page.hostPaddedBytesStorage,
      classIDs: page.hostClassIDsStorage,
      validMask: page.hostValidMaskStorage
    )
  }

  public static func resetHostExtractionCounts() {
    hostExtractionCounter.reset()
  }

  public static func hostExtractionCounts() -> HostExtractionCounts {
    let finalPackedRows = hostExtractionCounter.count(for: .finalPackedRows)
    let testInspection = hostExtractionCounter.count(for: .testInspection)
    let transitionalFamilyExecution = hostExtractionCounter.count(for: .transitionalFamilyExecution)
    return HostExtractionCounts(
      finalPackedRows: finalPackedRows,
      testInspection: testInspection,
      transitionalFamilyExecution: transitionalFamilyExecution
    )
  }

  private static func shouldUseHostClassificationFallback() -> Bool {
    let processInfo = ProcessInfo.processInfo
    return processInfo.environment["MICROSWIFT_ENABLE_DEVICE_CLASSIFICATION"] != "1"
  }

  private static func recordHostExtraction(_ boundary: HostExtractionBoundary) {
    hostExtractionCounter.record(boundary)
  }
}

private final class HostExtractionCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var counts: [HostExtractionBoundary: Int] = [:]

  func reset() {
    lock.lock()
    counts.removeAll(keepingCapacity: true)
    lock.unlock()
  }

  func record(_ boundary: HostExtractionBoundary) {
    lock.lock()
    counts[boundary, default: 0] += 1
    lock.unlock()
  }

  func count(for boundary: HostExtractionBoundary) -> Int {
    lock.lock()
    let value = counts[boundary] ?? 0
    lock.unlock()
    return value
  }
}
