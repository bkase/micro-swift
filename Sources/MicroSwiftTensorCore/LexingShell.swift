import MicroSwiftFrontend

public struct LexingShell: Sendable {
  public let pagingShell: PagingShell

  public init(pagingShell: PagingShell = PagingShell()) {
    self.pagingShell = pagingShell
  }

  /// Lex all pages of a source buffer. Returns page results in order.
  /// For now, calls lexPage stub for each non-overflow page.
  public func lexSource(
    source: SourceBuffer,
    artifact: ArtifactRuntime,
    options: LexOptions
  ) -> LexSourceResult {
    let preparedPages = pagingShell.planAndPreparePages(source: source)
    var pageResults: [(result: PageLexResult, baseOffset: Int64)] = []
    var overflowPages = [OverflowDiagnostic]()
    pageResults.reserveCapacity(preparedPages.count)

    for page in preparedPages {
      if let diagnostic = OverflowHandler.checkOverflow(
        page: page,
        maxBucketSize: pagingShell.maxBucketSize
      ) {
        overflowPages.append(diagnostic)
        pageResults.append(
          (
            result: PageLexResult(
              packedRows: [],
              rowCount: 0,
              errorSpans: [],
              overflowDiagnostic: diagnostic
            ),
            baseOffset: page.baseOffset
          ))
        continue
      }

      pageResults.append(
        (
          result: padResult(
            TensorLexer.lexPage(
              bytes: page.byteSlice,
              validLen: page.validLen,
              baseOffset: page.baseOffset,
              artifact: artifact,
              options: options
            ),
            to: page.byteSlice.count
          ),
          baseOffset: page.baseOffset
        ))
    }

    let tokenTape = TokenTape.assemble(pageResults: pageResults, overflows: overflowPages)
    return LexSourceResult(
      tokenTape: tokenTape, pageResults: pageResults, overflowPages: overflowPages)
  }

  private func padResult(_ result: PageLexResult, to width: Int) -> PageLexResult {
    guard result.packedRows.count < width else { return result }
    let paddedRows =
      result.packedRows + Array(repeating: UInt64(0), count: width - result.packedRows.count)
    return PageLexResult(
      packedRows: paddedRows,
      rowCount: result.rowCount,
      errorSpans: result.errorSpans,
      overflowDiagnostic: result.overflowDiagnostic
    )
  }
}

public struct LexSourceResult: Sendable {
  public let tokenTape: TokenTape
  public let pageResults: [(result: PageLexResult, baseOffset: Int64)]
  public let overflowPages: [OverflowDiagnostic]

  public init(
    tokenTape: TokenTape,
    pageResults: [(result: PageLexResult, baseOffset: Int64)],
    overflowPages: [OverflowDiagnostic]
  ) {
    self.tokenTape = tokenTape
    self.pageResults = pageResults
    self.overflowPages = overflowPages
  }
}
