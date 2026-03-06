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

    let packedRows = result.hostPackedRows()
    #expect(result.rowCount == 1)
    #expect(packedRows.count == 2)
    let row = try #require(packedRows.first)
    #expect(PackedToken.unpackLocalStart(row) == 0)
    #expect(row.len == 2)
    #expect(PackedToken.unpackTokenKindID(row) == 9)
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

    let packedRows = result.hostPackedRows()
    #expect(result.rowCount == 0)
    #expect(packedRows.allSatisfy { $0 == 0 })
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

    let page0PackedRows = results[0].hostPackedRows()
    let page1PackedRows = results[1].hostPackedRows()
    #expect(results.count == 2)
    #expect(results[0].rowCount == 1)
    #expect(page0PackedRows.count == 4)
    #expect(results[1].rowCount == 1)
    #expect(page1PackedRows.count == 4)
    #expect(page1PackedRows[1...] == Array(repeating: UInt64(0), count: 3)[...])
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
    let firstPageTokens = TokenUnpacker.unpack(result: results[0], baseOffset: 0)
    let secondPageTokens = TokenUnpacker.unpack(result: results[1], baseOffset: 4)
    #expect(firstPageTokens.map(\.startByte) == [0])
    #expect(secondPageTokens.map(\.startByte) == [4])
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
    let packedRows = page.hostPackedRows()
    #expect(page.rowCount == 1)
    #expect(packedRows.count == 8)
    #expect(packedRows[1...] == Array(repeating: UInt64(0), count: 7)[...])
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
    let row = try #require(result.hostPackedRows().first)
    #expect(PackedToken.unpackTokenKindID(row) == 300)
    #expect(PackedToken.unpackLength(row) == 2)
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

private extension UInt64 {
  var len: UInt16 {
    PackedToken.unpackLength(self)
  }
}
