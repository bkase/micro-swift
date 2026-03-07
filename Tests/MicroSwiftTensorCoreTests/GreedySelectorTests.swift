import MLX
import MicroSwiftTensorCore
import Testing

@Suite
struct GreedySelectorTests {

  // MARK: - Differential tests: host vs tensor greedy selector

  @Test(.enabled(if: requiresMLXEval))
  func differentialPlanExample1() {
    // len=[2,7,2,7,2,7,2,1] → selects {0,2,4,6}
    let lens: [UInt16] = [2, 7, 2, 7, 2, 7, 2, 1]
    assertHostTensorMatch(lens: lens)
  }

  @Test(.enabled(if: requiresMLXEval))
  func differentialPlanExample2() {
    // len=[4,2,0,3,1,0,2,0] → selects {0,4,6}
    let lens: [UInt16] = [4, 2, 0, 3, 1, 0, 2, 0]
    assertHostTensorMatch(lens: lens)
  }

  @Test(.enabled(if: requiresMLXEval))
  func differentialAllLen1() {
    // Pathological: every position has len=1, all selected
    let lens: [UInt16] = Array(repeating: 1, count: 64)
    assertHostTensorMatch(lens: lens)
  }

  @Test(.enabled(if: requiresMLXEval))
  func differentialDenseOverlap() {
    // Every position has len=N, only position 0 selected
    let n = 32
    let lens: [UInt16] = Array(repeating: UInt16(n), count: n)
    assertHostTensorMatch(lens: lens)
  }

  @Test(.enabled(if: requiresMLXEval))
  func differentialSingleCandidate() {
    let lens: [UInt16] = [0, 0, 3, 0, 0, 0, 0, 0]
    assertHostTensorMatch(lens: lens)
  }

  @Test(.enabled(if: requiresMLXEval))
  func differentialNoCandidates() {
    let lens: [UInt16] = Array(repeating: 0, count: 16)
    assertHostTensorMatch(lens: lens)
  }

  @Test(.enabled(if: requiresMLXEval))
  func differentialPartialValid() {
    // Only first 4 of 8 positions are valid
    let lens: [UInt16] = [2, 1, 3, 1, 2, 1, 3, 1]
    assertHostTensorMatch(lens: lens, validLen: 4)
  }

  // MARK: - Differential helper

  private func assertHostTensorMatch(
    lens: [UInt16],
    validLen: Int32? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let pageSize = lens.count
    let vl = validLen ?? Int32(pageSize)

    // Build WinnerTuples with distinct ruleIDs
    let winners = lens.enumerated().map { i, len in
      WinnerTuple(
        len: len, priorityRank: 0, ruleID: UInt16(i + 1),
        tokenKindID: UInt16(i + 10), mode: 0
      )
    }

    // Host reference
    let hostResult = GreedySelector.select(winners: winners, validLen: vl)

    // Tensor path
    let winnerTensors = WinnerReduction.WinnerTensors(
      len: MLXArray(lens.map { Int32($0) }),
      priorityRank: MLXArray(Array(repeating: Int32(0), count: pageSize)),
      ruleID: MLXArray((0..<pageSize).map { Int32($0 + 1) }),
      tokenKindID: MLXArray((0..<pageSize).map { Int32($0 + 10) }),
      mode: MLXArray(Array(repeating: Int32(0), count: pageSize))
    )
    let tensorResult = GreedySelector.select(winnerTensors: winnerTensors, validLen: vl)
    eval(tensorResult.selectedMask)

    // Extract selected positions from tensor result
    let maskArr = tensorResult.selectedMask.asArray(Bool.self)
    let startPosArr = tensorResult.startPos.asArray(Int32.self)
    let lenArr = tensorResult.length.asArray(UInt16.self)
    let ruleArr = tensorResult.ruleID.asArray(UInt16.self)

    var tensorSelected: [GreedySelector.SelectedToken] = []
    for i in 0..<pageSize where maskArr[i] {
      tensorSelected.append(
        GreedySelector.SelectedToken(
          startPos: startPosArr[i], length: lenArr[i], ruleID: ruleArr[i],
          tokenKindID: tensorResult.tokenKindID.asArray(UInt16.self)[i],
          mode: tensorResult.mode.asArray(UInt8.self)[i]
        )
      )
    }

    #expect(tensorSelected == hostResult, sourceLocation: sourceLocation)
  }

  // MARK: - Original tests
  @Test(.enabled(if: requiresMLXEval))
  func selectsNonOverlappingWinnersInSourceOrder() {
    let winners = [
      winner(position: 0, len: 4, priorityRank: 0, ruleID: 10),
      winner(position: 1, len: 2, priorityRank: 0, ruleID: 11),
      winner(position: 3, len: 3, priorityRank: 0, ruleID: 12),
      winner(position: 4, len: 1, priorityRank: 0, ruleID: 13),
      winner(position: 6, len: 2, priorityRank: 0, ruleID: 14),
    ]

    let selected = greedyNonOverlapSelect(winners: winners, validLen: 8)

    #expect(
      selected == [
        winner(position: 0, len: 4, priorityRank: 0, ruleID: 10),
        winner(position: 4, len: 1, priorityRank: 0, ruleID: 13),
        winner(position: 6, len: 2, priorityRank: 0, ruleID: 14),
      ])
  }

  @Test(.enabled(if: requiresMLXEval))
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

    #expect(
      selected == [
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
