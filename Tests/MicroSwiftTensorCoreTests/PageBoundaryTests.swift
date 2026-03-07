import MicroSwiftTensorCore
import Testing

@testable import MicroSwiftLexerGen

@Suite
struct PageBoundaryTests {
  private let scalar = ScalarFallbackEvaluator()

  @Test(.enabled(if: requiresMLXEval))
  func fallbackMatchEndingExactlyAtPageEndUsesValidLen() throws {
    let artifact = makeBoundedFallbackArtifact(
      FallbackFixtures.singleRuleFallback(),
      fallbackMaxWidth: 8
    )
    let bytes = Array("12abc".utf8)
    let validLen = bytes.count

    let result = try evaluateFallback(bytes: bytes, validLen: validLen, artifact: artifact)
    assertMatchesScalar(bytes: bytes, validLen: validLen, artifact: artifact, result: result)

    #expect(result.fallbackLen[2] == 3)
    #expect(result.fallbackRuleID[2] == 0)
  }

  @Test(.enabled(if: requiresMLXEval))
  func fallbackPrefixNearPageEndFailsWhenPageEnds() throws {
    let artifact = makeABFallbackArtifact(maxWidth: 2)
    let bytes = Array("xxa".utf8)
    let validLen = bytes.count

    let result = try evaluateFallback(bytes: bytes, validLen: validLen, artifact: artifact)
    assertMatchesScalar(bytes: bytes, validLen: validLen, artifact: artifact, result: result)

    #expect(result.fallbackLen[2] == 0)
    #expect(result.fallbackRuleID[2] == 0)
  }

  @Test(.enabled(if: requiresMLXEval))
  func fallbackCandidateFullyContainedInsidePage() throws {
    let artifact = makeABFallbackArtifact(maxWidth: 2)
    let bytes = Array("zabz".utf8)
    let validLen = bytes.count

    let result = try evaluateFallback(bytes: bytes, validLen: validLen, artifact: artifact)
    assertMatchesScalar(bytes: bytes, validLen: validLen, artifact: artifact, result: result)

    #expect(result.fallbackLen[1] == 2)
    #expect(result.fallbackRuleID[1] == 7)
    #expect(result.fallbackLen[2] == 0)
  }

  @Test(.enabled(if: requiresMLXEval))
  func fallbackFastOverlapNearPageBoundaryResolvesToFastWinner() throws {
    let artifact = makeBoundedFallbackArtifact(
      FallbackFixtures.overlappingFastFallback(),
      fallbackMaxWidth: 4
    )
    let bytes = Array("1if".utf8)
    let validLen = bytes.count

    let fallbackResult = try evaluateFallback(bytes: bytes, validLen: validLen, artifact: artifact)
    assertMatchesScalar(
      bytes: bytes,
      validLen: validLen,
      artifact: artifact,
      result: fallbackResult
    )

    let fastWinners = [
      winner(position: 1, len: 2, priorityRank: 0, ruleID: 0, tokenKindID: 0)
    ]
    let integrated = integrateWithFallback(
      fastWinners: fastWinners,
      fallbackResult: fallbackResult,
      pageWidth: validLen
    )
    let selected = greedyNonOverlapSelect(winners: integrated, validLen: validLen)

    #expect(selected.count == 1)
    #expect(selected[0] == winner(position: 1, len: 2, priorityRank: 0, ruleID: 0, tokenKindID: 0))
  }

  @Test(.enabled(if: requiresMLXEval))
  func classRunDoesNotLeakIntoPaddedTailBytes() {
    let runtime = ClassSetRuntime(
      mask: [[false, true]],
      numClassSets: 1,
      numByteClasses: 2
    )
    let classIDs: [UInt8] = [1, 1, 1, 1, 1, 1]
    let validMask: [Bool] = [true, true, true, false, false, false]

    let result = ClassRunExecution.evaluateClassRun(
      classIDs: classIDs,
      validMask: validMask,
      bodyClassSetID: 0,
      minLength: 1,
      classSetRuntime: runtime
    )

    #expect(result == [3, 0, 0, 0, 0, 0])
  }

  @Test(.enabled(if: requiresMLXEval))
  func headTailDoesNotLeakIntoPaddedTailBytes() {
    let runtime = ClassSetRuntime(
      mask: [
        [false, true, false],
        [false, true, true],
      ],
      numClassSets: 2,
      numByteClasses: 3
    )
    let classIDs: [UInt8] = [1, 2, 2, 2, 2]
    let validMask: [Bool] = [true, true, false, false, false]

    let result = HeadTailExecution.evaluateHeadTail(
      classIDs: classIDs,
      validMask: validMask,
      headClassSetID: 0,
      tailClassSetID: 1,
      classSetRuntime: runtime
    )

    #expect(result == [2, 0, 0, 0, 0])
  }

  @Test(.enabled(if: requiresMLXEval))
  func prefixedStopAwareRuleStopsAtNewlineInsidePage() {
    let runtime = makePrefixedClassRuntime()
    let bytes = Array("//abc\nz".utf8)
    let validMask = Array(repeating: true, count: bytes.count)
    let classIDs = classifyPrefixedBoundary(bytes)
    let stopMask = zip(classIDs, validMask).map { classID, valid in
      valid && runtime.contains(setID: 1, classID: classID)
    }
    let nextStop = NextStopHelper.computeNextStop(stopMask: stopMask, validLen: Int32(bytes.count))

    let lengths = PrefixedExecution.evaluatePrefixed(
      bytes: bytes,
      classIDs: classIDs,
      validMask: validMask,
      prefix: Array("//".utf8),
      bodyClassSetID: 0,
      stopClassSetID: 1,
      classSetRuntime: runtime,
      nextStop: nextStop
    )

    #expect(lengths[0] == 5)
    #expect(lengths.dropFirst().allSatisfy { $0 == 0 })
  }

  @Test(.enabled(if: requiresMLXEval))
  func prefixedStopAwareRuleEndsAtValidBoundaryWithoutPaddedTailMatch() {
    let runtime = makePrefixedClassRuntime()
    let bytes = Array("//abc/".utf8) + [UInt8](repeating: PageBucket.neutralPaddingByte, count: 2)
    let validLen = 6
    let validMask = (0..<bytes.count).map { $0 < validLen }
    let classIDs = classifyPrefixedBoundary(bytes)
    let stopMask = zip(classIDs, validMask).map { classID, valid in
      valid && runtime.contains(setID: 1, classID: classID)
    }
    let nextStop = NextStopHelper.computeNextStop(stopMask: stopMask, validLen: Int32(validLen))

    let lengths = PrefixedExecution.evaluatePrefixed(
      bytes: bytes,
      classIDs: classIDs,
      validMask: validMask,
      prefix: Array("//".utf8),
      bodyClassSetID: 0,
      stopClassSetID: 1,
      classSetRuntime: runtime,
      nextStop: nextStop
    )

    #expect(lengths[0] == 6)
    #expect(lengths[5] == 0)
    #expect(lengths[6] == 0)
  }
}

private func makeABFallbackArtifact(maxWidth: UInt16) -> LexerArtifact {
  var byteToClass = Array(repeating: UInt8(2), count: 256)
  byteToClass[Int(Character("a").asciiValue!)] = 0
  byteToClass[Int(Character("b").asciiValue!)] = 1

  let rule = LoweredRule(
    ruleID: 7,
    name: "abFallback",
    tokenKindID: 1,
    mode: .emit,
    family: .fallback,
    priorityRank: 10,
    minWidth: 2,
    maxWidth: maxWidth,
    firstClassSetID: 0,
    plan: .fallback(
      stateCount: 4,
      classCount: 3,
      transitionRowStride: 3,
      startState: 0,
      acceptingStates: [2],
      transitions: [
        1, 3, 3,
        3, 2, 3,
        3, 3, 3,
        3, 3, 3,
      ]
    )
  )

  return LexerArtifact(
    formatVersion: 1,
    specName: "ab-fallback",
    specHashHex: String(repeating: "0", count: 64),
    generatorVersion: "tests",
    runtimeHints: RuntimeHints(
      maxLiteralLength: 0,
      maxBoundedRuleWidth: maxWidth,
      maxDeterministicLookaheadBytes: maxWidth
    ),
    tokenKinds: [TokenKindDecl(tokenKindID: 1, name: "abTok", defaultMode: .emit)],
    byteToClass: byteToClass,
    classes: [],
    classSets: [],
    rules: [rule],
    keywordRemaps: []
  )
}

private func evaluateFallback(
  bytes: [UInt8],
  validLen: Int,
  artifact: LexerArtifact
) throws -> FallbackPageResult {
  let runtime = try ArtifactRuntime.fromArtifact(artifact)
  let fallback = try #require(runtime.fallback)
  let runner = FallbackKernelRunner(fallback: fallback)
  let classIDs = bytes.map { UInt16(artifact.byteToClass[Int($0)]) }
  return runner.evaluatePage(classIDs: classIDs, validLen: Int32(validLen))
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

private func makePrefixedClassRuntime() -> ClassSetRuntime {
  let body = [true, true, false, true]
  let stop = [false, false, true, false]
  return ClassSetRuntime(mask: [body, stop], numClassSets: 2, numByteClasses: 4)
}

private func classifyPrefixedBoundary(_ bytes: [UInt8]) -> [UInt8] {
  bytes.map { byte in
    if byte == UInt8(ascii: "/") { return 0 }
    if byte == UInt8(ascii: "\n") { return 2 }
    if byte == UInt8(ascii: " ") { return 3 }
    return 1
  }
}
