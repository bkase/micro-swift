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
    let row = unpackRow(result.packedRows[0])
    #expect(row.startByte == 0)
    #expect(row.len == 2)
    #expect(row.tokenKindID == 9)
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
  func lexShellPagesWhenPageCapacityExceeded() throws {
    let runtime = try makeRuntime(maxLookahead: 4)
    let shell = LexShell()

    let results = try shell.lexFile(
      bytes: Array("aaaaa".utf8),
      artifact: runtime,
      options: LexOptions(runtimeProfile: .v1Fallback)
    )

    #expect(results.count == 2)
    #expect(results[0].rowCount == 1)
    #expect(results[0].packedRows.count == 4)
    #expect(results[1].rowCount == 1)
    #expect(results[1].packedRows.count == 4)
    #expect(results[1].packedRows[1...] == Array(repeating: UInt64(0), count: 3)[...])
  }

  @Test
  func lexShellUsesBaseOffsetsAcrossMultiplePages() throws {
    let runtime = try makeRuntime(maxLookahead: 4)
    let shell = LexShell()

    let results = try shell.lexFile(
      bytes: Array("aaaaaaaa".utf8),
      artifact: runtime,
      options: LexOptions(runtimeProfile: .v1Fallback)
    )

    #expect(results.count == 2)
    #expect(results[0].rowCount == 1)
    #expect(results[1].rowCount == 1)
    #expect(unpackStartByte(results[0].packedRows[0]) == 0)
    #expect(unpackStartByte(results[1].packedRows[0]) == 4)
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

  @Test
  func lexPageRetainsFull16BitTokenKindIDInPackedRows() throws {
    let runtime = try makeRuntime(maxLookahead: 8, tokenKindID: 300)
    let bytes = Array("aa".utf8)

    let result = lexPage(
      bytes: bytes,
      validLen: Int32(bytes.count),
      baseOffset: 0,
      artifact: runtime,
      options: LexOptions(runtimeProfile: .v1Fallback)
    )

    #expect(result.rowCount == 1)
    let row = unpackRow(try #require(result.packedRows.first))
    #expect(row.tokenKindID == 300)
    #expect(row.len == 2)
  }
}

private func makeRuntime(maxLookahead: UInt16, tokenKindID: UInt16 = 9) throws -> ArtifactRuntime {
  let rule = LoweredRule(
    ruleID: 1,
    name: "a-fallback",
    tokenKindID: tokenKindID,
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
      TokenKindDecl(tokenKindID: tokenKindID, name: "tok\(tokenKindID)", defaultMode: .emit)
    ],
    byteToClass: byteToClass,
    classes: [ByteClassDecl(classID: 0, bytes: [Character("a").asciiValue!])],
    classSets: [ClassSetDecl(classSetID: ClassSetID(0), classes: [0])],
    rules: [rule],
    keywordRemaps: []
  )

  return try ArtifactRuntime.fromArtifact(artifact)
}

private func unpackStartByte(_ packedRow: UInt64) -> UInt64 {
  packedRow >> 32
}

private func unpackRow(_ packed: UInt64) -> (startByte: UInt32, len: UInt16, tokenKindID: UInt16) {
  (
    startByte: UInt32((packed >> 32) & 0xFFFF_FFFF),
    len: UInt16((packed >> 16) & 0xFFFF),
    tokenKindID: UInt16(packed & 0xFFFF)
  )
}
