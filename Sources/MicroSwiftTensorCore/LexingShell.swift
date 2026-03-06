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
    var pageResults = [PageLexResult]()
    var overflowPages = [OverflowDiagnostic]()
    pageResults.reserveCapacity(preparedPages.count)

    for page in preparedPages {
      if let diagnostic = OverflowHandler.checkOverflow(
        page: page,
        maxBucketSize: pagingShell.maxBucketSize
      ) {
        overflowPages.append(diagnostic)
        pageResults.append(
          PageLexResult(
            packedRows: [],
            rowCount: 0,
            errorSpans: [],
            overflowDiagnostic: diagnostic
          ))
        continue
      }

      pageResults.append(
        TensorLexer.lexPage(
          bytes: page.byteSlice,
          validLen: page.validLen,
          baseOffset: page.baseOffset,
          artifact: artifact,
          options: options
        ))
    }

    return LexSourceResult(pageResults: pageResults, overflowPages: overflowPages)
  }
}

public struct LexSourceResult: Sendable {
  public let pageResults: [PageLexResult]
  public let overflowPages: [OverflowDiagnostic]

  public init(pageResults: [PageLexResult], overflowPages: [OverflowDiagnostic]) {
    self.pageResults = pageResults
    self.overflowPages = overflowPages
  }
}
