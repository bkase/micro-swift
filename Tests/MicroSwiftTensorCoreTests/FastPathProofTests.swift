import Testing

@testable import MicroSwiftLexerGen
@testable import MicroSwiftTensorCore

@Suite
struct FastPathProofTests {
  @Test(.enabled(if: requiresMLXEval))
  func proofLaneCoversLiteralRunPrefixedAndWarmReuse() throws {
    let literalRuntime = try ArtifactRuntime.fromArtifact(buildLiteralArtifact())
    let runRuntime = try ArtifactRuntime.fromArtifact(buildRunArtifact())
    let prefixedRuntime = try ArtifactRuntime.fromArtifact(buildPrefixedArtifact())

    TensorLexer.resetFastPathGraphCache()
    CompiledPageInput.resetHostExtractionCounts()
    ClassRunExecution.resetDispatchMetrics()

    let literalRows = try lexTwice(
      bytes: Array("aaaaaaaaaaaa".utf8),
      runtime: literalRuntime
    )
    let runRows = try lexTwice(
      bytes: Array("alpha beta gamma42 delta99 _omega123".utf8),
      runtime: runRuntime
    )
    let prefixedRows = try lexTwice(
      bytes: Array("//aaaa\n//bbbb\n//cccc\n".utf8),
      runtime: prefixedRuntime
    )

    #expect(literalRows > 0)
    #expect(runRows > 0)
    #expect(prefixedRows > 0)

    let metrics = TensorLexer.fastPathGraphMetrics()
    #expect(metrics.compileCount == 3)
    #expect(metrics.cacheMisses == 3)
    #expect(metrics.cacheHits >= 3)

    let store = try #require(
      metrics.cacheEvents.first {
        ($0.event == "fast-path-graph-cache-store" || $0.event == "fast-path-graph-cache-hit")
          && $0.runtimeMetadata != nil
      })
    let metadata = try #require(store.runtimeMetadata)
    #expect(metadata.backend.hasPrefix("mlx"))
    #expect(metadata.pipelineFunction == "fastPathPageGraph")

    let hostExtractions = CompiledPageInput.hostExtractionCounts()
    #expect(hostExtractions.transitionalFamilyExecution == 0)

    let runMetrics = ClassRunExecution.dispatchMetrics()
    #expect(runMetrics.classRunDispatches > 0)
    #expect(runMetrics.headTailDispatches > 0)
  }
}

private func lexTwice(bytes: [UInt8], runtime: ArtifactRuntime) throws -> Int {
  let options = LexOptions(runtimeProfile: .v0)
  let first = TensorLexer.lexPage(
    bytes: bytes,
    validLen: Int32(bytes.count),
    baseOffset: 0,
    artifact: runtime,
    options: options
  )
  let second = TensorLexer.lexPage(
    bytes: bytes,
    validLen: Int32(bytes.count),
    baseOffset: 0,
    artifact: runtime,
    options: options
  )
  #expect(first == second)
  return Int(second.rowCount)
}

private func buildLiteralArtifact() throws -> LexerArtifact {
  let spec = LexerSpec(name: "fast-path-proof.literal") {
    token("letterA", literal("a"))
  }
  return try buildArtifact(spec, generatorVersion: "fast-path-proof-literal")
}

private func buildRunArtifact() throws -> LexerArtifact {
  let spec = LexerSpec(name: "fast-path-proof.run") {
    token("ident", .byteClass(.asciiIdentStart) <> zeroOrMore(.byteClass(.asciiIdentContinue)))
    token("int", oneOrMore(.byteClass(.asciiDigit)))
    skip("ws", oneOrMore(.byteClass(.asciiWhitespace)))
  }
  return try buildArtifact(spec, generatorVersion: "fast-path-proof-run")
}

private func buildPrefixedArtifact() throws -> LexerArtifact {
  let spec = LexerSpec(name: "fast-path-proof.prefixed") {
    token("lineComment", literal("//") <> zeroOrMore(not(.newline)))
    token("newline", literal("\n"))
  }
  return try buildArtifact(spec, generatorVersion: "fast-path-proof-prefixed")
}

private func buildArtifact(_ spec: LexerSpec, generatorVersion: String) throws -> LexerArtifact {
  let declared = spec.declare()
  let normalized = DeclaredSpec.normalize(declared)
  let validated = try NormalizedSpec.validate(normalized)
  let byteClasses = validated.buildByteClasses()
  let classSets = validated.buildClassSets(using: byteClasses)
  let classified = try validated.classifyRules(
    byteClasses: byteClasses,
    classSets: classSets
  )

  return try ArtifactSerializer.build(
    classified: classified,
    byteClasses: byteClasses,
    classSets: classSets,
    generatorVersion: generatorVersion
  )
}
