public struct LexFailureRecord: Sendable {
  public let traceID: String
  public let fileID: UInt32
  public let pageBucket: Int32
  public let baseOffset: Int64
  public let validLength: Int32
  public let ruleBucketCounts: [Int]
  public let selectedTokenCount: Int32
  public let errorRunCount: Int32
  public let overflowStatus: String?
  public let overflowMessage: String?
  public let overflowPageByteCount: Int32?
  public let overflowMaxBucketSize: Int32?

  public init(
    traceID: String,
    fileID: UInt32,
    pageBucket: Int32,
    baseOffset: Int64,
    validLength: Int32,
    ruleBucketCounts: [Int],
    selectedTokenCount: Int32,
    errorRunCount: Int32,
    overflowStatus: String?,
    overflowMessage: String?,
    overflowPageByteCount: Int32?,
    overflowMaxBucketSize: Int32?
  ) {
    self.traceID = traceID
    self.fileID = fileID
    self.pageBucket = pageBucket
    self.baseOffset = baseOffset
    self.validLength = validLength
    self.ruleBucketCounts = ruleBucketCounts
    self.selectedTokenCount = selectedTokenCount
    self.errorRunCount = errorRunCount
    self.overflowStatus = overflowStatus
    self.overflowMessage = overflowMessage
    self.overflowPageByteCount = overflowPageByteCount
    self.overflowMaxBucketSize = overflowMaxBucketSize
  }
}
