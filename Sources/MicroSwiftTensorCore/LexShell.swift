public enum LexShellError: Error, Sendable, Equatable {
  case pageOverflow(actual: Int, max: Int)
}

public struct LexShell: Sendable {
  public init() {}

  public func lexFile(
    bytes: [UInt8],
    artifact: ArtifactRuntime,
    options: LexOptions
  ) throws -> [PageLexResult] {
    let maxPageSize = pageCapacity(for: artifact)

    if bytes.isEmpty {
      let pageResult = lexPage(
        bytes: bytes,
        validLen: Int32(bytes.count),
        baseOffset: 0,
        artifact: artifact,
        options: options
      )

      return [pad(result: pageResult, to: maxPageSize)]
    }

    var results: [PageLexResult] = []
    var offset = 0

    while offset < bytes.count {
      let pageLen = min(maxPageSize, bytes.count - offset)
      let pageBytes = Array(bytes[offset..<(offset + pageLen)])
      let pageResult = lexPage(
        bytes: pageBytes,
        validLen: Int32(pageLen),
        baseOffset: Int64(offset),
        artifact: artifact,
        options: options
      )

      results.append(pad(result: pageResult, to: maxPageSize))
      offset += pageLen
    }

    return results
  }

  private func pageCapacity(for artifact: ArtifactRuntime) -> Int {
    let lookahead = Int(artifact.runtimeHints.maxDeterministicLookaheadBytes)
    if lookahead > 0 { return lookahead }
    return max(1, Int(artifact.runtimeHints.maxBoundedRuleWidth))
  }

  private func pad(result: PageLexResult, to width: Int) -> PageLexResult {
    guard result.packedRows.count < width else {
      return result
    }
    let padded =
      result.packedRows + Array(repeating: UInt64(0), count: width - result.packedRows.count)
    return PageLexResult(packedRows: padded, rowCount: result.rowCount)
  }
}
