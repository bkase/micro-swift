public enum CoverageMask {
  /// Build coverage mask from selected tokens (before skip filtering) using
  /// a delta array and prefix sum over page-local byte coordinates.
  public static func build(
    tokens: [GreedySelector.SelectedToken],
    pageSize: Int,
    validLen: Int32
  ) -> [Bool] {
    precondition(pageSize >= 0, "pageSize must be non-negative")
    precondition(validLen >= 0, "validLen must be non-negative")
    precondition(Int(validLen) <= pageSize, "validLen must not exceed pageSize")

    var delta = Array(repeating: 0, count: pageSize + 1)

    for token in tokens {
      let start = Int(token.startPos)
      let end = start + Int(token.length)

      precondition(start >= 0, "token startPos must be non-negative")
      precondition(start <= pageSize, "token startPos must be <= pageSize")
      precondition(end >= start, "token length must not underflow")
      precondition(end <= pageSize, "token end must be <= pageSize")

      delta[start] += 1
      delta[end] -= 1
    }

    var covered = Array(repeating: false, count: pageSize)
    var running = 0
    for i in 0..<pageSize {
      running += delta[i]
      covered[i] = running > 0
    }

    return covered
  }

  /// Find uncovered (unknown) bytes in the valid page prefix.
  public static func unknownBytes(
    covered: [Bool],
    validLen: Int32
  ) -> [Bool] {
    precondition(validLen >= 0, "validLen must be non-negative")
    precondition(Int(validLen) <= covered.count, "validLen must not exceed covered.count")

    var unknown = Array(repeating: false, count: covered.count)
    for i in 0..<Int(validLen) {
      unknown[i] = !covered[i]
    }
    return unknown
  }

  /// Build error spans from maximal runs of unknown bytes.
  /// Emits half-open spans [start, endExclusive).
  public static func errorSpans(unknown: [Bool]) -> [ErrorSpan] {
    guard !unknown.isEmpty else { return [] }

    var spans: [ErrorSpan] = []
    spans.reserveCapacity(unknown.count / 2)

    var currentStart: Int? = nil

    for i in 0..<unknown.count {
      let isUnknown = unknown[i]
      let isStart = isUnknown && (i == 0 || !unknown[i - 1])
      let isEnd = isUnknown && (i == unknown.count - 1 || !unknown[i + 1])

      if isStart {
        currentStart = i
      }

      if isEnd, let start = currentStart {
        spans.append(ErrorSpan(start: Int32(start), end: Int32(i + 1)))
        currentStart = nil
      }
    }

    return spans
  }
}
