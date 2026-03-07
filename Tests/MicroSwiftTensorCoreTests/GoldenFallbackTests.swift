import Testing

@testable import MicroSwiftLexerGen

@Suite
struct GoldenFallbackTests {
  @Test(.enabled(if: requiresMLXEval))
  func singleRuleFallbackGolden() throws {
    let bytes = Array("if iffy".utf8)
    let result = try runTestPipeline(bytes: bytes, artifact: FallbackFixtures.singleRuleFallback())
    #expect(
      renderSnapshot(result)
        == """
        TOK[0..<2] rule=1 kind=0 mode=0 lexeme='if'
        TOK[3..<7] rule=0 kind=1 mode=0 lexeme='iffy'
        ERR[2..<3] lexeme=' '
        """
    )
  }

  @Test(.enabled(if: requiresMLXEval))
  func multiRuleFallbackWithPriorityGolden() throws {
    let bytes = Array("abc123 z9".utf8)
    let result = try runTestPipeline(
      bytes: bytes, artifact: FallbackFixtures.multiRuleFallbackWithPriority())
    #expect(
      renderSnapshot(result)
        == """
        TOK[0..<6] rule=1 kind=2 mode=0 lexeme='abc123'
        TOK[7..<9] rule=1 kind=2 mode=0 lexeme='z9'
        ERR[6..<7] lexeme=' '
        """
    )
  }

  @Test(.enabled(if: requiresMLXEval))
  func mixedFastAndFallbackGolden() throws {
    let bytes = Array("let x9 42 _a1".utf8)
    let result = try runTestPipeline(
      bytes: bytes, artifact: FallbackFixtures.mixedFastAndFallback())
    #expect(
      renderSnapshot(result)
        == """
        TOK[0..<3] rule=0 kind=4 mode=0 lexeme='let'
        TOK[4..<6] rule=2 kind=1 mode=0 lexeme='x9'
        TOK[7..<9] rule=1 kind=3 mode=0 lexeme='42'
        TOK[10..<13] rule=2 kind=1 mode=0 lexeme='_a1'
        ERR[3..<4] lexeme=' '
        ERR[6..<7] lexeme=' '
        ERR[9..<10] lexeme=' '
        """
    )
  }

  @Test(.enabled(if: requiresMLXEval))
  func zeroFallbackRulesGolden() throws {
    let bytes = Array("if 123 a".utf8)
    let result = try runTestPipeline(bytes: bytes, artifact: FallbackFixtures.zeroFallbackRules())
    #expect(
      renderSnapshot(result)
        == """
        TOK[0..<2] rule=0 kind=0 mode=0 lexeme='if'
        TOK[3..<6] rule=1 kind=3 mode=0 lexeme='123'
        ERR[2..<3] lexeme=' '
        ERR[6..<8] lexeme=' a'
        """
    )
  }
}
