import Testing

@testable import MicroSwiftFrontend
@testable import MicroSwiftLexerGen
@testable import MicroSwiftTensorCore

@Suite
struct LexPageTests {
  @Test(.enabled(if: requiresMLXEval))
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

  @Test(.enabled(if: requiresMLXEval))
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

  @Test(.enabled(if: requiresMLXEval))
  func lexShellPagesWhenPageCapacityExceeded() throws {
    let runtime = try makeRuntime(maxLookahead: 4)
    let shell = makeShell(targetBytes: 3, bucketBytes: 4)

    let results = try shell.lexFile(
      bytes: Array("aa\naa\n".utf8),
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

  @Test(.enabled(if: requiresMLXEval))
  func lexShellUsesBaseOffsetsAcrossMultiplePages() throws {
    let runtime = try makeRuntime(maxLookahead: 4)
    let shell = makeShell(targetBytes: 3, bucketBytes: 4)

    let results = try shell.lexFile(
      bytes: Array("aa\naa\n".utf8),
      artifact: runtime,
      options: LexOptions(runtimeProfile: .v1Fallback)
    )

    #expect(results.count == 2)
    #expect(results[0].rowCount == 1)
    #expect(results[1].rowCount == 1)
    let firstPageTokens = TokenUnpacker.unpack(result: results[0], baseOffset: 0)
    let secondPageTokens = TokenUnpacker.unpack(result: results[1], baseOffset: 3)
    #expect(firstPageTokens.map(\.startByte) == [0])
    #expect(secondPageTokens.map(\.startByte) == [3])
  }

  @Test(.enabled(if: requiresMLXEval))
  func lexShellPadsUnusedRowsDeterministically() throws {
    let runtime = try makeRuntime(maxLookahead: 8)
    let shell = makeShell(targetBytes: 3, bucketBytes: 4)

    let first = try shell.lexFile(
      bytes: Array("aa\n".utf8),
      artifact: runtime,
      options: LexOptions(runtimeProfile: .v1Fallback)
    )
    let second = try shell.lexFile(
      bytes: Array("aa\n".utf8),
      artifact: runtime,
      options: LexOptions(runtimeProfile: .v1Fallback)
    )

    let page = try #require(first.first)
    let packedRows = page.hostPackedRows()
    #expect(page.rowCount == 1)
    #expect(packedRows.count == 4)
    #expect(packedRows[1...] == Array(repeating: UInt64(0), count: 3)[...])
    #expect(first == second)
  }

  @Test(.enabled(if: requiresMLXEval))
  func lexShellReturnsOverflowDiagnosticForUnsupportedPage() throws {
    let runtime = try makeRuntime(maxLookahead: 8)
    let shell = makeShell(targetBytes: 3, bucketBytes: 4)

    let results = try shell.lexFile(
      bytes: Array("aaaaa".utf8),
      artifact: runtime,
      options: LexOptions(runtimeProfile: .v1Fallback)
    )

    #expect(results.count == 1)
    let page = try #require(results.first)
    #expect(page.rowCount == 0)
    #expect(page.hostPackedRows().isEmpty)
    let overflow = try #require(page.overflowDiagnostic)
    #expect(overflow.pageByteCount == 5)
    #expect(overflow.maxBucketSize == 4)
  }

  @Test(.enabled(if: requiresMLXEval))
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

  @Test(.enabled(if: requiresMLXEval))
  func lexPageIntegratesPrefixedCandidatesWithOtherFastRules() throws {
    let runtime = try makePrefixedLexRuntime()
    let bytes = Array("//ab\n".utf8)

    let result = lexPage(
      bytes: bytes,
      validLen: Int32(bytes.count),
      baseOffset: 0,
      artifact: runtime,
      options: LexOptions(runtimeProfile: .v0)
    )

    let packedRows = result.hostPackedRows()
    #expect(result.rowCount == 2)
    #expect(packedRows.count == bytes.count)

    let first = try #require(packedRows.first)
    #expect(PackedToken.unpackLocalStart(first) == 0)
    #expect(PackedToken.unpackLength(first) == 4)
    #expect(PackedToken.unpackTokenKindID(first) == 41)

    let second = packedRows[1]
    #expect(PackedToken.unpackLocalStart(second) == 4)
    #expect(PackedToken.unpackLength(second) == 1)
    #expect(PackedToken.unpackTokenKindID(second) == 42)
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

private func makePrefixedLexRuntime() throws -> ArtifactRuntime {
  var byteToClass = Array(repeating: UInt8(1), count: 256)
  byteToClass[Int(Character("/").asciiValue!)] = 0
  byteToClass[Int(Character("\n").asciiValue!)] = 2
  byteToClass[Int(Character(" ").asciiValue!)] = 3

  let rules = [
    LoweredRule(
      ruleID: 10,
      name: "line-comment",
      tokenKindID: 41,
      mode: .emit,
      family: .run,
      priorityRank: 0,
      minWidth: 2,
      maxWidth: nil,
      firstClassSetID: 0,
      plan: .runPrefixed(prefix: Array("//".utf8), bodyClassSetID: 0, stopClassSetID: 1)
    ),
    LoweredRule(
      ruleID: 11,
      name: "newline",
      tokenKindID: 42,
      mode: .emit,
      family: .literal,
      priorityRank: 1,
      minWidth: 1,
      maxWidth: 1,
      firstClassSetID: 1,
      plan: .literal(bytes: [UInt8(ascii: "\n")])
    ),
  ]

  let artifact = LexerArtifact(
    formatVersion: 1,
    specName: "prefixed-lex-tests",
    specHashHex: String(repeating: "0", count: 64),
    generatorVersion: "tests",
    runtimeHints: RuntimeHints(
      maxLiteralLength: 1,
      maxBoundedRuleWidth: 2,
      maxDeterministicLookaheadBytes: 2
    ),
    tokenKinds: [
      TokenKindDecl(tokenKindID: 41, name: "lineComment", defaultMode: .emit),
      TokenKindDecl(tokenKindID: 42, name: "newline", defaultMode: .emit),
    ],
    byteToClass: byteToClass,
    classes: [
      ByteClassDecl(classID: 0, bytes: [Character("/").asciiValue!]),
      ByteClassDecl(classID: 1, bytes: [Character("a").asciiValue!, Character("b").asciiValue!]),
      ByteClassDecl(classID: 2, bytes: [Character("\n").asciiValue!]),
      ByteClassDecl(classID: 3, bytes: [Character(" ").asciiValue!]),
    ],
    classSets: [
      ClassSetDecl(classSetID: ClassSetID(0), classes: [0, 1, 3]),
      ClassSetDecl(classSetID: ClassSetID(1), classes: [2]),
    ],
    rules: rules,
    keywordRemaps: []
  )

  return try ArtifactRuntime.fromArtifact(artifact)
}

private func makeShell(targetBytes: Int32, bucketBytes: Int32) -> LexShell {
  let pagingShell = PagingShell(
    pagePolicy: PagePolicy(targetBytes: targetBytes),
    maxBucketSize: bucketBytes,
    buckets: [PageBucket(byteCapacity: bucketBytes)]
  )
  return LexShell(lexingShell: LexingShell(pagingShell: pagingShell))
}

extension UInt64 {
  fileprivate var len: UInt16 {
    PackedToken.unpackLength(self)
  }
}
