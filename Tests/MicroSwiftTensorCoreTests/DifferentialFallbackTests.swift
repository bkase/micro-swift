import MicroSwiftTensorCore
import Testing

@testable import MicroSwiftLexerGen

@Suite
struct DifferentialFallbackTests {
  private let scalar = ScalarFallbackEvaluator()

  @Test(.enabled(if: requiresMLXEval))
  func fallbackKernelMatchesScalarOnSeededRandomShortInputs() throws {
    let artifacts: [LexerArtifact] = [
      FallbackFixtures.singleRuleFallback(),
      FallbackFixtures.multiRuleFallbackWithPriority(),
      FallbackFixtures.mixedFastAndFallback(),
      FallbackFixtures.overlappingFastFallback(),
      FallbackFixtures.nearCapStateCount(),
    ].map(makeBoundedFallbackArtifactForTests)

    var rng = LCRNG(seed: 0xBADA_553D)
    for artifact in artifacts {
      let runtime = try ArtifactRuntime.fromArtifact(artifact)
      let fallback = try #require(runtime.fallback)
      let runner = FallbackKernelRunner(fallback: fallback)

      for _ in 0..<120 {
        let bytes = randomBytes(rng: &rng, maxLen: 32)
        let classIDs = bytes.map { UInt16(artifact.byteToClass[Int($0)]) }
        let validLen = rng.nextInt(upperBound: classIDs.count + 1)

        var observability = FallbackObservability()
        let page = runner.evaluatePage(
          classIDs: classIDs,
          validLen: Int32(validLen),
          observability: &observability
        )
        #expect(observability.fallbackKernelBackendDispatches == 1)
        #expect(
          observability.fallbackPositionsEntered + observability.fallbackPositionsSkippedByStartMask
            == validLen
        )
        for position in 0..<bytes.count {
          let scalarWinner = scalar.evaluate(
            bytes: bytes,
            startPosition: position,
            validLen: validLen,
            byteToClass: artifact.byteToClass,
            artifact: artifact
          )

          #expect(page.fallbackLen[position] == scalarWinner.len)
          #expect(page.fallbackPriorityRank[position] == scalarWinner.priorityRank)
          #expect(page.fallbackRuleID[position] == scalarWinner.ruleID)
          #expect(page.fallbackTokenKindID[position] == scalarWinner.tokenKindID)
          #expect(page.fallbackMode[position] == scalarWinner.mode)
        }
      }
    }
  }

  private func randomBytes(rng: inout LCRNG, maxLen: Int) -> [UInt8] {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789_ A!?".utf8)
    let len = rng.nextInt(upperBound: maxLen + 1)
    return (0..<len).map { _ in alphabet[rng.nextInt(upperBound: alphabet.count)] }
  }
}
