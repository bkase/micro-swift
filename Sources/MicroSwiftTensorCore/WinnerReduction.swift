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
  fastWinners: [CandidateWinner],
  fallbackResult: FallbackPageResult,
  pageWidth: Int
) -> [CandidateWinner] {
  guard pageWidth > 0 else { return [] }

  var fallbackWinners: [CandidateWinner] = []
  fallbackWinners.reserveCapacity(pageWidth)

  for position in 0..<pageWidth {
    let len = value(at: position, in: fallbackResult.fallbackLen)
    fallbackWinners.append(
      CandidateWinner(
        position: position,
        len: len,
        priorityRank: value(at: position, in: fallbackResult.fallbackPriorityRank),
        ruleID: value(at: position, in: fallbackResult.fallbackRuleID),
        tokenKindID: value(at: position, in: fallbackResult.fallbackTokenKindID),
        mode: value(at: position, in: fallbackResult.fallbackMode)
      ))
  }

  return reduceBucketWinners(
    buckets: [
      normalizedWinners(fastWinners, pageWidth: pageWidth),
      fallbackWinners,
    ])
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
