import Testing

@testable import MicroSwiftLexerGen
@testable import MicroSwiftTensorCore

@Suite
struct V0CompatibilityTests {
  @Test(.enabled(if: requiresMLXEval))
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

    assertEquivalentProfiles(
      runtime: runtime,
      bytes: sample,
      v0: v0,
      v1: v1
    )

    let decoded = decodeOutput(result: v0, bytes: sample, runtime: runtime)
    #expect(
      decoded.tokens == [
        .init(start: 0, end: 3, kindName: "kwLet", lexeme: "let"),
        .init(start: 4, end: 9, kindName: "ident", lexeme: "alpha"),
        .init(start: 12, end: 14, kindName: "ident", lexeme: "42"),
      ])
    #expect(decoded.errorSpans == [.init(start: 3, end: 4), .init(start: 9, end: 12)])
    #expect(decoded.overflowDiagnostic == nil)
  }

  @Test(.enabled(if: requiresMLXEval))
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

    assertEquivalentProfiles(
      runtime: runtime,
      bytes: sample,
      v0: v0,
      v1: v1
    )

    let decoded = decodeOutput(result: v0, bytes: sample, runtime: runtime)
    #expect(
      decoded.tokens == [
        .init(start: 0, end: 4, kindName: "kwFunc", lexeme: "func"),
        .init(start: 5, end: 6, kindName: "ident", lexeme: "f"),
        .init(start: 6, end: 7, kindName: "lParen", lexeme: "("),
        .init(start: 7, end: 8, kindName: "ident", lexeme: "x"),
        .init(start: 8, end: 9, kindName: "colon", lexeme: ":"),
        .init(start: 10, end: 13, kindName: "ident", lexeme: "int"),
        .init(start: 13, end: 14, kindName: "rParen", lexeme: ")"),
        .init(start: 15, end: 17, kindName: "arrow", lexeme: "->"),
        .init(start: 18, end: 21, kindName: "ident", lexeme: "int"),
        .init(start: 22, end: 23, kindName: "lBrace", lexeme: "{"),
        .init(start: 24, end: 30, kindName: "kwReturn", lexeme: "return"),
        .init(start: 31, end: 32, kindName: "ident", lexeme: "x"),
        .init(start: 33, end: 34, kindName: "plus", lexeme: "+"),
        .init(start: 35, end: 36, kindName: "int", lexeme: "1"),
        .init(start: 37, end: 38, kindName: "rBrace", lexeme: "}"),
      ])
    #expect(decoded.errorSpans.isEmpty)
    #expect(decoded.overflowDiagnostic == nil)
  }

  @Test(.enabled(if: requiresMLXEval))
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

private func assertEquivalentProfiles(
  runtime: ArtifactRuntime,
  bytes: [UInt8],
  v0: PageLexResult,
  v1: PageLexResult
) {
  #expect(v0.rowCount == v1.rowCount)
  #expect(v0.hostPackedRows() == v1.hostPackedRows())
  #expect(v0.errorSpans == v1.errorSpans)
  #expect(v0.overflowDiagnostic == v1.overflowDiagnostic)
  #expect(
    TokenUnpacker.unpack(result: v0, baseOffset: 0)
      == TokenUnpacker.unpack(result: v1, baseOffset: 0))
  let decoded = decodeOutput(result: v0, bytes: bytes, runtime: runtime)
  #expect(!decoded.tokens.isEmpty || !decoded.errorSpans.isEmpty)
}

private struct DecodedToken: Equatable {
  let start: Int
  let end: Int
  let kindName: String
  let lexeme: String
}

private struct DecodedOutput: Equatable {
  let tokens: [DecodedToken]
  let errorSpans: [ErrorSpan]
  let overflowDiagnostic: OverflowDiagnostic?
}

private func decodeOutput(
  result: PageLexResult,
  bytes: [UInt8],
  runtime: ArtifactRuntime
) -> DecodedOutput {
  let kindByID = Dictionary(
    uniqueKeysWithValues: runtime.tokenKinds.map { ($0.tokenKindID, $0.name) })
  let tokens = TokenUnpacker.unpack(result: result, baseOffset: 0).map { token in
    let start = Int(token.startByte)
    let end = Int(token.endByte)
    return DecodedToken(
      start: start,
      end: end,
      kindName: kindByID[token.kind] ?? "<unknown>",
      lexeme: String(decoding: bytes[start..<end], as: UTF8.self)
    )
  }
  return DecodedOutput(
    tokens: tokens, errorSpans: result.errorSpans, overflowDiagnostic: result.overflowDiagnostic)
}

private func makeV0LikeArtifact() -> LexerArtifact {
  var byteToClass = Array(repeating: UInt8(2), count: 256)
  for byte in UInt8(97)...UInt8(122) {
    byteToClass[Int(byte)] = 1
  }
  for byte in UInt8(48)...UInt8(57) {
    byteToClass[Int(byte)] = 1
  }
  byteToClass[Int(Character("_").asciiValue!)] = 1
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
      ByteClassDecl(
        classID: 1,
        bytes: Array("abcdefghijklmnopqrstuvwxyz0123456789_".utf8)
      ),
      ByteClassDecl(classID: 2, bytes: [0]),
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
