import Foundation

// MARK: - HostLineIndex

public struct HostLineIndex: Hashable, Sendable {
  public let lineStartOffsets: [Int64]
  public let lineCount: Int32

  public init(lineStartOffsets: [Int64], lineCount: Int32) {
    self.lineStartOffsets = lineStartOffsets
    self.lineCount = lineCount
  }
}

// MARK: - Line structure derivation

public enum LineStructure {
  /// Compute line-terminator-end mask per the M1 newline contract:
  /// LF, lone CR (not followed by LF), or the LF of a CRLF pair.
  public static func lineTerminatorEndMask(bytes: Data) -> [Bool] {
    let n = bytes.count
    guard n > 0 else { return [] }
    return bytes.withUnsafeBytes { buf in
      let ptr = buf.bindMemory(to: UInt8.self)
      var mask = [Bool](repeating: false, count: n)
      for i in 0..<n {
        let isLF = ptr[i] == 0x0A
        let isCR = ptr[i] == 0x0D
        let nextIsLF = (i + 1 < n) && (ptr[i + 1] == 0x0A)
        mask[i] = isLF || (isCR && !nextIsLF)
      }
      return mask
    }
  }

  /// Derive compact line-start offsets from a line-terminator-end mask.
  /// Always starts with 0. Each set bit at index i contributes i+1 as a line start.
  public static func lineStartOffsets(mask: [Bool]) -> [Int64] {
    var offsets: [Int64] = [0]
    for (i, isEnd) in mask.enumerated() where isEnd {
      offsets.append(Int64(i + 1))
    }
    return offsets
  }

  /// Derive line-start offsets directly from raw bytes.
  public static func lineStartOffsets(bytes: Data) -> [Int64] {
    lineStartOffsets(mask: lineTerminatorEndMask(bytes: bytes))
  }

  /// Build a HostLineIndex from raw bytes.
  public static func hostLineIndex(bytes: Data) -> HostLineIndex {
    let offsets = lineStartOffsets(bytes: bytes)
    return HostLineIndex(
      lineStartOffsets: offsets,
      lineCount: Int32(offsets.count)
    )
  }
}

// MARK: - Location resolver

public enum SourceResolver {
  /// Resolve a byte offset to a SourceLocation using binary search on lineStartOffsets.
  /// Valid for offsets in 0...byteCount.
  public static func resolve(
    _ offset: ByteOffset,
    fileID: FileID,
    hostLineIndex: HostLineIndex
  ) -> SourceLocation {
    let offsets = hostLineIndex.lineStartOffsets
    // upperBound: first element > offset
    var lo = 0
    var hi = offsets.count
    while lo < hi {
      let mid = lo + (hi - lo) / 2
      if offsets[mid] <= offset.rawValue {
        lo = mid + 1
      } else {
        hi = mid
      }
    }
    // line0 = upperBound - 1
    let line0 = lo - 1
    let column0 = offset.rawValue - offsets[line0]
    return SourceLocation(
      fileID: fileID,
      line: LineIndex(rawValue: Int32(line0)),
      column: ColumnIndex(rawValue: Int32(column0))
    )
  }
}
