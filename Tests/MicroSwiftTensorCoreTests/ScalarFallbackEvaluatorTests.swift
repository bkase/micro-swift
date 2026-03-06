import MicroSwiftTensorCore
@testable import MicroSwiftLexerGen
import Testing

@Suite
struct ScalarFallbackEvaluatorTests {
  private let evaluator = ScalarFallbackEvaluator()

  @Test
  func prefersLongestAcceptingMatchWithinRule() {
    let artifact = artifactWithRules([
      fallbackRule(
        ruleID: 10,
        tokenKindID: 3,
        priorityRank: 4,
        mode: .emit,
        acceptingStates: [1, 2],
        transitions: [
          1, 3, 3,
          3, 2, 3,
          3, 3, 3,
          3, 3, 3,
        ]
      )
    ])

    let winner = evaluator.evaluate(
      bytes: Array("abx".utf8),
      startPosition: 0,
      validLen: 3,
      byteToClass: byteToClassTable,
      artifact: artifact
    )

    #expect(
      winner == FallbackWinner(
        len: 2,
        priorityRank: 4,
        ruleID: 10,
        tokenKindID: 3,
        mode: 0
      ))
  }

  @Test
  func breaksTiesByPriorityThenRuleID() {
    let artifact = artifactWithRules([
      fallbackRule(
        ruleID: 9,
        tokenKindID: 11,
        priorityRank: 2,
        mode: .emit,
        acceptingStates: [2],
        transitions: abOnlyTransitions
      ),
      fallbackRule(
        ruleID: 4,
        tokenKindID: 12,
        priorityRank: 1,
        mode: .skip,
        acceptingStates: [2],
        transitions: abOnlyTransitions
      ),
      fallbackRule(
        ruleID: 3,
        tokenKindID: 13,
        priorityRank: 1,
        mode: .emit,
        acceptingStates: [2],
        transitions: abOnlyTransitions
      ),
    ])

    let winner = evaluator.evaluate(
      bytes: Array("ab".utf8),
      startPosition: 0,
      validLen: 2,
      byteToClass: byteToClassTable,
      artifact: artifact
    )

    #expect(
      winner == FallbackWinner(
        len: 2,
        priorityRank: 1,
        ruleID: 3,
        tokenKindID: 13,
        mode: 0
      ))
  }

  @Test
  func returnsNoMatchWhenStartOutsideValidWindow() {
    let artifact = artifactWithRules([
      fallbackRule(
        ruleID: 5,
        tokenKindID: 6,
        priorityRank: 0,
        mode: .emit,
        acceptingStates: [2],
        transitions: abOnlyTransitions
      )
    ])

    let winner = evaluator.evaluate(
      bytes: Array("ab".utf8),
      startPosition: 2,
      validLen: 2,
      byteToClass: byteToClassTable,
      artifact: artifact
    )

    #expect(winner == .noMatch)
  }

  private static let abOnlyTransitions: [UInt32] = [
    1, 3, 3,
    3, 2, 3,
    3, 3, 3,
    3, 3, 3,
  ]

  private var abOnlyTransitions: [UInt32] {
    Self.abOnlyTransitions
  }

  private func fallbackRule(
    ruleID: UInt16,
    tokenKindID: UInt16,
    priorityRank: UInt16,
    mode: RuleMode,
    acceptingStates: [UInt32],
    transitions: [UInt32]
  ) -> LoweredRule {
    LoweredRule(
      ruleID: ruleID,
      name: "r\(ruleID)",
      tokenKindID: tokenKindID,
      mode: mode,
      family: .fallback,
      priorityRank: priorityRank,
      minWidth: 1,
      maxWidth: 8,
      firstClassSetID: 0,
      plan: .fallback(
        stateCount: 4,
        classCount: 3,
        transitionRowStride: 3,
        startState: 0,
        acceptingStates: acceptingStates,
        transitions: transitions
      )
    )
  }

  private func artifactWithRules(_ rules: [LoweredRule]) -> LexerArtifact {
    LexerArtifact(
      formatVersion: 1,
      specName: "fixture",
      specHashHex: "00",
      generatorVersion: "test",
      runtimeHints: RuntimeHints(
        maxLiteralLength: 0,
        maxBoundedRuleWidth: 8,
        maxDeterministicLookaheadBytes: 0
      ),
      tokenKinds: [],
      byteToClass: byteToClassTable,
      classes: [],
      classSets: [],
      rules: rules,
      keywordRemaps: []
    )
  }

  private var byteToClassTable: [UInt8] {
    Self.byteToClassTable
  }

  private static let byteToClassTable: [UInt8] = {
    var table = Array(repeating: UInt8(2), count: 256)
    table[Int(Character("a").asciiValue!)] = 0
    table[Int(Character("b").asciiValue!)] = 1
    return table
  }()
}
