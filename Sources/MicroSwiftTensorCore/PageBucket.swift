public struct PageBucket: Sendable, Equatable {
  public static let neutralPaddingByte: UInt8 = 0
  public let byteCapacity: Int32

  public init(byteCapacity: Int32) {
    precondition(byteCapacity > 0, "PageBucket.byteCapacity must be > 0")
    self.byteCapacity = byteCapacity
  }

  /// Standard bucket set: 4KB, 8KB, 16KB, 32KB, 64KB
  public static let standardBuckets: [PageBucket] = [
    PageBucket(byteCapacity: 4096),
    PageBucket(byteCapacity: 8192),
    PageBucket(byteCapacity: 16384),
    PageBucket(byteCapacity: 32768),
    PageBucket(byteCapacity: 65536),
  ]

  /// Find the smallest bucket that fits the given byte count, or nil if too large.
  public static func bucket(for byteCount: Int32) -> PageBucket? {
    guard byteCount >= 0 else { return nil }
    return standardBuckets.first { byteCount <= $0.byteCapacity }
  }
}
