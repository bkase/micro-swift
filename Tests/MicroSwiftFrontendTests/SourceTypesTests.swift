import Foundation
import Testing

@testable import MicroSwiftFrontend

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
