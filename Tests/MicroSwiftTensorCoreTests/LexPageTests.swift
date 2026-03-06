import Testing

@testable import MicroSwiftLexerGen
@testable import MicroSwiftTensorCore

@Suite
struct LexPageTests {
  @Test
  func lexPageIntegratesFallbackWinnersInV1Profile() throws {
    let runtime = try makeRuntime(maxLookahead: 8)
    let bytes = Array("aa".utf8)

    let result = lexPage(
      bytes: bytes,
      validLen: Int32(bytes.count),
      baseOffset: 0,
      artifact: runtime,
      options: LexOptions(runtimeProfile: .v1Fallback)
    )

    #expect(result.rowCount == 1)
    #expect(result.packedRows.count == 1)
    #expect(result.packedRows[0] != 0)
  }

  @Test
  func lexPageSkipsFallbackInV0Profile() throws {
    let runtime = try makeRuntime(maxLookahead: 8)
    let bytes = Array("aa".utf8)

    let result = lexPage(
      bytes: bytes,
      validLen: Int32(bytes.count),
      baseOffset: 0,
      artifact: runtime,
      options: LexOptions(runtimeProfile: .v0)
    )

    #expect(result.rowCount == 0)
    #expect(result.packedRows.isEmpty)
  }

  @Test
  func lexShellThrowsOverflowWhenPageCapacityExceeded() throws {
    let runtime = try makeRuntime(maxLookahead: 4)
    let shell = LexShell()

    #expect(throws: LexShellError.pageOverflow(actual: 5, max: 4)) {
      _ = try shell.lexFile(
        bytes: Array("aaaaa".utf8),
        artifact: runtime,
        options: LexOptions(runtimeProfile: .v1Fallback)
      )
    }
  }

  @Test
  func lexShellPadsUnusedRowsDeterministically() throws {
    let runtime = try makeRuntime(maxLookahead: 8)
    let shell = LexShell()

    let first = try shell.lexFile(
      bytes: Array("aa".utf8),
      artifact: runtime,
      options: LexOptions(runtimeProfile: .v1Fallback)
    )
    let second = try shell.lexFile(
      bytes: Array("aa".utf8),
      artifact: runtime,
      options: LexOptions(runtimeProfile: .v1Fallback)
    )

    let page = try #require(first.first)
    #expect(page.rowCount == 1)
    #expect(page.packedRows.count == 8)
    #expect(page.packedRows[1...] == Array(repeating: UInt64(0), count: 7)[...])
    #expect(first == second)
  }
}

private func makeRuntime(maxLookahead: UInt16) throws -> ArtifactRuntime {
  let rule = LoweredRule(
    ruleID: 1,
    name: "a-fallback",
    tokenKindID: 9,
    mode: .emit,
    family: .fallback,
    priorityRank: 0,
    minWidth: 1,
    maxWidth: 8,
    firstClassSetID: 0,
    plan: .fallback(
      stateCount: 3,
      classCount: 1,
      transitionRowStride: 1,
      startState: 0,
      acceptingStates: [1, 2],
      transitions: [
        1,
        2,
        2,
      ]
    )
  )

  var byteToClass = Array(repeating: UInt8(0), count: 256)
  byteToClass[Int(Character("a").asciiValue!)] = 0

  let artifact = LexerArtifact(
    formatVersion: 1,
    specName: "lex-page-tests",
    specHashHex: String(repeating: "0", count: 64),
    generatorVersion: "tests",
    runtimeHints: RuntimeHints(
      maxLiteralLength: 0,
      maxBoundedRuleWidth: maxLookahead,
      maxDeterministicLookaheadBytes: maxLookahead
    ),
    tokenKinds: [
      TokenKindDecl(tokenKindID: 9, name: "tok9", defaultMode: .emit)
    ],
    byteToClass: byteToClass,
    classes: [ByteClassDecl(classID: 0, bytes: [Character("a").asciiValue!])],
    classSets: [ClassSetDecl(classSetID: ClassSetID(0), classes: [0])],
    rules: [rule],
    keywordRemaps: []
  )

  return try ArtifactRuntime.fromArtifact(artifact)
}
