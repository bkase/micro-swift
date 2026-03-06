import Foundation
import Testing
import MicroSwiftFrontend
@testable import MicroSwiftTensorCore

@Suite
struct PagingShellTests {
  @Test
  func smallSourceUses4KBBucket() {
    let source = SourceBuffer(
      fileID: FileID(rawValue: 1),
      path: "small.swift",
      bytes: Data("let x = 1\n".utf8)
    )
    let shell = PagingShell()

    let pages = shell.planAndPreparePages(source: source)

    #expect(pages.count == 1)
    #expect(pages[0].sourcePage.byteCount == Int32(source.bytes.count))
    #expect(pages[0].bucket?.byteCapacity == 4096)
    #expect(pages[0].byteSlice.count == 4096)
  }

  @Test
  func emptySourceGetsSingleEmptyPage() {
    let source = SourceBuffer(
      fileID: FileID(rawValue: 1),
      path: "empty.swift",
      bytes: Data()
    )
    let shell = PagingShell()

    let pages = shell.planAndPreparePages(source: source)

    #expect(pages.count == 1)
    #expect(pages[0].sourcePage.start.rawValue == 0)
    #expect(pages[0].sourcePage.end.rawValue == 0)
    #expect(pages[0].validLen == 0)
    #expect(pages[0].bucket?.byteCapacity == 4096)
    #expect(pages[0].byteSlice.count == 4096)
  }

  @Test
  func multiPageSourceRespectsLineBoundaries() {
    let bytes = Data("aaaa\nbbbb\ncccc\n".utf8)
    let source = SourceBuffer(
      fileID: FileID(rawValue: 1),
      path: "multi.swift",
      bytes: bytes
    )
    let shell = PagingShell(pagePolicy: PagePolicy(targetBytes: 8))

    let pages = shell.planAndPreparePages(source: source)

    #expect(pages.count == 3)
    #expect(pages[0].sourcePage.start.rawValue == 0)
    #expect(pages[0].sourcePage.end.rawValue == 5)
    #expect(pages[1].sourcePage.start.rawValue == 5)
    #expect(pages[1].sourcePage.end.rawValue == 10)
    #expect(pages[2].sourcePage.start.rawValue == 10)
    #expect(pages[2].sourcePage.end.rawValue == 15)
    #expect(pages[2].sourcePage.end.rawValue == Int64(bytes.count))
  }

  @Test
  func overlongLineIsOverflow() {
    let source = SourceBuffer(
      fileID: FileID(rawValue: 1),
      path: "overlong.swift",
      bytes: Data(repeating: 0x61, count: 70_000)
    )
    let shell = PagingShell()

    let pages = shell.planAndPreparePages(source: source)

    #expect(pages.count == 1)
    #expect(pages[0].bucket == nil)
    #expect(pages[0].validLen == 70_000)
    #expect(pages[0].byteSlice.count == 70_000)
  }

  @Test
  func pageBytesArePaddedToBucketCapacity() {
    let source = SourceBuffer(
      fileID: FileID(rawValue: 1),
      path: "padding.swift",
      bytes: Data(repeating: 0x41, count: 5_000)
    )
    let shell = PagingShell()

    let pages = shell.planAndPreparePages(source: source)

    #expect(pages.count == 1)
    #expect(pages[0].bucket?.byteCapacity == 8192)
    #expect(pages[0].validLen == 5_000)
    #expect(pages[0].byteSlice.count == 8192)
    #expect(pages[0].byteSlice[4_999] == 0x41)
    #expect(pages[0].byteSlice[5_000] == 0)
    #expect(pages[0].byteSlice[8_191] == 0)
  }
}
