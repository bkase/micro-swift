import MicroSwiftTensorCore
import Testing

@Suite
struct GreedySelectorTests {
  @Test
  func selectsNonOverlappingWinnersInSourceOrder() {
    let winners = [
      winner(position: 0, len: 4, priorityRank: 0, ruleID: 10),
      winner(position: 1, len: 2, priorityRank: 0, ruleID: 11),
      winner(position: 3, len: 3, priorityRank: 0, ruleID: 12),
      winner(position: 4, len: 1, priorityRank: 0, ruleID: 13),
      winner(position: 6, len: 2, priorityRank: 0, ruleID: 14),
    ]

    let selected = greedyNonOverlapSelect(winners: winners, validLen: 8)

    #expect(selected == [
      winner(position: 0, len: 4, priorityRank: 0, ruleID: 10),
      winner(position: 4, len: 1, priorityRank: 0, ruleID: 13),
      winner(position: 6, len: 2, priorityRank: 0, ruleID: 14),
    ])
  }

  @Test
  func rejectsFallbackStartInsideAcceptedFastToken() {
    let fastWinners = [
      winner(position: 0, len: 3, priorityRank: 0, ruleID: 10),
      winner(position: 1, len: 0, priorityRank: 0, ruleID: 0),
      winner(position: 2, len: 0, priorityRank: 0, ruleID: 0),
      winner(position: 3, len: 2, priorityRank: 0, ruleID: 11),
      winner(position: 4, len: 0, priorityRank: 0, ruleID: 0),
    ]

    let fallbackResult = FallbackPageResult(
      fallbackLen: [2, 4, 2, 1, 1],
      fallbackPriorityRank: [2, 1, 1, 3, 0],
      fallbackRuleID: [80, 81, 82, 83, 84],
      fallbackTokenKindID: [8, 8, 8, 8, 8],
      fallbackMode: [0, 0, 0, 0, 0]
    )

    let integrated = integrateWithFallback(
      fastWinners: fastWinners,
      fallbackResult: fallbackResult,
      pageWidth: 5
    )
    let selected = greedyNonOverlapSelect(winners: integrated, validLen: 5)

    #expect(selected == [
      winner(position: 0, len: 3, priorityRank: 0, ruleID: 10),
      winner(position: 3, len: 2, priorityRank: 0, ruleID: 11),
    ])
  }

  private func winner(
    position: Int,
    len: UInt16,
    priorityRank: UInt16,
    ruleID: UInt16,
    tokenKindID: UInt16 = 1,
    mode: UInt8 = 0
  ) -> CandidateWinner {
    CandidateWinner(
      position: position,
      len: len,
      priorityRank: priorityRank,
      ruleID: ruleID,
      tokenKindID: tokenKindID,
      mode: mode
    )
  }
}
