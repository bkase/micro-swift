import Testing

@testable import MicroSwiftLexerGen

@Suite
struct PropertyFallbackTests {
  @Test
  func determinismSameBytesAndArtifactSameResults() throws {
    var rng = LCRNG(seed: 0xD1CE_F00D)
    for artifact in propertyFixtures() {
      for _ in 0..<80 {
        let bytes = randomBytes(rng: &rng, maxLen: 24)
        let first = try runTestPipeline(bytes: bytes, artifact: artifact)
        let second = try runTestPipeline(bytes: bytes, artifact: artifact)
        #expect(first == second)
      }
    }
  }

  @Test
  func sourceOrderTokenPositionsStrictlyIncrease() throws {
    var rng = LCRNG(seed: 0xAA55_0001)
    for artifact in propertyFixtures() {
      for _ in 0..<80 {
        let bytes = randomBytes(rng: &rng, maxLen: 24)
        let result = try runTestPipeline(bytes: bytes, artifact: artifact)
        var previous = -1
        for token in result.tokens {
          #expect(token.start > previous)
          previous = token.start
        }
      }
    }
  }

  @Test
  func noOverlapBetweenSelectedTokens() throws {
    var rng = LCRNG(seed: 0xAA55_0002)
    for artifact in propertyFixtures() {
      for _ in 0..<80 {
        let bytes = randomBytes(rng: &rng, maxLen: 24)
        let result = try runTestPipeline(bytes: bytes, artifact: artifact)
        var covered = Set<Int>()
        for token in result.tokens {
          for i in token.start..<token.end {
            #expect(!covered.contains(i))
            covered.insert(i)
          }
        }
      }
    }
  }

  @Test
  func coverageCompletenessEveryValidByteCoveredByTokenOrErrorRun() throws {
    var rng = LCRNG(seed: 0xAA55_0003)
    for artifact in propertyFixtures() {
      for _ in 0..<80 {
        let bytes = randomBytes(rng: &rng, maxLen: 24)
        let result = try runTestPipeline(bytes: bytes, artifact: artifact)

        var covered = Array(repeating: false, count: bytes.count)
        for token in result.tokens where token.start < token.end {
          for i in token.start..<token.end {
            covered[i] = true
          }
        }
        for run in result.errorRuns where run.start < run.end {
          for i in run.start..<run.end {
            covered[i] = true
          }
        }

        #expect(covered.allSatisfy { $0 })
      }
    }
  }

  @Test
  func keywordRemapPreservesTokenSpans() throws {
    let fixtures = keywordRemapFixtures()
    let inputs: [[UInt8]] = [
      Array("if abc _a1 z9".utf8),
      Array("abc123 if _a1".utf8),
      Array("let _a1 if".utf8),
    ]

    for artifact in fixtures {
      for bytes in inputs {
        let withoutRemap = try runTestPipeline(
          bytes: bytes,
          artifact: artifact,
          applyKeywordRemap: false
        )
        let withRemap = try runTestPipeline(
          bytes: bytes,
          artifact: artifact,
          applyKeywordRemap: true
        )

        #expect(withoutRemap.tokens.count == withRemap.tokens.count)
        for index in withoutRemap.tokens.indices {
          let lhs = withoutRemap.tokens[index]
          let rhs = withRemap.tokens[index]
          #expect(lhs.start == rhs.start)
          #expect(lhs.end == rhs.end)
          #expect(lhs.ruleID == rhs.ruleID)
          #expect(lhs.mode == rhs.mode)
          #expect(lhs.lexeme == rhs.lexeme)
        }
      }
    }
  }

  private func propertyFixtures() -> [LexerArtifact] {
    [
      FallbackFixtures.singleRuleFallback(),
      FallbackFixtures.multiRuleFallbackWithPriority(),
      FallbackFixtures.mixedFastAndFallback(),
      FallbackFixtures.overlappingFastFallback(),
      FallbackFixtures.zeroFallbackRules(),
    ]
  }

  private func keywordRemapFixtures() -> [LexerArtifact] {
    var multi = FallbackFixtures.multiRuleFallbackWithPriority()
    multi = withExtraTokenKinds(multi, ids: [9, 10])
    multi = LexerArtifact(
      formatVersion: multi.formatVersion,
      specName: "\(multi.specName)-remap",
      specHashHex: multi.specHashHex,
      generatorVersion: multi.generatorVersion,
      runtimeHints: multi.runtimeHints,
      tokenKinds: multi.tokenKinds,
      byteToClass: multi.byteToClass,
      classes: multi.classes,
      classSets: multi.classSets,
      rules: multi.rules,
      keywordRemaps: [
        KeywordRemapTable(
          baseRuleID: 1,
          baseTokenKindID: 2,
          maxKeywordLength: 6,
          entries: [
            KeywordRemapEntry(lexeme: Array("if".utf8), tokenKindID: 9),
            KeywordRemapEntry(lexeme: Array("abc".utf8), tokenKindID: 10),
          ]
        )
      ]
    )

    var mixed = FallbackFixtures.mixedFastAndFallback()
    mixed = withExtraTokenKinds(mixed, ids: [11])
    mixed = LexerArtifact(
      formatVersion: mixed.formatVersion,
      specName: "\(mixed.specName)-remap",
      specHashHex: mixed.specHashHex,
      generatorVersion: mixed.generatorVersion,
      runtimeHints: mixed.runtimeHints,
      tokenKinds: mixed.tokenKinds,
      byteToClass: mixed.byteToClass,
      classes: mixed.classes,
      classSets: mixed.classSets,
      rules: mixed.rules,
      keywordRemaps: [
        KeywordRemapTable(
          baseRuleID: 2,
          baseTokenKindID: 1,
          maxKeywordLength: 4,
          entries: [
            KeywordRemapEntry(lexeme: Array("_a1".utf8), tokenKindID: 11)
          ]
        )
      ]
    )

    return [multi, mixed]
  }

  private func withExtraTokenKinds(_ artifact: LexerArtifact, ids: [UInt16]) -> LexerArtifact {
    var kinds = artifact.tokenKinds
    var existing = Set(kinds.map(\.tokenKindID))
    for id in ids where !existing.contains(id) {
      kinds.append(TokenKindDecl(tokenKindID: id, name: "remap\(id)", defaultMode: .emit))
      existing.insert(id)
    }
    return LexerArtifact(
      formatVersion: artifact.formatVersion,
      specName: artifact.specName,
      specHashHex: artifact.specHashHex,
      generatorVersion: artifact.generatorVersion,
      runtimeHints: artifact.runtimeHints,
      tokenKinds: kinds.sorted(by: { $0.tokenKindID < $1.tokenKindID }),
      byteToClass: artifact.byteToClass,
      classes: artifact.classes,
      classSets: artifact.classSets,
      rules: artifact.rules,
      keywordRemaps: artifact.keywordRemaps
    )
  }

  private func randomBytes(rng: inout LCRNG, maxLen: Int) -> [UInt8] {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789_ A!?".utf8)
    let len = rng.nextInt(upperBound: maxLen + 1)
    return (0..<len).map { _ in alphabet[rng.nextInt(upperBound: alphabet.count)] }
  }
}
