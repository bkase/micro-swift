import Foundation
import Testing

@testable import MicroSwiftFrontend

@Suite
struct FileIDTests {
  @Test func rawRoundTrip() {
    let id = FileID(rawValue: 42)
    #expect(id.rawValue == 42)
  }

  @Test func equality() {
    #expect(FileID(rawValue: 1) == FileID(rawValue: 1))
    #expect(FileID(rawValue: 1) != FileID(rawValue: 2))
  }

  @Test func hashable() {
    let set: Set<FileID> = [FileID(rawValue: 1), FileID(rawValue: 1), FileID(rawValue: 2)]
    #expect(set.count == 2)
  }
}

@Suite
struct ByteOffsetTests {
  @Test func rawRoundTrip() {
    let o = ByteOffset(rawValue: 100)
    #expect(o.rawValue == 100)
  }

  @Test func comparable() {
    #expect(ByteOffset(rawValue: 0) < ByteOffset(rawValue: 1))
    #expect(!(ByteOffset(rawValue: 5) < ByteOffset(rawValue: 5)))
  }
}

@Suite
struct LineIndexTests {
  @Test func comparable() {
    #expect(LineIndex(rawValue: 0) < LineIndex(rawValue: 1))
  }
}

@Suite
struct ColumnIndexTests {
  @Test func comparable() {
    #expect(ColumnIndex(rawValue: 0) < ColumnIndex(rawValue: 3))
  }
}

@Suite
struct SpanTests {
  let fid = FileID(rawValue: 1)

  @Test func validZeroWidthSpan() throws {
    let span = try Span.validated(
      fileID: fid,
      start: ByteOffset(rawValue: 5),
      end: ByteOffset(rawValue: 5),
      byteCount: 10
    )
    #expect(span.start == ByteOffset(rawValue: 5))
    #expect(span.end == ByteOffset(rawValue: 5))
  }

  @Test func validFullFileSpan() throws {
    let span = try Span.validated(
      fileID: fid,
      start: ByteOffset(rawValue: 0),
      end: ByteOffset(rawValue: 10),
      byteCount: 10
    )
    #expect(span.start.rawValue == 0)
    #expect(span.end.rawValue == 10)
  }

  @Test func rejectsNegativeStart() {
    #expect(throws: SpanError.negativeOffset(-1)) {
      try Span.validated(
        fileID: fid,
        start: ByteOffset(rawValue: -1),
        end: ByteOffset(rawValue: 5),
        byteCount: 10
      )
    }
  }

  @Test func rejectsNegativeEnd() {
    #expect(throws: SpanError.negativeOffset(-3)) {
      try Span.validated(
        fileID: fid,
        start: ByteOffset(rawValue: 0),
        end: ByteOffset(rawValue: -3),
        byteCount: 10
      )
    }
  }

  @Test func rejectsStartAfterEnd() {
    #expect(throws: SpanError.startAfterEnd(start: 6, end: 5)) {
      try Span.validated(
        fileID: fid,
        start: ByteOffset(rawValue: 6),
        end: ByteOffset(rawValue: 5),
        byteCount: 10
      )
    }
  }

  @Test func rejectsEndBeyondBounds() {
    #expect(throws: SpanError.endBeyondBounds(end: 11, byteCount: 10)) {
      try Span.validated(
        fileID: fid,
        start: ByteOffset(rawValue: 0),
        end: ByteOffset(rawValue: 11),
        byteCount: 10
      )
    }
  }

  @Test func validatedWithBuffer() throws {
    let buffer = SourceBuffer(
      fileID: fid,
      path: "/test.swift",
      bytes: Data([0x61, 0x62, 0x63])  // "abc"
    )
    let span = try Span.validated(
      fileID: fid,
      start: ByteOffset(rawValue: 0),
      end: ByteOffset(rawValue: 3),
      in: buffer
    )
    #expect(span.end.rawValue == 3)
  }

  @Test func rejectsFileIDMismatch() {
    let buffer = SourceBuffer(
      fileID: FileID(rawValue: 99),
      path: "/test.swift",
      bytes: Data([0x61])
    )
    #expect(throws: SpanError.fileIDMismatch(expected: 99, got: 1)) {
      try Span.validated(
        fileID: fid,
        start: ByteOffset(rawValue: 0),
        end: ByteOffset(rawValue: 1),
        in: buffer
      )
    }
  }

  @Test func spanEquality() throws {
    let a = try Span.validated(
      fileID: fid, start: ByteOffset(rawValue: 0), end: ByteOffset(rawValue: 5), byteCount: 10)
    let b = try Span.validated(
      fileID: fid, start: ByteOffset(rawValue: 0), end: ByteOffset(rawValue: 5), byteCount: 10)
    #expect(a == b)
  }
}

@Suite
struct SourceBufferTests {
  @Test func preservesExactBytes() {
    let raw = Data([0x00, 0xFF, 0x0A, 0x0D, 0xC3, 0xA9])
    let buffer = SourceBuffer(fileID: FileID(rawValue: 1), path: "/test", bytes: raw)
    #expect(buffer.bytes == raw)
  }

  @Test func emptyFile() {
    let buffer = SourceBuffer(fileID: FileID(rawValue: 0), path: "/empty", bytes: Data())
    #expect(buffer.bytes.isEmpty)
  }
}
