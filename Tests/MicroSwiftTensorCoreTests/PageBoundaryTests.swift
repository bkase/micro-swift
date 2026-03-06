import Foundation
import MicroSwiftFrontend
import MicroSwiftLexerGen
import Testing

@testable import MicroSwiftTensorCore

@Suite
struct PageBoundaryTests {
  @Test
  func eqEqAtPageEdge() throws {
    let fixture = try lexWithTinyPaging(input: "x==\nlet a = 1\n", emitSkipTokens: false)

    #expect(fixture.pages.count == 2)
    #expect(fixture.pages[0].sourcePage.end.rawValue == 4)
    #expect(fixture.tokens == [
      .init(kind: "ident", lexeme: "x", start: 0, end: 1),
      .init(kind: "eqEq", lexeme: "==", start: 1, end: 3),
      .init(kind: "kwLet", lexeme: "let", start: 4, end: 7),
      .init(kind: "ident", lexeme: "a", start: 8, end: 9),
      .init(kind: "eq", lexeme: "=", start: 10, end: 11),
      .init(kind: "int", lexeme: "1", start: 12, end: 13),
    ])
    #expect(fixture.errorSpans.isEmpty)
    #expect(fixture.overflows.isEmpty)
  }

  @Test
  func arrowAtPageEdge() throws {
    let fixture = try lexWithTinyPaging(input: "f->\nlet b = 2\n", emitSkipTokens: false)

    #expect(fixture.pages.count == 2)
    #expect(fixture.pages[0].sourcePage.end.rawValue == 4)
    #expect(fixture.tokens == [
      .init(kind: "ident", lexeme: "f", start: 0, end: 1),
      .init(kind: "arrow", lexeme: "->", start: 1, end: 3),
      .init(kind: "kwLet", lexeme: "let", start: 4, end: 7),
      .init(kind: "ident", lexeme: "b", start: 8, end: 9),
      .init(kind: "eq", lexeme: "=", start: 10, end: 11),
      .init(kind: "int", lexeme: "2", start: 12, end: 13),
    ])
    #expect(fixture.errorSpans.isEmpty)
    #expect(fixture.overflows.isEmpty)
  }

  @Test
  func identifierEndingExactlyAtPageBoundary() throws {
    let fixture = try lexWithTinyPaging(input: "boundary", emitSkipTokens: false)

    #expect(fixture.pages.count == 1)
    #expect(fixture.pages[0].validLen == 8)
    #expect(fixture.pages[0].bucket?.byteCapacity == 8)
    #expect(fixture.tokens == [
      .init(kind: "ident", lexeme: "boundary", start: 0, end: 8)
    ])
    #expect(fixture.tokens[0].end == fixture.pages[0].sourcePage.end.rawValue)
  }

  @Test
  func integerEndingExactlyAtPageBoundary() throws {
    let fixture = try lexWithTinyPaging(input: "12345678", emitSkipTokens: false)

    #expect(fixture.pages.count == 1)
    #expect(fixture.pages[0].validLen == 8)
    #expect(fixture.pages[0].bucket?.byteCapacity == 8)
    #expect(fixture.tokens == [
      .init(kind: "int", lexeme: "12345678", start: 0, end: 8)
    ])
    #expect(fixture.tokens[0].end == fixture.pages[0].sourcePage.end.rawValue)
  }

  @Test
  func whitespaceSpanningNewlineCut() throws {
    let fixture = try lexWithTinyPaging(input: "x \n   yyyyy\n", emitSkipTokens: true)

    #expect(fixture.pages.count == 2)
    #expect(fixture.pages[0].sourcePage.end.rawValue == 3)
    #expect(fixture.tokens == [
      .init(kind: "ident", lexeme: "x", start: 0, end: 1),
      .init(kind: "ws", lexeme: " \n", start: 1, end: 3),
      .init(kind: "ws", lexeme: "   ", start: 3, end: 6),
      .init(kind: "ident", lexeme: "yyyyy", start: 6, end: 11),
      .init(kind: "ws", lexeme: "\n", start: 11, end: 12),
    ])
    #expect(fixture.errorSpans.isEmpty)
    #expect(fixture.overflows.isEmpty)
  }

  @Test
  func lineCommentEndingJustBeforeCut() throws {
    let fixture = try lexWithTinyPaging(input: "//a\nlet d = 4\n", emitSkipTokens: true)

    #expect(fixture.pages.count == 2)
    #expect(fixture.pages[0].sourcePage.end.rawValue == 4)
    #expect(fixture.tokens == [
      .init(kind: "lineComment", lexeme: "//a", start: 0, end: 3),
      .init(kind: "ws", lexeme: "\n", start: 3, end: 4),
      .init(kind: "kwLet", lexeme: "let", start: 4, end: 7),
      .init(kind: "ws", lexeme: " ", start: 7, end: 8),
      .init(kind: "ident", lexeme: "d", start: 8, end: 9),
      .init(kind: "ws", lexeme: " ", start: 9, end: 10),
      .init(kind: "eq", lexeme: "=", start: 10, end: 11),
      .init(kind: "ws", lexeme: " ", start: 11, end: 12),
      .init(kind: "int", lexeme: "4", start: 12, end: 13),
      .init(kind: "ws", lexeme: "\n", start: 13, end: 14),
    ])
    #expect(fixture.errorSpans.isEmpty)
    #expect(fixture.overflows.isEmpty)
  }

  @Test
  func longLineCommentUsesLargerBucket() throws {
    let fixture = try lexWithTinyPaging(input: "//1234567890\n", emitSkipTokens: true)

    #expect(fixture.pages.count == 1)
    #expect(fixture.pages[0].validLen == 13)
    #expect(fixture.pages[0].bucket?.byteCapacity == 16)
    #expect(fixture.tokens == [
      .init(kind: "lineComment", lexeme: "//1234567890", start: 0, end: 12),
      .init(kind: "ws", lexeme: "\n", start: 12, end: 13),
    ])
    #expect(fixture.errorSpans.isEmpty)
    #expect(fixture.overflows.isEmpty)
  }

  @Test
  func overlongLineExceedingLargestBucketOverflows() throws {
    let fixture = try lexWithTinyPaging(input: "//aaaaaaaaaaaaaaaaaaaa\n", emitSkipTokens: true)

    #expect(fixture.pages.count == 1)
    #expect(fixture.pages[0].bucket == nil)
    #expect(fixture.tokens.isEmpty)
    #expect(fixture.errorSpans.isEmpty)
    #expect(fixture.overflows.count == 1)
    #expect(fixture.overflows[0].message == "lex-page-overflow: line exceeds maximum supported page bucket")
    #expect(fixture.overflows[0].pageByteCount == fixture.pages[0].validLen)
    #expect(fixture.overflows[0].maxBucketSize == 16)
  }

  private func lexWithTinyPaging(input: String, emitSkipTokens: Bool) throws -> BoundaryFixture {
    let bytes = [UInt8](input.utf8)
    let source = SourceBuffer(
      fileID: FileID(rawValue: 1),
      path: "boundary.swift",
      bytes: Data(bytes)
    )

    let runtime = try makeMicroSwiftRuntime()
    let pagingShell = PagingShell(
      pagePolicy: PagePolicy(targetBytes: 8),
      maxBucketSize: 16,
      buckets: [PageBucket(byteCapacity: 8), PageBucket(byteCapacity: 16)]
    )
    let shell = LexingShell(pagingShell: pagingShell)
    let result = shell.lexSource(
      source: source,
      artifact: runtime,
      options: LexOptions(emitSkipTokens: emitSkipTokens)
    )

    let kindByID = Dictionary(uniqueKeysWithValues: runtime.tokenKinds.map { ($0.tokenKindID, $0.name) })
    let tokens = result.tokenTape.tokens.map { token in
      BoundaryToken(
        kind: kindByID[token.kind] ?? "<unknown>",
        lexeme: String(decoding: bytes[Int(token.startByte)..<Int(token.endByte)], as: UTF8.self),
        start: token.startByte,
        end: token.endByte
      )
    }

    return BoundaryFixture(
      pages: pagingShell.planAndPreparePages(source: source),
      tokens: tokens,
      errorSpans: result.tokenTape.errorSpans,
      overflows: result.tokenTape.overflows
    )
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

private struct BoundaryFixture {
  let pages: [PreparedPage]
  let tokens: [BoundaryToken]
  let errorSpans: [ErrorSpan]
  let overflows: [OverflowDiagnostic]
}

private struct BoundaryToken: Equatable {
  let kind: String
  let lexeme: String
  let start: Int64
  let end: Int64
}
