import Foundation

// MARK: - PagePolicy

public struct PagePolicy: Hashable, Sendable {
  public let targetBytes: Int32

  public init(targetBytes: Int32) {
    precondition(targetBytes > 0, "PagePolicy.targetBytes must be > 0")
    self.targetBytes = targetBytes
  }
}

// MARK: - SourcePage

public struct SourcePage: Hashable, Sendable {
  public let pageID: Int32
  public let start: ByteOffset
  public let end: ByteOffset
  public let byteCount: Int32
  public let lineBreakCount: Int32
  public let oversize: Bool

  public init(
    pageID: Int32,
    start: ByteOffset,
    end: ByteOffset,
    byteCount: Int32,
    lineBreakCount: Int32,
    oversize: Bool
  ) {
    self.pageID = pageID
    self.start = start
    self.end = end
    self.byteCount = byteCount
    self.lineBreakCount = lineBreakCount
    self.oversize = oversize
  }
}

// MARK: - Page planner

public enum SourcePaging {
  /// Plan pages for a source file.
  ///
  /// - `lineStartOffsets`: strictly increasing, starts with 0, in `0...byteCount`
  /// - `byteCount`: total byte count of the source
  /// - `policy`: page sizing policy
  ///
  /// Pages are newline-aligned or EOF-aligned. Each page boundary falls on a
  /// line start or at EOF.
  public static func planPages(
    lineStartOffsets: [Int64],
    byteCount: Int64,
    policy: PagePolicy
  ) -> [SourcePage] {
    // Empty file: one empty page
    if byteCount == 0 {
      return [
        SourcePage(
          pageID: 0,
          start: ByteOffset(rawValue: 0),
          end: ByteOffset(rawValue: 0),
          byteCount: 0,
          lineBreakCount: 0,
          oversize: false
        )
      ]
    }

    var pages = [SourcePage]()
    var start: Int64 = 0
    var pageID: Int32 = 0

    while start < byteCount {
      let target = min(start + Int64(policy.targetBytes), byteCount)

      // Find `end`: greatest line start <= target and > start, else smallest line start > target, else byteCount
      let end: Int64

      // upperBound for target: first lineStart > target
      let ubTarget = upperBound(lineStartOffsets, target)
      // Greatest line start <= target is at ubTarget - 1
      // But we need it > start
      let bestBelow = ubTarget - 1
      if bestBelow >= 0 && lineStartOffsets[bestBelow] > start {
        end = lineStartOffsets[bestBelow]
      } else if ubTarget < lineStartOffsets.count {
        end = lineStartOffsets[ubTarget]
      } else {
        end = byteCount
      }

      // Count line breaks in [start, end): line starts in (start, end]
      let lbStart = lowerBound(lineStartOffsets, start + 1)
      let ubEnd = upperBound(lineStartOffsets, end)
      let lineBreaks = Int32(ubEnd - lbStart)

      let pageBytes = Int32(end - start)
      pages.append(
        SourcePage(
          pageID: pageID,
          start: ByteOffset(rawValue: start),
          end: ByteOffset(rawValue: end),
          byteCount: pageBytes,
          lineBreakCount: lineBreaks,
          oversize: pageBytes > policy.targetBytes
        ))

      start = end
      pageID += 1
    }

    return pages
  }

  // Binary search: index of first element >= value
  private static func lowerBound(_ sorted: [Int64], _ value: Int64) -> Int {
    var lo = 0
    var hi = sorted.count
    while lo < hi {
      let mid = lo + (hi - lo) / 2
      if sorted[mid] < value {
        lo = mid + 1
      } else {
        hi = mid
      }
    }
    return lo
  }

  // Binary search: index of first element > value
  private static func upperBound(_ sorted: [Int64], _ value: Int64) -> Int {
    var lo = 0
    var hi = sorted.count
    while lo < hi {
      let mid = lo + (hi - lo) / 2
      if sorted[mid] <= value {
        lo = mid + 1
      } else {
        hi = mid
      }
    }
    return lo
  }
}
