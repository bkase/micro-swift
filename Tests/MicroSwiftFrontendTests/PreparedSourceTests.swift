import Foundation
import Testing

@testable import MicroSwiftFrontend

@Suite
struct SourceLoaderTests {
  let fid = FileID(rawValue: 1)
  let policy = PagePolicy(targetBytes: 64)

  @Test func prepareEmptyFile() {
    let ps = SourceLoader.prepareHostOnly(
      fileID: fid, path: "/empty", bytes: Data(), pagePolicy: policy)
    #expect(ps.buffer.bytes.isEmpty)
    #expect(ps.tape == nil)
    #expect(ps.hostLineIndex.lineStartOffsets == [0])
    #expect(ps.hostLineIndex.lineCount == 1)
    #expect(ps.pages.count == 1)
    #expect(ps.pages[0].byteCount == 0)
  }

  @Test func preparePreservesExactBytes() {
    let raw = Data([0x00, 0xFF, 0x0A, 0x0D, 0xC3, 0xA9])
    let ps = SourceLoader.prepareHostOnly(
      fileID: fid, path: "/test", bytes: raw, pagePolicy: policy)
    #expect(ps.buffer.bytes == raw)
  }

  @Test func lineStartsMatchFixtures() {
    for fixture in SourceFixtures.all {
      let ps = SourceLoader.prepareHostOnly(
        fileID: fid, path: "/\(fixture.name)", bytes: fixture.bytes, pagePolicy: policy)
      #expect(
        ps.hostLineIndex.lineStartOffsets == fixture.expectedLineStartOffsets,
        "Fixture \(fixture.name): lineStarts mismatch"
      )
    }
  }

  @Test func pageCoverageForAllFixtures() {
    for fixture in SourceFixtures.all {
      let ps = SourceLoader.prepareHostOnly(
        fileID: fid, path: "/\(fixture.name)", bytes: fixture.bytes, pagePolicy: policy)
      let totalBytes = ps.pages.reduce(Int64(0)) { $0 + Int64($1.byteCount) }
      #expect(totalBytes == Int64(fixture.bytes.count), "Fixture \(fixture.name): page bytes")
    }
  }

  @Test func loadWithReadFile() throws {
    let raw = Data([0x61, 0x0A, 0x62])
    let ps = try SourceLoader.load(
      fileID: fid,
      path: "/mock",
      pagePolicy: policy,
      readFile: { _ in raw }
    )
    #expect(ps.buffer.bytes == raw)
    #expect(ps.buffer.path == "/mock")
    #expect(ps.tape == nil)
  }

  @Test func loadReadFailure() {
    #expect(throws: SourceLoadError.readFailed("/bad")) {
      try SourceLoader.load(
        fileID: fid,
        path: "/bad",
        pagePolicy: policy,
        readFile: { _ in throw NSError(domain: "test", code: 1) }
      )
    }
  }
}

@Suite
struct SourceQueriesTests {
  let fid = FileID(rawValue: 1)

  @Test func resolveViaQueries() {
    // "a\nb"
    let ps = SourceLoader.prepareHostOnly(
      fileID: fid, path: "/t", bytes: Data([0x61, 0x0A, 0x62]),
      pagePolicy: PagePolicy(targetBytes: 64))
    let loc = SourceQueries.resolve(ByteOffset(rawValue: 2), in: ps)
    #expect(loc.line == LineIndex(rawValue: 1))
    #expect(loc.column == ColumnIndex(rawValue: 0))
  }

  @Test func makeSpanViaQueries() throws {
    let ps = SourceLoader.prepareHostOnly(
      fileID: fid, path: "/t", bytes: Data([0x61, 0x62, 0x63]),
      pagePolicy: PagePolicy(targetBytes: 64))
    let span = try SourceQueries.makeSpan(
      fileID: fid, start: ByteOffset(rawValue: 0), end: ByteOffset(rawValue: 3), in: ps)
    #expect(span.start.rawValue == 0)
    #expect(span.end.rawValue == 3)
  }

  @Test func makeSpanRejectsWrongFileID() {
    let ps = SourceLoader.prepareHostOnly(
      fileID: fid, path: "/t", bytes: Data([0x61]),
      pagePolicy: PagePolicy(targetBytes: 64))
    #expect(throws: SpanError.self) {
      try SourceQueries.makeSpan(
        fileID: FileID(rawValue: 99),
        start: ByteOffset(rawValue: 0),
        end: ByteOffset(rawValue: 1),
        in: ps
      )
    }
  }
}
