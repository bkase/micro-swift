import MicroSwiftLexerGen
import Testing

@testable import MicroSwiftTensorCore

@Suite
struct LexPageIntegrationTests {
  @Test(.enabled(if: requiresMLXEval))
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

  @Test(.enabled(if: requiresMLXEval))
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

  @Test(.enabled(if: requiresMLXEval))
  func deviceExecutionMaterializesToSameResultAsEndToEndLexPage() throws {
    let runtime = try makeMicroSwiftRuntime()
    let input = "let value = 42\n"
    let bytes = Array(input.utf8)
    let bucket =
      PageBucket.bucket(for: Int32(bytes.count))
      ?? PageBucket(byteCapacity: Int32(max(bytes.count, 1)))
    let compiledPage = CompiledPageInput(
      bytes: bytes,
      validLen: Int32(bytes.count),
      baseOffset: 0,
      bucket: bucket,
      artifact: runtime
    )
    let options = LexOptions(emitSkipTokens: false, runtimeProfile: .v1Fallback)

    let deviceResult = TensorLexer.lexPageDevice(
      compiledPage: compiledPage,
      artifact: runtime,
      options: options
    )
    let materialized = TensorLexer.materialize(
      deviceResult: deviceResult,
      remapTables: [],
      options: options
    )
    let endToEnd = TensorLexer.lexPage(
      compiledPage: compiledPage,
      artifact: runtime,
      options: options
    )

    #expect(deviceResult.hostRowCount() == endToEnd.rowCount)
    #expect(materialized == endToEnd)
  }

  @Test(.enabled(if: requiresMLXEval))
  func deviceExecutionAvoidsPackedRowHostMaterializationUntilTransport() throws {
    let runtime = try makeMicroSwiftRuntime()
    let input = "let alpha = beta + 1\n"
    let bytes = Array(input.utf8)
    let bucket =
      PageBucket.bucket(for: Int32(bytes.count))
      ?? PageBucket(byteCapacity: Int32(max(bytes.count, 1)))
    let compiledPage = CompiledPageInput(
      bytes: bytes,
      validLen: Int32(bytes.count),
      baseOffset: 0,
      bucket: bucket,
      artifact: runtime
    )
    let options = LexOptions(emitSkipTokens: false, runtimeProfile: .v1Fallback)

    TransportEmitter.resetHostMaterializationCounts()

    var totalRows: Int32 = 0
    for _ in 0..<3 {
      let deviceResult = TensorLexer.lexPageDevice(
        compiledPage: compiledPage,
        artifact: runtime,
        options: options
      )
      totalRows += deviceResult.hostRowCount()
    }

    let countsBeforeTransport = TransportEmitter.hostMaterializationCounts()
    #expect(totalRows > 0)
    #expect(countsBeforeTransport.packedRows == 0)

    let materialized = TensorLexer.materialize(
      deviceResult: TensorLexer.lexPageDevice(
        compiledPage: compiledPage,
        artifact: runtime,
        options: options
      ),
      remapTables: [],
      options: options
    )

    #expect(materialized.rowCount > 0)

    let countsAfterTransport = TransportEmitter.hostMaterializationCounts()
    #expect(countsAfterTransport.packedRows == 1)
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
