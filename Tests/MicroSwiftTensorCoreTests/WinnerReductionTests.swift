import Testing

@testable import MicroSwiftTensorCore

@Suite
struct WinnerReductionTests {
  @Test
  func singleRuleYieldsThatRuleAtMatchingPositions() {
    let candidate = WinnerReduction.RuleCandidate(
      ruleID: 7,
      tokenKindID: 17,
      priorityRank: 2,
      mode: 1,
      candLen: [0, 3, 1, 0]
    )

    let winners = WinnerReduction.reduce(candidates: [candidate], pageSize: 4)

    expectWinner(winners[0], len: 0, priorityRank: .max, ruleID: .max, tokenKindID: 0, mode: 0)
    expectWinner(winners[1], len: 3, priorityRank: 2, ruleID: 7, tokenKindID: 17, mode: 1)
    expectWinner(winners[2], len: 1, priorityRank: 2, ruleID: 7, tokenKindID: 17, mode: 1)
    expectWinner(winners[3], len: 0, priorityRank: .max, ruleID: .max, tokenKindID: 0, mode: 0)
  }

  @Test
  func longerCandidateWins() {
    let short = WinnerReduction.RuleCandidate(
      ruleID: 1,
      tokenKindID: 10,
      priorityRank: 0,
      mode: 0,
      candLen: [2, 1, 0]
    )
    let long = WinnerReduction.RuleCandidate(
      ruleID: 2,
      tokenKindID: 20,
      priorityRank: 3,
      mode: 0,
      candLen: [3, 4, 0]
    )

    let winners = WinnerReduction.reduce(candidates: [short, long], pageSize: 3)

    expectWinner(winners[0], len: 3, priorityRank: 3, ruleID: 2, tokenKindID: 20, mode: 0)
    expectWinner(winners[1], len: 4, priorityRank: 3, ruleID: 2, tokenKindID: 20, mode: 0)
    expectWinner(winners[2], len: 0, priorityRank: .max, ruleID: .max, tokenKindID: 0, mode: 0)
  }

  @Test
  func smallerPriorityWinsWhenLengthsTie() {
    let highPriorityRank = WinnerReduction.RuleCandidate(
      ruleID: 3,
      tokenKindID: 30,
      priorityRank: 5,
      mode: 0,
      candLen: [4]
    )
    let lowPriorityRank = WinnerReduction.RuleCandidate(
      ruleID: 4,
      tokenKindID: 40,
      priorityRank: 1,
      mode: 0,
      candLen: [4]
    )

    let winners = WinnerReduction.reduce(candidates: [highPriorityRank, lowPriorityRank], pageSize: 1)

    expectWinner(winners[0], len: 4, priorityRank: 1, ruleID: 4, tokenKindID: 40, mode: 0)
  }

  @Test
  func hierarchicalReductionAcrossMultipleRules() {
    let r1 = WinnerReduction.RuleCandidate(
      ruleID: 8,
      tokenKindID: 80,
      priorityRank: 3,
      mode: 0,
      candLen: [2, 0, 1, 0]
    )
    let r2 = WinnerReduction.RuleCandidate(
      ruleID: 6,
      tokenKindID: 60,
      priorityRank: 3,
      mode: 0,
      candLen: [2, 4, 0, 0]
    )
    let r3 = WinnerReduction.RuleCandidate(
      ruleID: 5,
      tokenKindID: 50,
      priorityRank: 2,
      mode: 1,
      candLen: [2, 4, 3, 0]
    )
    let r4 = WinnerReduction.RuleCandidate(
      ruleID: 4,
      tokenKindID: 40,
      priorityRank: 2,
      mode: 2,
      candLen: [2, 1, 5, 0]
    )

    let winners = WinnerReduction.reduce(candidates: [r1, r2, r3, r4], pageSize: 4)

    // Position 0: all len=2, priority tie between r3/r4, smaller ruleID (4) wins.
    expectWinner(winners[0], len: 2, priorityRank: 2, ruleID: 4, tokenKindID: 40, mode: 2)
    // Position 1: longest len=4 from r2/r3, smaller priorityRank from r3 wins.
    expectWinner(winners[1], len: 4, priorityRank: 2, ruleID: 5, tokenKindID: 50, mode: 1)
    // Position 2: longest len=5 from r4 wins.
    expectWinner(winners[2], len: 5, priorityRank: 2, ruleID: 4, tokenKindID: 40, mode: 2)
    // Position 3: no candidates.
    expectWinner(winners[3], len: 0, priorityRank: .max, ruleID: .max, tokenKindID: 0, mode: 0)
  }

  @Test
  func emptyCandidatesProduceEmptyWinners() {
    let winners = WinnerReduction.reduce(candidates: [], pageSize: 3)

    expectWinner(winners[0], len: 0, priorityRank: .max, ruleID: .max, tokenKindID: 0, mode: 0)
    expectWinner(winners[1], len: 0, priorityRank: .max, ruleID: .max, tokenKindID: 0, mode: 0)
    expectWinner(winners[2], len: 0, priorityRank: .max, ruleID: .max, tokenKindID: 0, mode: 0)
  }

  @Test
  func pairwiseMergeChoosesBetterElement() {
    let a: [WinnerTuple] = [
      WinnerTuple(len: 2, priorityRank: 2, ruleID: 5, tokenKindID: 50, mode: 0),
      WinnerTuple(len: 4, priorityRank: 7, ruleID: 9, tokenKindID: 90, mode: 0),
      .empty,
    ]
    let b: [WinnerTuple] = [
      WinnerTuple(len: 3, priorityRank: 9, ruleID: 1, tokenKindID: 10, mode: 1),
      WinnerTuple(len: 4, priorityRank: 1, ruleID: 10, tokenKindID: 100, mode: 1),
      WinnerTuple(len: 1, priorityRank: 0, ruleID: 2, tokenKindID: 20, mode: 2),
    ]

    let merged = WinnerReduction.pairwiseMerge(a, b)

    expectWinner(merged[0], len: 3, priorityRank: 9, ruleID: 1, tokenKindID: 10, mode: 1)
    expectWinner(merged[1], len: 4, priorityRank: 1, ruleID: 10, tokenKindID: 100, mode: 1)
    expectWinner(merged[2], len: 1, priorityRank: 0, ruleID: 2, tokenKindID: 20, mode: 2)
  }

  private func expectWinner(
    _ winner: WinnerTuple,
    len: UInt16,
    priorityRank: UInt16,
    ruleID: UInt16,
    tokenKindID: UInt16,
    mode: UInt8
  ) {
    #expect(winner.len == len)
    #expect(winner.priorityRank == priorityRank)
    #expect(winner.ruleID == ruleID)
    #expect(winner.tokenKindID == tokenKindID)
    #expect(winner.mode == mode)
  }
}
