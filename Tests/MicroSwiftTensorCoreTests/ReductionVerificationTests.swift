import Testing

@testable import MicroSwiftTensorCore

@Suite
struct ReductionVerificationTests {
  @Test(.enabled(if: requiresMLXEval))
  func winnerReductionIsDeterministicForSameInputs() {
    var rng = LCG(seed: 0xDEAD_BEEF)

    for _ in 0..<160 {
      let pageSize = rng.int(in: 0...32)
      let candidates = makeRandomCandidates(pageSize: pageSize, rng: &rng)

      let first = WinnerReduction.reduce(candidates: candidates, pageSize: pageSize)
      let second = WinnerReduction.reduce(candidates: candidates, pageSize: pageSize)

      #expect(first.count == second.count)
      for i in 0..<first.count {
        #expect(equalWinners(first[i], second[i]))
      }
    }
  }

  @Test(.enabled(if: requiresMLXEval))
  func comparatorTransitivityHoldsOnRandomTuples() {
    var rng = LCG(seed: 0xABCDEF)

    for _ in 0..<800 {
      let a = randomWinnerTuple(rng: &rng)
      let b = randomWinnerTuple(rng: &rng)
      let c = randomWinnerTuple(rng: &rng)

      if a.isBetterThan(b) && b.isBetterThan(c) {
        #expect(a.isBetterThan(c))
      }

      let cmpAB = totalOrder(a, b)
      let cmpBC = totalOrder(b, c)
      let cmpAC = totalOrder(a, c)
      if cmpAB <= 0 && cmpBC <= 0 {
        #expect(cmpAC <= 0)
      }
      if cmpAB >= 0 && cmpBC >= 0 {
        #expect(cmpAC >= 0)
      }
    }
  }

  @Test(.enabled(if: requiresMLXEval))
  func treeReductionMatchesSequentialReduction() {
    var rng = LCG(seed: 0x00C0_FFEE)

    for _ in 0..<170 {
      let pageSize = rng.int(in: 0...34)
      let candidates = makeRandomCandidates(pageSize: pageSize, rng: &rng)

      let tree = WinnerReduction.reduce(candidates: candidates, pageSize: pageSize)
      let sequential = sequentialReduce(candidates: candidates, pageSize: pageSize)

      #expect(tree.count == sequential.count)
      for i in 0..<tree.count {
        #expect(equalWinners(tree[i], sequential[i]))
      }
    }
  }
}

private struct LCG {
  private var state: UInt64

  init(seed: UInt64) {
    self.state = seed
  }

  mutating func next() -> UInt64 {
    state = state &* 6_364_136_223_846_793_005 &+ 1
    return state
  }

  mutating func int(in range: ClosedRange<Int>) -> Int {
    let width = range.upperBound - range.lowerBound + 1
    return range.lowerBound + Int(next() % UInt64(width))
  }

  mutating func bool() -> Bool {
    (next() & 1) == 1
  }
}

private func makeRandomCandidates(
  pageSize: Int,
  rng: inout LCG
) -> [WinnerReduction.RuleCandidate] {
  let count = rng.int(in: 0...14)
  return (0..<count).map { i in
    let candLen: [UInt16] = (0..<pageSize).map { _ in
      if rng.bool() {
        return UInt16(rng.int(in: 1...8))
      }
      return 0
    }

    return WinnerReduction.RuleCandidate(
      ruleID: UInt16(i),
      tokenKindID: UInt16(rng.int(in: 1...200)),
      priorityRank: UInt16(rng.int(in: 0...16)),
      mode: UInt8(rng.int(in: 0...2)),
      candLen: candLen
    )
  }
}

private func randomWinnerTuple(rng: inout LCG) -> WinnerTuple {
  let isEmpty = rng.bool() && rng.bool()
  if isEmpty {
    return .empty
  }

  return WinnerTuple(
    len: UInt16(rng.int(in: 1...12)),
    priorityRank: UInt16(rng.int(in: 0...24)),
    ruleID: UInt16(rng.int(in: 0...30)),
    tokenKindID: UInt16(rng.int(in: 0...255)),
    mode: UInt8(rng.int(in: 0...2))
  )
}

private func totalOrder(_ lhs: WinnerTuple, _ rhs: WinnerTuple) -> Int {
  if lhs.len != rhs.len {
    return lhs.len > rhs.len ? -1 : 1
  }
  if lhs.priorityRank != rhs.priorityRank {
    return lhs.priorityRank < rhs.priorityRank ? -1 : 1
  }
  if lhs.ruleID != rhs.ruleID {
    return lhs.ruleID < rhs.ruleID ? -1 : 1
  }
  return 0
}

private func sequentialReduce(
  candidates: [WinnerReduction.RuleCandidate],
  pageSize: Int
) -> [WinnerTuple] {
  var out = Array(repeating: WinnerTuple.empty, count: pageSize)

  for candidate in candidates {
    for index in 0..<pageSize {
      let len = candidate.candLen[index]
      guard len > 0 else { continue }

      let contender = WinnerTuple(
        len: len,
        priorityRank: candidate.priorityRank,
        ruleID: candidate.ruleID,
        tokenKindID: candidate.tokenKindID,
        mode: candidate.mode
      )

      if contender.isBetterThan(out[index]) {
        out[index] = contender
      }
    }
  }

  return out
}

private func equalWinners(_ lhs: WinnerTuple, _ rhs: WinnerTuple) -> Bool {
  lhs.len == rhs.len
    && lhs.priorityRank == rhs.priorityRank
    && lhs.ruleID == rhs.ruleID
    && lhs.tokenKindID == rhs.tokenKindID
    && lhs.mode == rhs.mode
}
