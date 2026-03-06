import Foundation
import Testing

@testable import MicroSwiftFrontend

@Suite
struct PagePlannerTests {
  // MARK: - Empty file

  @Test func emptyFileProducesOneEmptyPage() {
    let pages = SourcePaging.planPages(
      lineStartOffsets: [0],
      byteCount: 0,
      policy: PagePolicy(targetBytes: 64)
    )
    #expect(pages.count == 1)
    #expect(pages[0].pageID == 0)
    #expect(pages[0].start.rawValue == 0)
    #expect(pages[0].end.rawValue == 0)
    #expect(pages[0].byteCount == 0)
    #expect(pages[0].lineBreakCount == 0)
    #expect(pages[0].oversize == false)
  }

  // MARK: - Small file fits in one page

  @Test func smallFileNoTrailingNewline() {
    // "a\nb\nc" = 5 bytes, lineStarts=[0,2,4]
    // Pages split at line-aligned boundaries: [0,4) and [4,5)
    let pages = SourcePaging.planPages(
      lineStartOffsets: [0, 2, 4],
      byteCount: 5,
      policy: PagePolicy(targetBytes: 64)
    )
    #expect(pages.count == 2)
    #expect(pages[0].start.rawValue == 0)
    #expect(pages[0].end.rawValue == 4)
    #expect(pages[0].lineBreakCount == 2)
    #expect(pages[1].start.rawValue == 4)
    #expect(pages[1].end.rawValue == 5)
    #expect(pages[1].lineBreakCount == 0)
  }

  @Test func smallFileWithTrailingNewline() {
    // "a\nb\n" = 4 bytes, lineStarts=[0,2,4]
    // byteCount=4, target=64→4, greatest lineStart <=4 and >0 → 4 → end=4
    // Single page [0,4)
    let pages = SourcePaging.planPages(
      lineStartOffsets: [0, 2, 4],
      byteCount: 4,
      policy: PagePolicy(targetBytes: 64)
    )
    #expect(pages.count == 1)
    #expect(pages[0].start.rawValue == 0)
    #expect(pages[0].end.rawValue == 4)
    #expect(pages[0].byteCount == 4)
    #expect(pages[0].lineBreakCount == 2)
    #expect(pages[0].oversize == false)
  }

  // MARK: - Multi-page split

  @Test func multiPageSplitsAtLineStart() {
    // "abcd\nefgh\nijkl" = 14 bytes, lineStarts=[0,5,10]
    let pages = SourcePaging.planPages(
      lineStartOffsets: [0, 5, 10],
      byteCount: 14,
      policy: PagePolicy(targetBytes: 8)
    )
    // target=8: greatest line start <= 8 and > 0 is 5 → page [0,5)
    // target=5+8=13: greatest line start <= 13 and > 5 is 10 → page [5,10)
    // target=10+8=18: >= 14, so end=14 → page [10,14)
    #expect(pages.count == 3)
    #expect(pages[0].start.rawValue == 0)
    #expect(pages[0].end.rawValue == 5)
    #expect(pages[1].start.rawValue == 5)
    #expect(pages[1].end.rawValue == 10)
    #expect(pages[2].start.rawValue == 10)
    #expect(pages[2].end.rawValue == 14)
  }

  // MARK: - Oversize page

  @Test func oversizeSingleLine() {
    // One line of 200 bytes, no newline
    // lineStarts=[0]
    let pages = SourcePaging.planPages(
      lineStartOffsets: [0],
      byteCount: 200,
      policy: PagePolicy(targetBytes: 64)
    )
    #expect(pages.count == 1)
    #expect(pages[0].oversize == true)
    #expect(pages[0].byteCount == 200)
    #expect(pages[0].lineBreakCount == 0)
  }

  @Test func oversizeLineFollowedByNormal() {
    // 200 bytes of 'a', then \n, then 10 bytes of 'b'
    // lineStarts=[0, 201], byteCount=211
    let pages = SourcePaging.planPages(
      lineStartOffsets: [0, 201],
      byteCount: 211,
      policy: PagePolicy(targetBytes: 64)
    )
    // target=64: greatest line start <= 64 and > 0 → none (only 0, 201)
    //   smallest line start > 64 → 201 → page [0,201) oversize
    // target=201+64=265: > 211, end=211 → page [201,211)
    #expect(pages.count == 2)
    #expect(pages[0].oversize == true)
    #expect(pages[0].byteCount == 201)
    #expect(pages[1].oversize == false)
    #expect(pages[1].byteCount == 10)
  }

  // MARK: - Coverage invariants

  @Test func pagesAreContiguousAndNonOverlapping() {
    for fixture in SourceFixtures.all {
      let offsets = LineStructure.lineStartOffsets(bytes: fixture.bytes)
      let pages = SourcePaging.planPages(
        lineStartOffsets: offsets,
        byteCount: Int64(fixture.bytes.count),
        policy: PagePolicy(targetBytes: 8)
      )
      guard !pages.isEmpty else { continue }
      // First page starts at 0
      #expect(pages[0].start.rawValue == 0, "Fixture \(fixture.name): first page must start at 0")
      // Last page ends at byteCount
      #expect(
        pages[pages.count - 1].end.rawValue == Int64(fixture.bytes.count),
        "Fixture \(fixture.name): last page must end at byteCount"
      )
      // Contiguous
      for i in 1..<pages.count {
        #expect(
          pages[i].start == pages[i - 1].end,
          "Fixture \(fixture.name): gap between pages \(i-1) and \(i)"
        )
      }
    }
  }

  @Test func sumBytesEqualsFileSize() {
    for fixture in SourceFixtures.all {
      let offsets = LineStructure.lineStartOffsets(bytes: fixture.bytes)
      let pages = SourcePaging.planPages(
        lineStartOffsets: offsets,
        byteCount: Int64(fixture.bytes.count),
        policy: PagePolicy(targetBytes: 8)
      )
      let totalBytes = pages.reduce(Int64(0)) { $0 + Int64($1.byteCount) }
      #expect(totalBytes == Int64(fixture.bytes.count), "Fixture \(fixture.name)")
    }
  }

  @Test func sumLineBreaksEqualsLineCountMinusOne() {
    for fixture in SourceFixtures.all {
      let offsets = LineStructure.lineStartOffsets(bytes: fixture.bytes)
      let pages = SourcePaging.planPages(
        lineStartOffsets: offsets,
        byteCount: Int64(fixture.bytes.count),
        policy: PagePolicy(targetBytes: 8)
      )
      let totalBreaks = pages.reduce(Int32(0)) { $0 + $1.lineBreakCount }
      let lineCount = Int32(offsets.count)
      #expect(totalBreaks == lineCount - 1, "Fixture \(fixture.name)")
    }
  }

  @Test func pageEndsAreLineStartsOrEOF() {
    for fixture in SourceFixtures.all {
      let offsets = LineStructure.lineStartOffsets(bytes: fixture.bytes)
      let offsetSet = Set(offsets)
      let eof = Int64(fixture.bytes.count)
      let pages = SourcePaging.planPages(
        lineStartOffsets: offsets,
        byteCount: eof,
        policy: PagePolicy(targetBytes: 8)
      )
      for page in pages {
        let isLineStart = offsetSet.contains(page.end.rawValue)
        let isEOF = page.end.rawValue == eof
        #expect(
          isLineStart || isEOF,
          "Fixture \(fixture.name): page end \(page.end.rawValue) is neither line start nor EOF")
      }
    }
  }

  @Test func pageIDsAreSequential() {
    for fixture in SourceFixtures.all {
      let offsets = LineStructure.lineStartOffsets(bytes: fixture.bytes)
      let pages = SourcePaging.planPages(
        lineStartOffsets: offsets,
        byteCount: Int64(fixture.bytes.count),
        policy: PagePolicy(targetBytes: 8)
      )
      for (i, page) in pages.enumerated() {
        #expect(page.pageID == Int32(i), "Fixture \(fixture.name)")
      }
    }
  }
}

// MARK: - Property tests

@Suite
struct PagePlannerPropertyTests {
  struct Xorshift64 {
    var state: UInt64
    mutating func next() -> UInt64 {
      state ^= state << 13
      state ^= state >> 7
      state ^= state << 17
      return state
    }
    mutating func nextByte() -> UInt8 { UInt8(next() & 0xFF) }
  }

  @Test func propertyTestRandomCorpora() {
    var rng = Xorshift64(state: 0xCAFE_BABE_DEAD_BEEF)
    for _ in 0..<100 {
      let length = Int(rng.next() % 512)
      var bytes = [UInt8]()
      for _ in 0..<length { bytes.append(rng.nextByte()) }
      let data = Data(bytes)
      let offsets = LineStructure.lineStartOffsets(bytes: data)
      let targetBytes = Int32(max(1, rng.next() % 128))
      let policy = PagePolicy(targetBytes: targetBytes)
      let pages = SourcePaging.planPages(
        lineStartOffsets: offsets, byteCount: Int64(length), policy: policy)

      // Coverage
      #expect(!pages.isEmpty)
      #expect(pages[0].start.rawValue == 0)
      #expect(pages.last!.end.rawValue == Int64(length))

      // Contiguous
      for i in 1..<pages.count {
        #expect(pages[i].start == pages[i - 1].end)
      }

      // Sum bytes
      let totalBytes = pages.reduce(Int64(0)) { $0 + Int64($1.byteCount) }
      #expect(totalBytes == Int64(length))

      // Sum line breaks
      let totalBreaks = pages.reduce(Int32(0)) { $0 + $1.lineBreakCount }
      #expect(totalBreaks == Int32(offsets.count) - 1)

      // Ends are line starts or EOF
      let offsetSet = Set(offsets)
      for page in pages {
        #expect(offsetSet.contains(page.end.rawValue) || page.end.rawValue == Int64(length))
      }
    }
  }
}
