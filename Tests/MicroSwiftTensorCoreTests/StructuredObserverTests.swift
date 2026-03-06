import Foundation
import MicroSwiftFrontend
import Testing

@testable import MicroSwiftTensorCore

@Suite
struct StructuredObserverTests {
  @Test
  func observeCountsTokensErrorsAndOverflows() {
    let source = SourceBuffer(
      fileID: FileID(rawValue: 42),
      path: "sample.swift",
      bytes: Data(repeating: 0x61, count: 128)
    )
    let tape = TokenTape(
      tokens: [
        LogicalToken(kind: 1, flags: 0, startByte: 0, endByte: 3, payloadA: 0, payloadB: 0),
        LogicalToken(kind: 2, flags: 0, startByte: 4, endByte: 5, payloadA: 0, payloadB: 0),
        LogicalToken(kind: 3, flags: 0, startByte: 6, endByte: 10, payloadA: 0, payloadB: 0),
      ],
      errorSpans: [ErrorSpan(start: 11, end: 12), ErrorSpan(start: 20, end: 23)],
      overflows: [
        OverflowDiagnostic(
          message: "lex-page-overflow: line exceeds maximum supported page bucket",
          pageByteCount: 70_000,
          maxBucketSize: 65_536
        )
      ]
    )
    let pages = [
      makePreparedPage(bucket: PageBucket(byteCapacity: 4096), validLen: 100, baseOffset: 0),
      makePreparedPage(bucket: PageBucket(byteCapacity: 8192), validLen: 28, baseOffset: 100),
      makePreparedPage(bucket: nil, validLen: 70_000, baseOffset: 200),
    ]

    let observation = StructuredObserver.observe(source: source, tape: tape, pages: pages)

    #expect(observation.traceID == "f42-b128-p3-t3-e2-o1")
    #expect(observation.fileID == 42)
    #expect(observation.pageCount == 3)
    #expect(observation.totalBytes == 128)
    #expect(observation.tokenCount == 3)
    #expect(observation.errorSpanCount == 2)
    #expect(observation.overflowCount == 1)
  }

  @Test
  func observeComputesPageBucketDistribution() {
    let source = SourceBuffer(
      fileID: FileID(rawValue: 7),
      path: "dist.swift",
      bytes: Data(repeating: 0x62, count: 64)
    )
    let tape = TokenTape(tokens: [], errorSpans: [], overflows: [])
    let pages = [
      makePreparedPage(bucket: PageBucket(byteCapacity: 4096), validLen: 10, baseOffset: 0),
      makePreparedPage(bucket: PageBucket(byteCapacity: 8192), validLen: 20, baseOffset: 10),
      makePreparedPage(bucket: PageBucket(byteCapacity: 4096), validLen: 30, baseOffset: 30),
      makePreparedPage(bucket: PageBucket(byteCapacity: 16384), validLen: 4, baseOffset: 60),
      makePreparedPage(bucket: nil, validLen: 70_000, baseOffset: 100),
    ]

    let observation = StructuredObserver.observe(source: source, tape: tape, pages: pages)

    #expect(observation.pageBucketDistribution == [4096: 2, 8192: 1, 16384: 1])
  }

  private func makePreparedPage(
    bucket: PageBucket?,
    validLen: Int32,
    baseOffset: Int64
  ) -> PreparedPage {
    let sourcePage = SourcePage(
      pageID: 0,
      start: ByteOffset(rawValue: baseOffset),
      end: ByteOffset(rawValue: baseOffset + Int64(validLen)),
      byteCount: validLen,
      lineBreakCount: 0,
      oversize: bucket == nil
    )
    return PreparedPage(
      sourcePage: sourcePage,
      bucket: bucket,
      byteSlice: [UInt8](repeating: 0, count: Int(max(validLen, 0))),
      validLen: validLen,
      baseOffset: baseOffset
    )
  }
}
