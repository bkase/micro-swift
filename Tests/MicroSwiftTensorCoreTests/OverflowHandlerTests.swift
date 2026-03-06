import Testing
import MicroSwiftFrontend
@testable import MicroSwiftTensorCore

@Suite
struct OverflowHandlerTests {
  @Test
  func nonOverflowPageReturnsNilDiagnostic() {
    let page = makePreparedPage(
      bucket: PageBucket(byteCapacity: 4096),
      validLen: 128,
      baseOffset: 42
    )

    let diagnostic = OverflowHandler.checkOverflow(page: page, maxBucketSize: 65536)

    #expect(diagnostic == nil)
  }

  @Test
  func overflowPageReturnsDiagnostic() {
    let page = makePreparedPage(bucket: nil, validLen: 70_000, baseOffset: 0)

    let diagnostic = OverflowHandler.checkOverflow(page: page, maxBucketSize: 65536)

    #expect(diagnostic != nil)
    #expect(diagnostic?.message == "lex-page-overflow: line exceeds maximum supported page bucket")
    #expect(diagnostic?.pageByteCount == 70_000)
    #expect(diagnostic?.maxBucketSize == 65536)
  }

  @Test
  func overflowSpanCoversRegion() {
    let page = makePreparedPage(bucket: nil, validLen: 100, baseOffset: 1_000)
    let fileID = FileID(rawValue: 7)

    let span = OverflowHandler.overflowSpan(page: page, fileID: fileID)

    #expect(span.fileID == fileID)
    #expect(span.start == ByteOffset(rawValue: 1_000))
    #expect(span.end == ByteOffset(rawValue: 1_100))
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
