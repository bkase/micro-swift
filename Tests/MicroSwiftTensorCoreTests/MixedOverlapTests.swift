import MicroSwiftTensorCore
import Testing

@testable import MicroSwiftLexerGen

@Suite
struct MixedOverlapTests {
  @Test(.enabled(if: requiresMLXEval))
  func fastLiteralVsFallbackOverlapPrefersFastLiteral() throws {
    let artifact = makeBoundedFallbackArtifact(
      FallbackFixtures.overlappingFastFallback(),
      fallbackMaxWidth: 4
    )
    let bytes = Array("if".utf8)
    let validLen = bytes.count

    let fallbackResult = try evaluateFallback(bytes: bytes, validLen: validLen, artifact: artifact)
    assertMatchesScalar(
      bytes: bytes,
      validLen: validLen,
      artifact: artifact,
      result: fallbackResult
    )

    let fastWinners = [winner(position: 0, len: 2, priorityRank: 0, ruleID: 0, tokenKindID: 0)]
    let selected = selectMixed(
      fastWinners: fastWinners, fallbackResult: fallbackResult, validLen: validLen)

    #expect(selected == [winner(position: 0, len: 2, priorityRank: 0, ruleID: 0, tokenKindID: 0)])
  }

  @Test(.enabled(if: requiresMLXEval))
  func fastRunVsFallbackOverlapPrefersFastRun() throws {
    let artifact = makeBoundedFallbackArtifact(
      FallbackFixtures.multiRuleFallbackWithPriority(),
      fallbackMaxWidth: 2
    )
    let bytes = Array("123".utf8)
    let validLen = bytes.count

    let fallbackResult = try evaluateFallback(bytes: bytes, validLen: validLen, artifact: artifact)
    assertMatchesScalar(
      bytes: bytes,
      validLen: validLen,
      artifact: artifact,
      result: fallbackResult
    )

    let fastWinners = [winner(position: 0, len: 3, priorityRank: 0, ruleID: 200, tokenKindID: 3)]
    let selected = selectMixed(
      fastWinners: fastWinners, fallbackResult: fallbackResult, validLen: validLen)

    #expect(selected == [winner(position: 0, len: 3, priorityRank: 0, ruleID: 200, tokenKindID: 3)])
  }

  @Test(.enabled(if: requiresMLXEval))
  func laterValidTokenAfterInternalRejectedFallbackStart() throws {
    let artifact = makeBoundedFallbackArtifact(
      FallbackFixtures.multiRuleFallbackWithPriority(),
      fallbackMaxWidth: 2
    )
    let bytes = Array("123ab".utf8)
    let validLen = bytes.count

    let fallbackResult = try evaluateFallback(bytes: bytes, validLen: validLen, artifact: artifact)
    assertMatchesScalar(
      bytes: bytes,
      validLen: validLen,
      artifact: artifact,
      result: fallbackResult
    )
    #expect(fallbackResult.fallbackLen[1] == 2)
    #expect(fallbackResult.fallbackLen[3] == 2)

    let fastWinners = [winner(position: 0, len: 3, priorityRank: 0, ruleID: 201, tokenKindID: 3)]
    let integrated = integrateWithFallback(
      fastWinners: fastWinners,
      fallbackResult: fallbackResult,
      pageWidth: validLen
    )
    let selected = greedyNonOverlapSelect(winners: integrated, validLen: validLen)

    #expect(
      selected
        == [
          winner(position: 0, len: 3, priorityRank: 0, ruleID: 201, tokenKindID: 3),
          winner(position: 3, len: 2, priorityRank: 5, ruleID: 1, tokenKindID: 2),
        ])
  }

  @Test(.enabled(if: requiresMLXEval))
  func fallbackCandidatesStartingInsideAcceptedFastTokenAreRejected() throws {
    let artifact = makeBoundedFallbackArtifact(
      FallbackFixtures.overlappingFastFallback(),
      fallbackMaxWidth: 2
    )
    let bytes = Array("ifab".utf8)
    let validLen = bytes.count

    let fallbackResult = try evaluateFallback(bytes: bytes, validLen: validLen, artifact: artifact)
    assertMatchesScalar(
      bytes: bytes,
      validLen: validLen,
      artifact: artifact,
      result: fallbackResult
    )
    #expect(fallbackResult.fallbackLen[1] == 2)

    let fastWinners = [winner(position: 0, len: 2, priorityRank: 0, ruleID: 0, tokenKindID: 0)]
    let selected = selectMixed(
      fastWinners: fastWinners, fallbackResult: fallbackResult, validLen: validLen)

    #expect(
      selected
        == [
          winner(position: 0, len: 2, priorityRank: 0, ruleID: 0, tokenKindID: 0),
          winner(position: 2, len: 2, priorityRank: 10, ruleID: 1, tokenKindID: 1),
        ])
  }

  @Test(.enabled(if: requiresMLXEval))
  func fallbackCandidateThatWouldWinAtStartStillRejectedByCoverage() throws {
    let artifact = makeBoundedFallbackArtifact(
      FallbackFixtures.multiRuleFallbackWithPriority(),
      fallbackMaxWidth: 2
    )
    let bytes = Array("1234ab".utf8)
    let validLen = bytes.count

    let fallbackResult = try evaluateFallback(bytes: bytes, validLen: validLen, artifact: artifact)
    assertMatchesScalar(
      bytes: bytes,
      validLen: validLen,
      artifact: artifact,
      result: fallbackResult
    )
    #expect(fallbackResult.fallbackLen[2] == 2)

    let fastWinners = [winner(position: 0, len: 4, priorityRank: 0, ruleID: 202, tokenKindID: 3)]
    let integrated = integrateWithFallback(
      fastWinners: fastWinners,
      fallbackResult: fallbackResult,
      pageWidth: validLen
    )
    let selected = greedyNonOverlapSelect(winners: integrated, validLen: validLen)

    #expect(
      integrated[2] == winner(position: 2, len: 2, priorityRank: 5, ruleID: 1, tokenKindID: 2))
    #expect(
      selected
        == [
          winner(position: 0, len: 4, priorityRank: 0, ruleID: 202, tokenKindID: 3),
          winner(position: 4, len: 2, priorityRank: 5, ruleID: 1, tokenKindID: 2),
        ])
  }
}

private func selectMixed(
  fastWinners: [CandidateWinner],
  fallbackResult: FallbackPageResult,
  validLen: Int
) -> [CandidateWinner] {
  let integrated = integrateWithFallback(
    fastWinners: fastWinners,
    fallbackResult: fallbackResult,
    pageWidth: validLen
  )
  return greedyNonOverlapSelect(winners: integrated, validLen: validLen)
}

private func evaluateFallback(
  bytes: [UInt8],
  validLen: Int,
  artifact: LexerArtifact
) throws -> FallbackPageResult {
  return scalarEvaluateFallbackPage(
    bytes: bytes,
    validLen: validLen,
    artifact: artifact
  )
}

private func assertMatchesScalar(
  bytes: [UInt8],
  validLen: Int,
  artifact: LexerArtifact,
  result: FallbackPageResult
) {
  let scalar = ScalarFallbackEvaluator()
  for start in 0..<bytes.count {
    let winner = scalar.evaluate(
      bytes: bytes,
      startPosition: start,
      validLen: validLen,
      byteToClass: artifact.byteToClass,
      artifact: artifact
    )
    #expect(result.fallbackLen[start] == winner.len)
    #expect(result.fallbackPriorityRank[start] == winner.priorityRank)
    #expect(result.fallbackRuleID[start] == winner.ruleID)
    #expect(result.fallbackTokenKindID[start] == winner.tokenKindID)
    #expect(result.fallbackMode[start] == winner.mode)
  }
}

private func makeBoundedFallbackArtifact(
  _ artifact: LexerArtifact,
  fallbackMaxWidth: UInt16
) -> LexerArtifact {
  let rules = artifact.rules.map { rule in
    guard case .fallback = rule.plan else {
      return rule
    }
    return LoweredRule(
      ruleID: rule.ruleID,
      name: rule.name,
      tokenKindID: rule.tokenKindID,
      mode: rule.mode,
      family: rule.family,
      priorityRank: rule.priorityRank,
      minWidth: rule.minWidth,
      maxWidth: fallbackMaxWidth,
      firstClassSetID: rule.firstClassSetID,
      plan: rule.plan
    )
  }

  return LexerArtifact(
    formatVersion: artifact.formatVersion,
    specName: artifact.specName,
    specHashHex: artifact.specHashHex,
    generatorVersion: artifact.generatorVersion,
    runtimeHints: RuntimeHints(
      maxLiteralLength: artifact.runtimeHints.maxLiteralLength,
      maxBoundedRuleWidth: max(artifact.runtimeHints.maxBoundedRuleWidth, fallbackMaxWidth),
      maxDeterministicLookaheadBytes: max(
        artifact.runtimeHints.maxDeterministicLookaheadBytes,
        fallbackMaxWidth
      )
    ),
    tokenKinds: artifact.tokenKinds,
    byteToClass: artifact.byteToClass,
    classes: artifact.classes,
    classSets: artifact.classSets,
    rules: rules,
    keywordRemaps: artifact.keywordRemaps
  )
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
