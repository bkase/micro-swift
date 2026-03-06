import Testing

@testable import MicroSwiftTensorCore

@Suite
struct GreedySelectorTests {
  @Test
  func simpleNonOverlappingTokensSelected() {
    let winners: [WinnerTuple] = [
      w(len: 2, ruleID: 10, tokenKindID: 100, mode: 1),
      .empty,
      w(len: 1, ruleID: 11, tokenKindID: 101, mode: 1),
      .empty,
      w(len: 3, ruleID: 12, tokenKindID: 102, mode: 2),
      .empty,
      .empty,
    ]

    let selected = GreedySelector.select(winners: winners, validLen: 7)

    #expect(selected == [
      .init(startPos: 0, length: 2, ruleID: 10, tokenKindID: 100, mode: 1),
      .init(startPos: 2, length: 1, ruleID: 11, tokenKindID: 101, mode: 1),
      .init(startPos: 4, length: 3, ruleID: 12, tokenKindID: 102, mode: 2),
    ])
  }

  @Test
  func tripleEqualsWithDoubleAndSingleEquals() {
    // "===" with winners from rules "==" and "=".
    let winners: [WinnerTuple] = [
      w(len: 2, ruleID: 20, tokenKindID: 200),
      w(len: 2, ruleID: 20, tokenKindID: 200),
      w(len: 1, ruleID: 21, tokenKindID: 201),
    ]

    let selected = GreedySelector.select(winners: winners, validLen: 3)

    #expect(selected == [
      .init(startPos: 0, length: 2, ruleID: 20, tokenKindID: 200, mode: 0),
      .init(startPos: 2, length: 1, ruleID: 21, tokenKindID: 201, mode: 0),
    ])
  }

  @Test
  func overlapCaseTripleEqualsArrow() {
    // "===>": accept at 0, reject overlapping starts 1 and 2, then accept at 3.
    let winners: [WinnerTuple] = [
      w(len: 3, ruleID: 30, tokenKindID: 300),
      w(len: 3, ruleID: 31, tokenKindID: 301),
      w(len: 2, ruleID: 32, tokenKindID: 302),
      w(len: 1, ruleID: 33, tokenKindID: 303),
    ]

    let selected = GreedySelector.select(winners: winners, validLen: 4)

    #expect(selected == [
      .init(startPos: 0, length: 3, ruleID: 30, tokenKindID: 300, mode: 0),
      .init(startPos: 3, length: 1, ruleID: 33, tokenKindID: 303, mode: 0),
    ])
  }

  @Test
  func overlapCaseFourDashesArrow() {
    // "---->": accept at 0, reject overlapping starts 1..3, then accept at 4.
    let winners: [WinnerTuple] = [
      w(len: 4, ruleID: 40, tokenKindID: 400),
      w(len: 4, ruleID: 41, tokenKindID: 401),
      w(len: 3, ruleID: 42, tokenKindID: 402),
      w(len: 2, ruleID: 43, tokenKindID: 403),
      w(len: 1, ruleID: 44, tokenKindID: 404),
    ]

    let selected = GreedySelector.select(winners: winners, validLen: 5)

    #expect(selected == [
      .init(startPos: 0, length: 4, ruleID: 40, tokenKindID: 400, mode: 0),
      .init(startPos: 4, length: 1, ruleID: 44, tokenKindID: 404, mode: 0),
    ])
  }

  @Test
  func noWinnersReturnsEmptySelection() {
    let winners = Array(repeating: WinnerTuple.empty, count: 6)

    let selected = GreedySelector.select(winners: winners, validLen: 6)

    #expect(selected.isEmpty)
  }

  @Test
  func adjacentTokensWithNoGapAreAccepted() {
    let winners: [WinnerTuple] = [
      w(len: 2, ruleID: 50, tokenKindID: 500),
      .empty,
      w(len: 2, ruleID: 51, tokenKindID: 501),
      .empty,
    ]

    let selected = GreedySelector.select(winners: winners, validLen: 4)

    #expect(selected == [
      .init(startPos: 0, length: 2, ruleID: 50, tokenKindID: 500, mode: 0),
      .init(startPos: 2, length: 2, ruleID: 51, tokenKindID: 501, mode: 0),
    ])
  }

  @Test
  func laterValidTokenAcceptedAfterInternalRejectedCandidate() {
    // Accept at 0 with len=3, reject candidate at 1, still accept at 3.
    let winners: [WinnerTuple] = [
      w(len: 3, ruleID: 60, tokenKindID: 600),
      w(len: 5, ruleID: 61, tokenKindID: 601),
      .empty,
      w(len: 2, ruleID: 62, tokenKindID: 602),
      .empty,
    ]

    let selected = GreedySelector.select(winners: winners, validLen: 5)

    #expect(selected == [
      .init(startPos: 0, length: 3, ruleID: 60, tokenKindID: 600, mode: 0),
      .init(startPos: 3, length: 2, ruleID: 62, tokenKindID: 602, mode: 0),
    ])
  }

  private func w(len: UInt16, ruleID: UInt16, tokenKindID: UInt16, mode: UInt8 = 0) -> WinnerTuple {
    WinnerTuple(len: len, priorityRank: 0, ruleID: ruleID, tokenKindID: tokenKindID, mode: mode)
  }
}
