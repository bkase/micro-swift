import MicroSwiftTensorCore
import Testing

@testable import MicroSwiftLexerGen

@Suite
struct FallbackKernelRunnerTests {
  private let scalar = ScalarFallbackEvaluator()

  @Test
  func bitsetKernelMatchesScalarAcrossFixtures() throws {
    let artifacts = [
      FallbackFixtures.singleRuleFallback(),
      FallbackFixtures.multiRuleFallbackWithPriority(),
      FallbackFixtures.mixedFastAndFallback(),
      FallbackFixtures.overlappingFastFallback(),
      FallbackFixtures.nearCapStateCount(),
    ].map(makeBoundedFallbackArtifact)

    let inputs: [[UInt8]] = [
      Array("if".utf8),
      Array("iffy".utf8),
      Array("letx".utf8),
      Array("abc123".utf8),
      Array("_a12".utf8),
      Array("999".utf8),
      Array("z".utf8),
      Array("".utf8),
    ]

    for artifact in artifacts {
      let runtime = try ArtifactRuntime.fromArtifact(artifact)
      let fallback = try #require(runtime.fallback)
      let runner = FallbackKernelRunner(fallback: fallback)

      for bytes in inputs {
        let classIDs = bytes.map { UInt16(artifact.byteToClass[Int($0)]) }
        let result = runner.evaluatePage(classIDs: classIDs, validLen: Int32(classIDs.count))
        assertMatchesScalar(
          result: result,
          bytes: bytes,
          validLen: classIDs.count,
          artifact: artifact
        )

        if classIDs.count > 0 {
          let truncated = max(0, classIDs.count - 1)
          let truncatedResult = runner.evaluatePage(
            classIDs: classIDs,
            validLen: Int32(truncated)
          )
          assertMatchesScalar(
            result: truncatedResult,
            bytes: bytes,
            validLen: truncated,
            artifact: artifact
          )
        }
      }
    }
  }

  @Test
  func recordsBackendDispatchInObservability() throws {
    let artifact = makeBoundedFallbackArtifact(FallbackFixtures.singleRuleFallback())
    let runtime = try ArtifactRuntime.fromArtifact(artifact)
    let fallback = try #require(runtime.fallback)
    let runner = FallbackKernelRunner(fallback: fallback)
    let classIDs = Array("if".utf8).map { UInt16(artifact.byteToClass[Int($0)]) }

    var observability = FallbackObservability()
    _ = runner.evaluatePage(
      classIDs: classIDs,
      validLen: Int32(classIDs.count),
      observability: &observability
    )

    #expect(observability.fallbackKernelBackendDispatches == 1)
    #expect(
      observability.fallbackPositionsEntered + observability.fallbackPositionsSkippedByStartMask
        == classIDs.count
    )
  }

  private func assertMatchesScalar(
    result: FallbackPageResult,
    bytes: [UInt8],
    validLen: Int,
    artifact: LexerArtifact
  ) {
    #expect(result.fallbackLen.count == bytes.count)
    #expect(result.fallbackPriorityRank.count == bytes.count)
    #expect(result.fallbackRuleID.count == bytes.count)
    #expect(result.fallbackTokenKindID.count == bytes.count)
    #expect(result.fallbackMode.count == bytes.count)

    for startPosition in 0..<bytes.count {
      let winner = scalar.evaluate(
        bytes: bytes,
        startPosition: startPosition,
        validLen: validLen,
        byteToClass: artifact.byteToClass,
        artifact: artifact
      )

      #expect(result.fallbackLen[startPosition] == winner.len)
      #expect(result.fallbackPriorityRank[startPosition] == winner.priorityRank)
      #expect(result.fallbackRuleID[startPosition] == winner.ruleID)
      #expect(result.fallbackTokenKindID[startPosition] == winner.tokenKindID)
      #expect(result.fallbackMode[startPosition] == winner.mode)
    }
  }
}

private func makeBoundedFallbackArtifact(_ artifact: LexerArtifact) -> LexerArtifact {
  var rules: [LoweredRule] = []
  rules.reserveCapacity(artifact.rules.count)

  var maxWidth: UInt16 = artifact.runtimeHints.maxBoundedRuleWidth

  for rule in artifact.rules {
    guard case .fallback = rule.plan else {
      rules.append(rule)
      continue
    }

    let boundedWidth = rule.maxWidth ?? UInt16(32)
    maxWidth = max(maxWidth, boundedWidth)

    rules.append(
      LoweredRule(
        ruleID: rule.ruleID,
        name: rule.name,
        tokenKindID: rule.tokenKindID,
        mode: rule.mode,
        family: rule.family,
        priorityRank: rule.priorityRank,
        minWidth: rule.minWidth,
        maxWidth: boundedWidth,
        firstClassSetID: rule.firstClassSetID,
        plan: rule.plan
      ))
  }

  return LexerArtifact(
    formatVersion: artifact.formatVersion,
    specName: artifact.specName,
    specHashHex: artifact.specHashHex,
    generatorVersion: artifact.generatorVersion,
    runtimeHints: RuntimeHints(
      maxLiteralLength: artifact.runtimeHints.maxLiteralLength,
      maxBoundedRuleWidth: maxWidth,
      maxDeterministicLookaheadBytes: max(
        artifact.runtimeHints.maxDeterministicLookaheadBytes,
        maxWidth
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
