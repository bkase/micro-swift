public struct TokenTape: Sendable {
  public let tokens: [LogicalToken]
  public let errorSpans: [ErrorSpan]  // source-level
  public let overflows: [OverflowDiagnostic]

  public init(
    tokens: [LogicalToken],
    errorSpans: [ErrorSpan],
    overflows: [OverflowDiagnostic]
  ) {
    self.tokens = tokens
    self.errorSpans = errorSpans
    self.overflows = overflows
  }

  /// Build from ordered page results.
  public static func assemble(
    pageResults: [(result: PageLexResult, baseOffset: Int64)],
    overflows: [OverflowDiagnostic]
  ) -> TokenTape {
    var tokens: [LogicalToken] = []
    var errorSpans: [ErrorSpan] = []

    for pageResult in pageResults {
      tokens.append(contentsOf: TokenUnpacker.unpack(result: pageResult.result, baseOffset: pageResult.baseOffset))
      errorSpans.append(
        contentsOf: pageResult.result.errorSpans.map { span in
          let start = pageResult.baseOffset + Int64(span.start)
          let end = pageResult.baseOffset + Int64(span.end)
          guard let sourceStart = Int32(exactly: start),
            let sourceEnd = Int32(exactly: end)
          else {
            preconditionFailure("source-level error span must fit in Int32")
          }
          return ErrorSpan(start: sourceStart, end: sourceEnd)
        }
      )
    }

    return TokenTape(tokens: tokens, errorSpans: errorSpans, overflows: overflows)
  }
}
