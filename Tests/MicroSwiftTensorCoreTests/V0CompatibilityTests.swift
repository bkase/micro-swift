import Testing

@testable import MicroSwiftLexerGen
@testable import MicroSwiftTensorCore

@Suite
struct V0CompatibilityTests {
  @Test
  func v0LikeArtifactPassesV1FallbackAndLexesIdentically() throws {
    let artifact = makeV0LikeArtifact()
    #expect(CapabilityValidator.validate(artifact: artifact, profile: .v1Fallback).isEmpty)
    #expect(validateV0UnderV1Fallback(artifact: artifact))

    let runtime = try ArtifactRuntime.fromArtifact(artifact)
    let sample = Array("let alpha = 42".utf8)

    let v0 = lexPage(
      bytes: sample,
      validLen: Int32(sample.count),
      baseOffset: 0,
      artifact: runtime,
      options: LexOptions(runtimeProfile: .v0)
    )
    let v1 = lexPage(
      bytes: sample,
      validLen: Int32(sample.count),
      baseOffset: 0,
      artifact: runtime,
      options: LexOptions(runtimeProfile: .v1Fallback)
    )

    #expect(v0 == v1)
  }

  @Test
  func microSwiftV0ArtifactUnderV1FallbackMatchesV0Profile() throws {
    let artifact = try buildArtifact(
      from: microSwiftV0,
      options: .init(maxLocalWindowBytes: 8, enableFallback: true, maxFallbackStatesPerRule: 256)
    )
    #expect(artifact.rules.allSatisfy { $0.family != .fallback })
    #expect(CapabilityValidator.validate(artifact: artifact, profile: .v1Fallback).isEmpty)
    #expect(validateV0UnderV1Fallback(artifact: artifact))

    let runtime = try ArtifactRuntime.fromArtifact(artifact)
    let sample = Array("func f(x: int) -> int { return x + 1 }".utf8)

    let v0 = lexPage(
      bytes: sample,
      validLen: Int32(sample.count),
      baseOffset: 0,
      artifact: runtime,
      options: LexOptions(runtimeProfile: .v0)
    )
    let v1 = lexPage(
      bytes: sample,
      validLen: Int32(sample.count),
      baseOffset: 0,
      artifact: runtime,
      options: LexOptions(runtimeProfile: .v1Fallback)
    )

    #expect(v0 == v1)
  }

  @Test
  func v1FallbackRejectsLocalWindowWithStructuredDiagnostic() {
    let artifact = makeLocalWindowArtifact()
    let diagnostics = CapabilityValidator.validate(artifact: artifact, profile: .v1Fallback)

    #expect(diagnostics.count == 1)
    #expect(diagnostics[0].reason == .localWindowPresent)
    #expect(
      diagnostics[0].formattedMessage(profile: .v1Fallback)
        == "artifact-capability-error: unsupported localWindow for runtime profile v1-fallback ruleID=9 name=window reason=localWindow-present"
    )
  }
}

private func makeV0LikeArtifact() -> LexerArtifact {
  var byteToClass = Array(repeating: UInt8(1), count: 256)
  byteToClass[Int(Character("l").asciiValue!)] = 0
  byteToClass[Int(Character("e").asciiValue!)] = 0
  byteToClass[Int(Character("t").asciiValue!)] = 0

  let rules = [
    LoweredRule(
      ruleID: 0,
      name: "kwLet",
      tokenKindID: 1,
      mode: .emit,
      family: .literal,
      priorityRank: 0,
      minWidth: 3,
      maxWidth: 3,
      firstClassSetID: 0,
      plan: .literal(bytes: Array("let".utf8))
    ),
    LoweredRule(
      ruleID: 1,
      name: "ident",
      tokenKindID: 2,
      mode: .emit,
      family: .run,
      priorityRank: 1,
      minWidth: 1,
      maxWidth: 32,
      firstClassSetID: 1,
      plan: .runClassRun(bodyClassSetID: 1, minLength: 1)
    ),
  ]

  return LexerArtifact(
    formatVersion: 1,
    specName: "v0-like",
    specHashHex: String(repeating: "0", count: 64),
    generatorVersion: "tests",
    runtimeHints: RuntimeHints(
      maxLiteralLength: 3,
      maxBoundedRuleWidth: 32,
      maxDeterministicLookaheadBytes: 32
    ),
    tokenKinds: [
      TokenKindDecl(tokenKindID: 1, name: "kwLet", defaultMode: .emit),
      TokenKindDecl(tokenKindID: 2, name: "ident", defaultMode: .emit),
    ],
    byteToClass: byteToClass,
    classes: [
      ByteClassDecl(classID: 0, bytes: Array("let".utf8)),
      ByteClassDecl(classID: 1, bytes: [0]),
    ],
    classSets: [
      ClassSetDecl(classSetID: ClassSetID(0), classes: [0]),
      ClassSetDecl(classSetID: ClassSetID(1), classes: [1]),
    ],
    rules: rules,
    keywordRemaps: []
  )
}

private func makeLocalWindowArtifact() -> LexerArtifact {
  LexerArtifact(
    formatVersion: 1,
    specName: "local-window-fixture",
    specHashHex: String(repeating: "f", count: 64),
    generatorVersion: "tests",
    runtimeHints: RuntimeHints(
      maxLiteralLength: 0,
      maxBoundedRuleWidth: 4,
      maxDeterministicLookaheadBytes: 4
    ),
    tokenKinds: [
      TokenKindDecl(tokenKindID: 1, name: "tok1", defaultMode: .emit)
    ],
    byteToClass: Array(repeating: 0, count: 256),
    classes: [ByteClassDecl(classID: 0, bytes: [0])],
    classSets: [ClassSetDecl(classSetID: ClassSetID(0), classes: [0])],
    rules: [
      LoweredRule(
        ruleID: 9,
        name: "window",
        tokenKindID: 1,
        mode: .emit,
        family: .localWindow,
        priorityRank: 0,
        minWidth: 1,
        maxWidth: 2,
        firstClassSetID: 0,
        plan: .localWindow(maxWidth: 2)
      )
    ],
    keywordRemaps: []
  )
}

private func buildArtifact(from spec: LexerSpec, options: CompileOptions) throws -> LexerArtifact {
  let validated = try NormalizedSpec.validate(
    DeclaredSpec.normalize(spec.declare()),
    options: options
  )
  let byteClasses = validated.buildByteClasses()
  let classSets = validated.buildClassSets(using: byteClasses)
  let classified = try validated.classifyRules(
    byteClasses: byteClasses,
    classSets: classSets,
    options: options
  )
  return try ArtifactSerializer.build(
    classified: classified,
    byteClasses: byteClasses,
    classSets: classSets,
    generatorVersion: "test"
  )
}
