import Foundation
import MicroSwiftFrontend

public struct LexObservation: Sendable, Codable {
  public let traceID: String
  public let fileID: UInt32
  public let pageCount: Int
  public let totalBytes: Int64
  public let tokenCount: Int
  public let errorSpanCount: Int
  public let overflowCount: Int
  public let pageBucketDistribution: [Int32: Int]

  public init(
    traceID: String,
    fileID: UInt32,
    pageCount: Int,
    totalBytes: Int64,
    tokenCount: Int,
    errorSpanCount: Int,
    overflowCount: Int,
    pageBucketDistribution: [Int32: Int]
  ) {
    self.traceID = traceID
    self.fileID = fileID
    self.pageCount = pageCount
    self.totalBytes = totalBytes
    self.tokenCount = tokenCount
    self.errorSpanCount = errorSpanCount
    self.overflowCount = overflowCount
    self.pageBucketDistribution = pageBucketDistribution
  }
}

public enum StructuredObserver {
  public static func observe(
    source: SourceBuffer,
    tape: TokenTape,
    pages: [PreparedPage]
  ) -> LexObservation {
    var bucketDistribution: [Int32: Int] = [:]
    bucketDistribution.reserveCapacity(pages.count)

    for page in pages {
      guard let bucket = page.bucket else { continue }
      bucketDistribution[bucket.byteCapacity, default: 0] += 1
    }

    let traceID = "f\(source.fileID.rawValue)-b\(source.bytes.count)-p\(pages.count)-t\(tape.tokens.count)-e\(tape.errorSpans.count)-o\(tape.overflows.count)"

    return LexObservation(
      traceID: traceID,
      fileID: source.fileID.rawValue,
      pageCount: pages.count,
      totalBytes: Int64(source.bytes.count),
      tokenCount: tape.tokens.count,
      errorSpanCount: tape.errorSpans.count,
      overflowCount: tape.overflows.count,
      pageBucketDistribution: bucketDistribution
    )
  }
}
