import Foundation

// MARK: - Fixed-width identity types

public struct FileID: RawRepresentable, Hashable, Sendable {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }
}

public struct ByteOffset: RawRepresentable, Comparable, Hashable, Sendable {
  public let rawValue: Int64
  public init(rawValue: Int64) { self.rawValue = rawValue }
  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct LineIndex: RawRepresentable, Comparable, Hashable, Sendable {
  public let rawValue: Int32
  public init(rawValue: Int32) { self.rawValue = rawValue }
  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct ColumnIndex: RawRepresentable, Comparable, Hashable, Sendable {
  public let rawValue: Int32
  public init(rawValue: Int32) { self.rawValue = rawValue }
  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - SourceLocation

public struct SourceLocation: Hashable, Sendable {
  public let fileID: FileID
  public let line: LineIndex
  public let column: ColumnIndex

  public init(fileID: FileID, line: LineIndex, column: ColumnIndex) {
    self.fileID = fileID
    self.line = line
    self.column = column
  }
}

// MARK: - Span

public enum SpanError: Error, Equatable {
  case negativeOffset(Int64)
  case startAfterEnd(start: Int64, end: Int64)
  case endBeyondBounds(end: Int64, byteCount: Int64)
  case fileIDMismatch(expected: UInt32, got: UInt32)
}

public struct Span: Hashable, Sendable {
  public let fileID: FileID
  public let start: ByteOffset
  public let end: ByteOffset

  public init(fileID: FileID, start: ByteOffset, end: ByteOffset) {
    self.fileID = fileID
    self.start = start
    self.end = end
  }

  public static func validated(
    fileID: FileID,
    start: ByteOffset,
    end: ByteOffset,
    byteCount: Int64
  ) throws -> Span {
    guard start.rawValue >= 0 else {
      throw SpanError.negativeOffset(start.rawValue)
    }
    guard end.rawValue >= 0 else {
      throw SpanError.negativeOffset(end.rawValue)
    }
    guard start <= end else {
      throw SpanError.startAfterEnd(start: start.rawValue, end: end.rawValue)
    }
    guard end.rawValue <= byteCount else {
      throw SpanError.endBeyondBounds(end: end.rawValue, byteCount: byteCount)
    }
    return Span(fileID: fileID, start: start, end: end)
  }

  public static func validated(
    fileID: FileID,
    start: ByteOffset,
    end: ByteOffset,
    in buffer: SourceBuffer
  ) throws -> Span {
    guard fileID == buffer.fileID else {
      throw SpanError.fileIDMismatch(expected: buffer.fileID.rawValue, got: fileID.rawValue)
    }
    return try validated(
      fileID: fileID,
      start: start,
      end: end,
      byteCount: Int64(buffer.bytes.count)
    )
  }
}

// MARK: - SourceBuffer

public struct SourceBuffer: Sendable {
  public let fileID: FileID
  public let path: String
  public let bytes: Data

  public init(fileID: FileID, path: String, bytes: Data) {
    self.fileID = fileID
    self.path = path
    self.bytes = bytes
  }
}
