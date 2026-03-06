import Foundation
import MicroSwiftLexerGen
import Testing

@testable import MicroSwiftTensorCore

@Suite
struct ArtifactLoaderTests {
  @Test
  func loadsValidArtifact() throws {
    let artifact = try makeMicroSwiftArtifact()

    let runtime = try ArtifactLoader.load(artifact)

    #expect(runtime.specName == artifact.specName)
    #expect(runtime.ruleCount == artifact.rules.count)
    #expect(runtime.byteToClassLUT.count == 256)
    #expect(runtime.tokenKinds == artifact.tokenKinds)
    #expect(runtime.rules == artifact.rules)
    #expect(runtime.keywordRemaps == artifact.keywordRemaps)
    #expect(runtime.classSets == artifact.classSets)
    #expect(runtime.classes == artifact.classes)
  }

  @Test
  func rejectsInvalidByteToClassSize() throws {
    let artifact = try makeMicroSwiftArtifact()
    let invalid = try mutatingArtifactJSON(artifact) { root in
      root["byteToClass"] = Array(repeating: 0, count: 255)
    }

    #expect(throws: ArtifactLoaderError.invalidByteToClassSize(expected: 256, got: 255)) {
      try ArtifactLoader.load(invalid)
    }
  }

  @Test
  func extractsRuntimeHintConstants() throws {
    let artifact = try makeMicroSwiftArtifact()

    let runtime = try ArtifactLoader.load(artifact)

    #expect(runtime.maxLiteralLength == artifact.runtimeHints.maxLiteralLength)
    #expect(runtime.maxBoundedRuleWidth == artifact.runtimeHints.maxBoundedRuleWidth)
    #expect(
      runtime.maxDeterministicLookaheadBytes == artifact.runtimeHints.maxDeterministicLookaheadBytes
    )
  }

  @Test
  func rejectsEmptyRules() throws {
    let artifact = try makeMicroSwiftArtifact()
    let invalid = try mutatingArtifactJSON(artifact) { root in
      root["rules"] = []
    }

    #expect(throws: ArtifactLoaderError.emptyRules) {
      try ArtifactLoader.load(invalid)
    }
  }

  private func makeMicroSwiftArtifact() throws -> LexerArtifact {
    let declared = microSwiftV0.declare()
    let normalized = DeclaredSpec.normalize(declared)
    let validated = try NormalizedSpec.validate(normalized)
    let byteClasses = validated.buildByteClasses()
    let classSets = validated.buildClassSets(using: byteClasses)
    let classified = try validated.classifyRules(byteClasses: byteClasses, classSets: classSets)

    return try ArtifactSerializer.build(
      classified: classified,
      byteClasses: byteClasses,
      classSets: classSets,
      generatorVersion: "test"
    )
  }

  private func mutatingArtifactJSON(
    _ artifact: LexerArtifact,
    _ mutate: (inout [String: Any]) -> Void
  ) throws -> LexerArtifact {
    let encoded = try ArtifactSerializer.encode(artifact)
    var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    mutate(&json)
    let mutated = try JSONSerialization.data(withJSONObject: json)
    return try ArtifactSerializer.decode(mutated)
  }
}
