import MicroSwiftLexerGen

public enum WinnerReduction {
  /// Candidate from a single rule at all positions.
  public struct RuleCandidate {
    public let ruleID: UInt16
    public let tokenKindID: UInt16
    public let priorityRank: UInt16
    public let mode: UInt8
    public let candLen: [UInt16]

    public init(
      ruleID: UInt16,
      tokenKindID: UInt16,
      priorityRank: UInt16,
      mode: UInt8,
      candLen: [UInt16]
    ) {
      self.ruleID = ruleID
      self.tokenKindID = tokenKindID
      self.priorityRank = priorityRank
      self.mode = mode
      self.candLen = candLen
    }
  }

  /// Reduce multiple rule candidates to one winner per position.
  /// Uses hierarchical pairwise tree merge with the lexicographic comparator:
  ///   1. longer length wins
  ///   2. smaller priorityRank wins
  ///   3. smaller ruleID wins
  public static func reduce(candidates: [RuleCandidate], pageSize: Int) -> [WinnerTuple] {
    precondition(pageSize >= 0, "pageSize must be non-negative")

    if candidates.isEmpty {
      return Array(repeating: .empty, count: pageSize)
    }

    var levels = candidates.map { candidate -> [WinnerTuple] in
      precondition(
        candidate.candLen.count == pageSize,
        "RuleCandidate candLen count must equal pageSize"
      )

      return candidate.candLen.map { len in
        if len == 0 {
          return .empty
        }

        return WinnerTuple(
          len: len,
          priorityRank: candidate.priorityRank,
          ruleID: candidate.ruleID,
          tokenKindID: candidate.tokenKindID,
          mode: candidate.mode
        )
      }
    }

    while levels.count > 1 {
      var nextLevel: [[WinnerTuple]] = []
      nextLevel.reserveCapacity((levels.count + 1) / 2)

      var index = 0
      while index < levels.count {
        let left = levels[index]
        if index + 1 < levels.count {
          let right = levels[index + 1]
          nextLevel.append(pairwiseMerge(left, right))
        } else {
          nextLevel.append(left)
        }
        index += 2
      }

      levels = nextLevel
    }

    return levels[0]
  }

  /// Pairwise merge two winner arrays element-wise.
  public static func pairwiseMerge(_ a: [WinnerTuple], _ b: [WinnerTuple]) -> [WinnerTuple] {
    precondition(a.count == b.count, "Winner arrays must have equal length")

    var merged: [WinnerTuple] = []
    merged.reserveCapacity(a.count)

    for index in a.indices {
      let lhs = a[index]
      let rhs = b[index]
      merged.append(rhs.isBetterThan(lhs) ? rhs : lhs)
    }

    return merged
  }
}

public struct CandidateWinner: Sendable, Equatable {
  public let position: Int
  public let len: UInt16
  public let priorityRank: UInt16
  public let ruleID: UInt16
  public let tokenKindID: UInt16
  public let mode: UInt8

  public init(
    position: Int,
    len: UInt16,
    priorityRank: UInt16,
    ruleID: UInt16,
    tokenKindID: UInt16,
    mode: UInt8
  ) {
    self.position = position
    self.len = len
    self.priorityRank = priorityRank
    self.ruleID = ruleID
    self.tokenKindID = tokenKindID
    self.mode = mode
  }

  public static func noMatch(at position: Int) -> CandidateWinner {
    CandidateWinner(
      position: position,
      len: 0,
      priorityRank: 0,
      ruleID: 0,
      tokenKindID: 0,
      mode: 0
    )
  }
}

public func reduceBucketWinners(buckets: [[CandidateWinner]]) -> [CandidateWinner] {
  let maxPosition =
    buckets
    .flatMap(\.self)
    .map(\.position)
    .max() ?? -1

  guard maxPosition >= 0 else { return [] }

  var reduced = (0...maxPosition).map(CandidateWinner.noMatch(at:))

  for bucket in buckets {
    for candidate in bucket where candidate.position >= 0 && candidate.position <= maxPosition {
      if isBetterCandidate(candidate, than: reduced[candidate.position]) {
        reduced[candidate.position] = candidate
      }
    }
  }

  return reduced
}

public func integrateWithFallback(
  fastWinners: [WinnerTuple],
  fallbackResult: FallbackPageResult,
  pageWidth: Int
) -> [WinnerTuple] {
  guard pageWidth > 0 else { return [] }

  var integrated = normalizedWinners(fastWinners, pageWidth: pageWidth)
  for position in 0..<pageWidth {
    let fallback = WinnerTuple(
      len: value(at: position, in: fallbackResult.fallbackLen),
      priorityRank: value(at: position, in: fallbackResult.fallbackPriorityRank),
      ruleID: value(at: position, in: fallbackResult.fallbackRuleID),
      tokenKindID: value(at: position, in: fallbackResult.fallbackTokenKindID),
      mode: value(at: position, in: fallbackResult.fallbackMode)
    )

    if fallback.isBetterThan(integrated[position]) {
      integrated[position] = fallback
    }
  }

  return integrated
}

public func integrateWithFallback(
  fastWinners: [CandidateWinner],
  fallbackResult: FallbackPageResult,
  pageWidth: Int
) -> [CandidateWinner] {
  let integrated = integrateWithFallback(
    fastWinners: normalizedWinners(fastWinners, pageWidth: pageWidth).map(asWinnerTuple),
    fallbackResult: fallbackResult,
    pageWidth: pageWidth
  )

  return integrated.enumerated().map { position, winner in
    candidateWinner(from: winner, position: position)
  }
}

private func normalizedWinners(_ winners: [WinnerTuple], pageWidth: Int) -> [WinnerTuple] {
  guard pageWidth > 0 else { return [] }
  guard winners.count != pageWidth else { return winners }

  var normalized = Array(repeating: WinnerTuple.empty, count: pageWidth)
  for (position, winner) in winners.enumerated() where position < pageWidth {
    normalized[position] = winner
  }
  return normalized
}

private func normalizedWinners(_ winners: [CandidateWinner], pageWidth: Int) -> [CandidateWinner] {
  guard pageWidth > 0 else { return [] }

  var normalized = (0..<pageWidth).map(CandidateWinner.noMatch(at:))
  for winner in winners where winner.position >= 0 && winner.position < pageWidth {
    if isBetterCandidate(winner, than: normalized[winner.position]) {
      normalized[winner.position] = winner
    }
  }
  return normalized
}

private func value<T>(at index: Int, in values: [T], default defaultValue: T) -> T {
  guard index >= 0, index < values.count else { return defaultValue }
  return values[index]
}

private func value(at index: Int, in values: [UInt16]) -> UInt16 {
  value(at: index, in: values, default: 0)
}

private func value(at index: Int, in values: [UInt8]) -> UInt8 {
  value(at: index, in: values, default: 0)
}

private func isBetterCandidate(_ lhs: CandidateWinner, than rhs: CandidateWinner) -> Bool {
  if lhs.len != rhs.len { return lhs.len > rhs.len }
  if lhs.len == 0 { return false }
  if lhs.priorityRank != rhs.priorityRank { return lhs.priorityRank < rhs.priorityRank }
  return lhs.ruleID < rhs.ruleID
}

private func asWinnerTuple(_ candidate: CandidateWinner) -> WinnerTuple {
  if candidate.len == 0 {
    return .empty
  }

  return WinnerTuple(
    len: candidate.len,
    priorityRank: candidate.priorityRank,
    ruleID: candidate.ruleID,
    tokenKindID: candidate.tokenKindID,
    mode: candidate.mode
  )
}

func candidateWinner(from winner: WinnerTuple, position: Int) -> CandidateWinner {
  CandidateWinner(
    position: position,
    len: winner.len,
    priorityRank: winner.len == 0 ? 0 : winner.priorityRank,
    ruleID: winner.len == 0 ? 0 : winner.ruleID,
    tokenKindID: winner.len == 0 ? 0 : winner.tokenKindID,
    mode: winner.len == 0 ? 0 : winner.mode
  )
}
