import Foundation
import Testing

@testable import MicroSwiftFrontend

@Suite
struct SourceSnapshotTests {
  let fid = FileID(rawValue: 1)
  let policy = PagePolicy(targetBytes: 8)

  @Test func emptyFileJSONGolden() throws {
    let ps = SourceLoader.prepareHostOnly(
      fileID: fid, path: "/empty", bytes: Data(), pagePolicy: policy)
    let json = try SourceDump.canonicalJSON(from: ps)
    let expected = """
      {
        "byteCount" : 0,
        "fileID" : 1,
        "lineCount" : 1,
        "lineStartOffsets" : [
          0
        ],
        "pages" : [
          {
            "byteCount" : 0,
            "end" : 0,
            "lineBreakCount" : 0,
            "oversize" : false,
            "pageID" : 0,
            "start" : 0
          }
        ]
      }
      """
    #expect(json == expected)
  }

  @Test func threeLineFileJSONGolden() throws {
    // "abc\ndef\nghi" = 11 bytes, lineStarts=[0,4,8], pageTarget=8
    let bytes = Data("abc\ndef\nghi".utf8)
    let ps = SourceLoader.prepareHostOnly(
      fileID: fid, path: "/test", bytes: bytes, pagePolicy: policy)
    let json = try SourceDump.canonicalJSON(from: ps)
    // Verify it's valid JSON and round-trips
    let decoded = try JSONDecoder().decode(SourceSnapshot.self, from: Data(json.utf8))
    #expect(decoded.fileID == 1)
    #expect(decoded.byteCount == 11)
    #expect(decoded.lineCount == 3)
    #expect(decoded.lineStartOffsets == [0, 4, 8])
    // Pages should be: [0,8) and [8,11)
    #expect(decoded.pages.count == 2)
    #expect(decoded.pages[0].start == 0)
    #expect(decoded.pages[0].end == 8)
    #expect(decoded.pages[1].start == 8)
    #expect(decoded.pages[1].end == 11)
  }

  @Test func textDumpContainsAllFields() {
    let bytes = Data("a\nb".utf8)
    let ps = SourceLoader.prepareHostOnly(
      fileID: fid, path: "/test", bytes: bytes, pagePolicy: policy)
    let text = SourceDump.textDump(from: ps)
    #expect(text.contains("fileID: 1"))
    #expect(text.contains("byteCount: 3"))
    #expect(text.contains("lineCount: 2"))
    #expect(text.contains("lineStartOffsets: [0, 2]"))
    #expect(text.contains("pages:"))
  }

  @Test func oversizePageMarkedInText() {
    // 200 bytes of 'a', no newline → oversize with targetBytes=8
    let bytes = Data(Array(repeating: UInt8(0x61), count: 200))
    let ps = SourceLoader.prepareHostOnly(
      fileID: fid, path: "/big", bytes: bytes, pagePolicy: policy)
    let text = SourceDump.textDump(from: ps)
    #expect(text.contains("OVERSIZE"))
  }

  @Test func snapshotRoundTrips() throws {
    for fixture in SourceFixtures.all {
      let ps = SourceLoader.prepareHostOnly(
        fileID: fid, path: "/\(fixture.name)", bytes: fixture.bytes, pagePolicy: policy)
      let json = try SourceDump.canonicalJSON(from: ps)
      let decoded = try JSONDecoder().decode(SourceSnapshot.self, from: Data(json.utf8))
      let snap = SourceDump.snapshot(from: ps)
      #expect(decoded == snap, "Fixture \(fixture.name): snapshot round-trip mismatch")
    }
  }
}

// MARK: - Determinism soak

@Suite
struct SnapshotDeterminismTests {
  let fid = FileID(rawValue: 1)

  @Test func determinismSoakSmall() throws {
    let bytes = Data("a\nb\r\nc\rd\ne".utf8)
    let policy = PagePolicy(targetBytes: 4)
    let ps = SourceLoader.prepareHostOnly(
      fileID: fid, path: "/soak", bytes: bytes, pagePolicy: policy)
    let referenceJSON = try SourceDump.canonicalJSON(from: ps)
    for _ in 0..<50 {
      let ps2 = SourceLoader.prepareHostOnly(
        fileID: fid, path: "/soak", bytes: bytes, pagePolicy: policy)
      let json2 = try SourceDump.canonicalJSON(from: ps2)
      #expect(json2 == referenceJSON, "Determinism soak failed")
    }
  }

  @Test func determinismSoakLarge() throws {
    var bytes = [UInt8]()
    for i in 0..<10000 {
      bytes.append(contentsOf: "line\(i)\n".utf8)
    }
    let data = Data(bytes)
    let policy = PagePolicy(targetBytes: 256)
    let ps = SourceLoader.prepareHostOnly(
      fileID: fid, path: "/large", bytes: data, pagePolicy: policy)
    let referenceJSON = try SourceDump.canonicalJSON(from: ps)
    for _ in 0..<5 {
      let ps2 = SourceLoader.prepareHostOnly(
        fileID: fid, path: "/large", bytes: data, pagePolicy: policy)
      let json2 = try SourceDump.canonicalJSON(from: ps2)
      #expect(json2 == referenceJSON, "Large determinism soak failed")
    }
  }
}
