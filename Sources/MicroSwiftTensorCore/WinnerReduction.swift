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
