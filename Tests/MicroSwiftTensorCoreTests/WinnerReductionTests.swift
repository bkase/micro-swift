import MicroSwiftTensorCore
import Testing

@Suite
struct WinnerReductionTests {
  @Test(.enabled(if: requiresMLXEval))
  func reduceAcrossLiteralRunAndFallbackBuckets() {
    let literalBucket = [
      winner(position: 0, len: 2, priorityRank: 3, ruleID: 20),
      winner(position: 1, len: 1, priorityRank: 2, ruleID: 30),
    ]
    let runBucket = [
      winner(position: 0, len: 3, priorityRank: 9, ruleID: 40),
      winner(position: 1, len: 1, priorityRank: 1, ruleID: 25),
    ]
    let fallbackBucket = [
      winner(position: 0, len: 3, priorityRank: 1, ruleID: 50),
      winner(position: 1, len: 1, priorityRank: 1, ruleID: 21),
      winner(position: 2, len: 4, priorityRank: 0, ruleID: 60),
    ]

    let reduced = reduceBucketWinners(
      buckets: [literalBucket, runBucket, fallbackBucket]
    )

    #expect(reduced.count == 3)
    #expect(reduced[0] == winner(position: 0, len: 3, priorityRank: 1, ruleID: 50))
    #expect(reduced[1] == winner(position: 1, len: 1, priorityRank: 1, ruleID: 21))
    #expect(reduced[2] == winner(position: 2, len: 4, priorityRank: 0, ruleID: 60))
  }

  @Test(.enabled(if: requiresMLXEval))
  func integrateFallbackIntoFastWinners() {
    let fastWinners = [
      winner(position: 0, len: 2, priorityRank: 0, ruleID: 10),
      winner(position: 1, len: 1, priorityRank: 5, ruleID: 11),
      winner(position: 2, len: 0, priorityRank: 0, ruleID: 0),
      winner(position: 3, len: 2, priorityRank: 2, ruleID: 99),
    ]

    let fallbackResult = FallbackPageResult(
      fallbackLen: [1, 3, 1, 2],
      fallbackPriorityRank: [0, 1, 0, 1],
      fallbackRuleID: [70, 71, 72, 50],
      fallbackTokenKindID: [7, 7, 7, 7],
      fallbackMode: [0, 0, 0, 1]
    )

    let integrated = integrateWithFallback(
      fastWinners: fastWinners,
      fallbackResult: fallbackResult,
      pageWidth: 4
    )

    #expect(integrated.count == 4)
    #expect(integrated[0] == winner(position: 0, len: 2, priorityRank: 0, ruleID: 10))
    #expect(
      integrated[1]
        == winner(
          position: 1,
          len: 3,
          priorityRank: 1,
          ruleID: 71,
          tokenKindID: 7
        ))
    #expect(
      integrated[2]
        == winner(
          position: 2,
          len: 1,
          priorityRank: 0,
          ruleID: 72,
          tokenKindID: 7
        ))
    #expect(
      integrated[3]
        == winner(
          position: 3,
          len: 2,
          priorityRank: 1,
          ruleID: 50,
          tokenKindID: 7,
          mode: 1
        ))
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
