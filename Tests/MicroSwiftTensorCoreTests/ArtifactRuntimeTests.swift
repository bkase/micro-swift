import Testing

@testable import MicroSwiftLexerGen
@testable import MicroSwiftTensorCore

@Suite struct ArtifactRuntimeTests {
  @Test func packsFallbackTablesAndMetadata() throws {
    let artifact = makeArtifact(
      rules: [
        makeFallbackRule(
          ruleID: 7,
          tokenKindID: 11,
          priorityRank: 3,
          mode: .emit,
          maxWidth: 6,
          classCount: 4,
          startState: 1,
          acceptingStates: [2],
          transitions: [
            0, 0, 0, 0,
            2, 0, 0, 0,
            2, 2, 0, 0,
          ]
        )
      ]
    )

    let runtime = try ArtifactRuntime.fromArtifact(artifact)
    let fallback = try #require(runtime.fallback)

    #expect(fallback.numStatesUsed == 3)
    #expect(fallback.maxWidth == 6)
    #expect(fallback.startMaskLo == (1 << 1))
    #expect(fallback.startMaskHi == 0)
    #expect(fallback.startClassMaskLo == 1)
    #expect(fallback.startClassMaskHi == 0)

    #expect(fallback.acceptLoByRule == [1 << 2])
    #expect(fallback.acceptHiByRule == [0])
    #expect(fallback.globalRuleIDByFallbackRule == [7])
    #expect(fallback.priorityRankByFallbackRule == [3])
    #expect(fallback.tokenKindIDByFallbackRule == [11])
    #expect(fallback.modeByFallbackRule == [0])

    let numStates = Int(fallback.numStatesUsed)
    #expect(fallback.stepLo[(0 * numStates) + 1] == (1 << 2))
    #expect(fallback.stepLo[(0 * numStates) + 2] == (1 << 2))
    #expect(fallback.stepLo[(1 * numStates) + 2] == (1 << 2))
    #expect(fallback.stepLo[(1 * numStates) + 1] == 0)
    #expect(fallback.stepHi.allSatisfy { $0 == 0 })
  }

  @Test func combinesStartMasksAcrossFallbackRules() throws {
    let artifact = makeArtifact(
      rules: [
        makeFallbackRule(
          ruleID: 7,
          tokenKindID: 11,
          priorityRank: 3,
          mode: .emit,
          maxWidth: 6,
          classCount: 4,
          startState: 1,
          acceptingStates: [2],
          transitions: [
            0, 0, 0, 0,
            2, 0, 0, 0,
            2, 0, 0, 0,
          ]
        ),
        makeFallbackRule(
          ruleID: 9,
          tokenKindID: 5,
          priorityRank: 1,
          mode: .skip,
          maxWidth: 4,
          classCount: 4,
          startState: 1,
          acceptingStates: [2],
          transitions: [
            0, 0, 0, 0,
            0, 0, 2, 0,
            0, 0, 2, 0,
          ]
        ),
      ]
    )

    let runtime = try ArtifactRuntime.fromArtifact(artifact)
    let fallback = try #require(runtime.fallback)

    #expect(fallback.numStatesUsed == 6)
    #expect(fallback.maxWidth == 6)
    #expect(fallback.startMaskLo == ((1 << 1) | (1 << 4)))
    #expect(fallback.startMaskHi == 0)
    #expect(fallback.startClassMaskLo == ((1 << 0) | (1 << 2)))

    #expect(fallback.acceptLoByRule == [(1 << 2), (1 << 5)])
    #expect(fallback.acceptHiByRule == [0, 0])
    #expect(fallback.globalRuleIDByFallbackRule == [7, 9])
    #expect(fallback.priorityRankByFallbackRule == [3, 1])
    #expect(fallback.tokenKindIDByFallbackRule == [11, 5])
    #expect(fallback.modeByFallbackRule == [0, 1])
  }

  @Test func rejectsCombinedFallbackStatesOver128() {
    let artifact = makeArtifact(
      rules: [
        makeFallbackRule(
          ruleID: 100,
          tokenKindID: 1,
          priorityRank: 0,
          mode: .emit,
          maxWidth: 4,
          stateCount: 80,
          classCount: 1,
          startState: 1,
          acceptingStates: [2],
          transitions: Array(repeating: 0, count: 80)
        ),
        makeFallbackRule(
          ruleID: 101,
          tokenKindID: 1,
          priorityRank: 0,
          mode: .emit,
          maxWidth: 4,
          stateCount: 60,
          classCount: 1,
          startState: 1,
          acceptingStates: [2],
          transitions: Array(repeating: 0, count: 60)
        ),
      ]
    )

    #expect(throws: ArtifactRuntimeError.fallbackStateCapExceeded(totalStates: 140)) {
      _ = try ArtifactRuntime.fromArtifact(artifact)
    }
  }
}

private func makeArtifact(rules: [LoweredRule]) -> LexerArtifact {
  let classCount = rules.reduce(into: UInt16(1)) { partial, rule in
    if case .fallback(_, let count, _, _, _, _) = rule.plan {
      partial = max(partial, count)
    }
  }
  let classes = (0..<Int(classCount)).map { classID in
    ByteClassDecl(classID: UInt8(classID), bytes: [UInt8(classID)])
  }

  return LexerArtifact(
    formatVersion: 1,
    specName: "runtime-tests",
    specHashHex: String(repeating: "0", count: 64),
    generatorVersion: "tests",
    runtimeHints: RuntimeHints(
      maxLiteralLength: 0,
      maxBoundedRuleWidth: 16,
      maxDeterministicLookaheadBytes: 16
    ),
    tokenKinds: [
      TokenKindDecl(tokenKindID: 1, name: "tok1", defaultMode: .emit),
      TokenKindDecl(tokenKindID: 5, name: "tok5", defaultMode: .emit),
      TokenKindDecl(tokenKindID: 11, name: "tok11", defaultMode: .emit),
    ],
    byteToClass: Array(repeating: 0, count: 256),
    classes: classes,
    classSets: [ClassSetDecl(classSetID: ClassSetID(0), classes: [0])],
    rules: rules,
    keywordRemaps: []
  )
}

private func makeFallbackRule(
  ruleID: UInt16,
  tokenKindID: UInt16,
  priorityRank: UInt16,
  mode: RuleMode,
  maxWidth: UInt16,
  stateCount: UInt32 = 3,
  classCount: UInt16,
  startState: UInt32,
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
    maxWidth: maxWidth,
    firstClassSetID: 0,
    plan: .fallback(
      stateCount: stateCount,
      classCount: classCount,
      transitionRowStride: classCount,
      startState: startState,
      acceptingStates: acceptingStates,
      transitions: transitions
    )
  )
}
