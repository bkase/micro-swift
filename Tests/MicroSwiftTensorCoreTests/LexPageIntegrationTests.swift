import MicroSwiftLexerGen
import Testing

@testable import MicroSwiftTensorCore

@Suite
struct LexPageIntegrationTests {
  @Test
  func lexSimpleInputEndToEnd() throws {
    let runtime = try makeMicroSwiftRuntime()
    let input = "let x = 42\n"
    let bytes = Array(input.utf8)

    let result = TensorLexer.lexPage(
      bytes: bytes,
      validLen: Int32(bytes.count),
      baseOffset: 0,
      artifact: runtime,
      options: LexOptions(emitSkipTokens: false)
    )
    let tokens = TokenUnpacker.unpack(result: result, baseOffset: 0)
    let kindByID = Dictionary(
      uniqueKeysWithValues: runtime.tokenKinds.map { ($0.tokenKindID, $0.name) })
    let kindNames = tokens.map { kindByID[$0.kind] ?? "<unknown>" }

    #expect(kindNames == ["kwLet", "ident", "eq", "int"])
    #expect(tokens.map(\.startByte) == [0, 4, 6, 8])
    #expect(tokens.map(\.endByte) == [3, 5, 7, 10])
    #expect(result.errorSpans.isEmpty)
  }

  @Test
  func lexPageRejectsLiteralThatWouldReadPastValidLen() throws {
    let runtime = try makeMicroSwiftRuntime()
    let bytes = Array("==".utf8)

    let result = TensorLexer.lexPage(
      bytes: bytes,
      validLen: 1,
      baseOffset: 0,
      artifact: runtime,
      options: LexOptions(emitSkipTokens: false)
    )
    let tokens = TokenUnpacker.unpack(result: result, baseOffset: 0)
    let kindByID = Dictionary(
      uniqueKeysWithValues: runtime.tokenKinds.map { ($0.tokenKindID, $0.name) })
    let kindNames = tokens.map { kindByID[$0.kind] ?? "<unknown>" }

    #expect(tokens.count == 1)
    #expect(tokens[0].startByte == 0)
    #expect(tokens[0].endByte == 1)
    #expect(kindNames == ["eq"])
  }

  private func makeMicroSwiftRuntime() throws -> ArtifactRuntime {
    let declared = microSwiftV0.declare()
    let normalized = DeclaredSpec.normalize(declared)
    let validated = try NormalizedSpec.validate(normalized)
    let byteClasses = validated.buildByteClasses()
    let classSets = validated.buildClassSets(using: byteClasses)
    let classified = try validated.classifyRules(byteClasses: byteClasses, classSets: classSets)
    let artifact = try ArtifactSerializer.build(
      classified: classified,
      byteClasses: byteClasses,
      classSets: classSets,
      generatorVersion: "test"
    )
    return try ArtifactLoader.load(artifact)
  }
}
