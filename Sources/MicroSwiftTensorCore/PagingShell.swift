import Foundation
import MicroSwiftFrontend

public struct PagingShell: Sendable {
  public let pagePolicy: PagePolicy
  public let maxBucketSize: Int32
  public let buckets: [PageBucket]

  public init(
    pagePolicy: PagePolicy = PagePolicy(targetBytes: 32768),
    maxBucketSize: Int32 = 65536,
    buckets: [PageBucket] = PageBucket.standardBuckets
  ) {
    precondition(maxBucketSize > 0, "PagingShell.maxBucketSize must be > 0")
    precondition(!buckets.isEmpty, "PagingShell.buckets must not be empty")
    self.pagePolicy = pagePolicy
    self.maxBucketSize = maxBucketSize
    self.buckets = buckets.sorted { $0.byteCapacity < $1.byteCapacity }
  }

  /// Plan pages from a source buffer using SourcePaging, then prepare each for lexing.
  public func planAndPreparePages(source: SourceBuffer) -> [PreparedPage] {
    let lineStarts = LineStructure.lineStartOffsets(bytes: source.bytes)
    let pages = SourcePaging.planPages(
      lineStartOffsets: lineStarts,
      byteCount: Int64(source.bytes.count),
      policy: pagePolicy
    )

    let sourceBytes = [UInt8](source.bytes)
    let buckets = buckets.filter { $0.byteCapacity <= maxBucketSize }

    return pages.map { page in
      let start = Int(page.start.rawValue)
      let end = Int(page.end.rawValue)
      let validLen = page.byteCount
      let rawSlice = Array(sourceBytes[start..<end])
      let bucket = buckets.first { validLen <= $0.byteCapacity }
      let byteSlice: [UInt8]
      if let bucket {
        byteSlice =
          rawSlice
          + [UInt8](
            repeating: PageBucket.neutralPaddingByte,
            count: Int(bucket.byteCapacity - validLen)
          )
      } else {
        byteSlice = rawSlice
      }

      return PreparedPage(
        sourcePage: page,
        bucket: bucket,
        byteSlice: byteSlice,
        validLen: validLen,
        baseOffset: page.start.rawValue
      )
    }
  }
}

public struct PreparedPage: Sendable {
  public let sourcePage: SourcePage
  public let bucket: PageBucket?  // nil means overflow
  public let byteSlice: [UInt8]  // the actual bytes for this page, padded to bucket capacity
  public let validLen: Int32
  public let baseOffset: Int64

  public init(
    sourcePage: SourcePage,
    bucket: PageBucket?,
    byteSlice: [UInt8],
    validLen: Int32,
    baseOffset: Int64
  ) {
    self.sourcePage = sourcePage
    self.bucket = bucket
    self.byteSlice = byteSlice
    self.validLen = validLen
    self.baseOffset = baseOffset
  }
}
