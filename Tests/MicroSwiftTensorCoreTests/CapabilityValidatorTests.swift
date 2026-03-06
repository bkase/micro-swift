import Foundation
import Testing
@testable import MicroSwiftTensorCore
import MicroSwiftLexerGen

@Suite
struct CapabilityValidatorTests {
  @Test
  func validArtifactWithLiteralAndRunRulesPasses() throws {
    let artifact = try makeMicroSwiftArtifact()
    let runtime = try ArtifactLoader.load(artifact)

    let result = CapabilityValidator.validate(runtime)

    #expect(result.isValid)
    #expect(result.diagnostics.isEmpty)
  }

  @Test
  func localWindowRuleFailsWithDiagnostic() throws {
    let artifact = try makeMicroSwiftArtifact()
    let invalid = try mutatingArtifactJSON(artifact) { root in
      var rules = (root["rules"] as? [[String: Any]]) ?? []
      guard !rules.isEmpty else { return }
      rules[0]["family"] = "localWindow"
      rules[0]["plan"] = [
        "kind": "localWindow",
        "maxWidth": 4,
      ]
      root["rules"] = rules
    }

    let runtime = try ArtifactLoader.load(invalid)
    let result = CapabilityValidator.validate(runtime)

    #expect(!result.isValid)
    #expect(result.diagnostics.count == 1)

    let diagnostic = try #require(result.diagnostics.first)
    #expect(diagnostic.family == "localWindow")
    #expect(diagnostic.ruleID == runtime.rules[0].ruleID)
    #expect(diagnostic.ruleName == runtime.rules[0].name)
    #expect(
      diagnostic.message
        == "artifact-capability-error: unsupported rule family for runtime profile v0, ruleID=\(diagnostic.ruleID), name=\(diagnostic.ruleName), family=localWindow"
    )
  }

  @Test
  func fallbackRuleFails() throws {
    let artifact = try makeMicroSwiftArtifact()
    let invalid = try mutatingArtifactJSON(artifact) { root in
      var rules = (root["rules"] as? [[String: Any]]) ?? []
      guard !rules.isEmpty else { return }
      rules[0]["family"] = "fallback"
      rules[0]["plan"] = [
        "kind": "fallback",
        "stateCount": 1,
        "classCount": 1,
        "transitionRowStride": 1,
        "startState": 0,
        "acceptingStates": [0],
        "transitions": [0],
      ]
      root["rules"] = rules
    }

    let runtime = try ArtifactLoader.load(invalid)
    let result = CapabilityValidator.validate(runtime)

    #expect(!result.isValid)
    #expect(result.diagnostics.count == 1)
    #expect(result.diagnostics[0].family == "fallback")
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
