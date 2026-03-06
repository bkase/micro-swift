import MicroSwiftLexerGen
import Testing

@testable import MicroSwiftTensorCore

@Suite
struct RuleBucketTests {
  @Test
  func literalsGroupedByLength() throws {
    let artifact = try makeMicroSwiftArtifact()
    let buckets = RuleBuckets.build(from: artifact.rules)

    let literalRules = artifact.rules.filter { rule in
      if case .literal = rule.plan {
        return true
      }
      return false
    }

    let groupedCount = buckets.literalBuckets.values.reduce(0) { $0 + $1.count }
    #expect(groupedCount == literalRules.count)

    for (length, rules) in buckets.literalBuckets {
      for rule in rules {
        switch rule.plan {
        case .literal(let bytes):
          #expect(bytes.count == length)
        default:
          Issue.record("non-literal rule found in literal bucket")
        }
      }

      let ids = rules.map(\LoweredRule.ruleID)
      #expect(ids == ids.sorted())
    }
  }

  @Test
  func runRulesSortedIntoCorrectBuckets() throws {
    let artifact = try makeMicroSwiftArtifact()
    let buckets = RuleBuckets.build(from: artifact.rules)

    let expectedClassRun = artifact.rules
      .filter {
        if case .runClassRun = $0.plan {
          return true
        }
        return false
      }
      .sorted { $0.ruleID < $1.ruleID }
      .map(\LoweredRule.ruleID)

    let expectedHeadTail = artifact.rules
      .filter {
        if case .runHeadTail = $0.plan {
          return true
        }
        return false
      }
      .sorted { $0.ruleID < $1.ruleID }
      .map(\LoweredRule.ruleID)

    let expectedPrefixed = artifact.rules
      .filter {
        if case .runPrefixed = $0.plan {
          return true
        }
        return false
      }
      .sorted { $0.ruleID < $1.ruleID }
      .map(\LoweredRule.ruleID)

    #expect(buckets.classRunRules.map(\LoweredRule.ruleID) == expectedClassRun)
    #expect(buckets.headTailRules.map(\LoweredRule.ruleID) == expectedHeadTail)
    #expect(buckets.prefixedRules.map(\LoweredRule.ruleID) == expectedPrefixed)
  }

  @Test
  func emptyRulesProduceEmptyBuckets() {
    let buckets = RuleBuckets.build(from: [])

    #expect(buckets.literalBuckets.isEmpty)
    #expect(buckets.classRunRules.isEmpty)
    #expect(buckets.headTailRules.isEmpty)
    #expect(buckets.prefixedRules.isEmpty)
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
}
