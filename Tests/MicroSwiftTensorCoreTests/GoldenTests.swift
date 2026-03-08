import Foundation
import MicroSwiftFrontend
import MicroSwiftLexerGen
import Testing

@testable import MicroSwiftTensorCore

@Suite
struct GoldenTests {
  @Test(.enabled(if: requiresMLXEval))
  func letAssignmentGolden() throws {
    let snapshot = try lexSnapshot(input: "let x = 42\n", emitSkipTokens: true)

    #expect(
      snapshot.tokens == [
        .init(kind: "kwLet", lexeme: "let", start: 0, end: 3, flags: 0),
        .init(kind: "ws", lexeme: " ", start: 3, end: 4, flags: 1),
        .init(kind: "ident", lexeme: "x", start: 4, end: 5, flags: 0),
        .init(kind: "ws", lexeme: " ", start: 5, end: 6, flags: 1),
        .init(kind: "eq", lexeme: "=", start: 6, end: 7, flags: 0),
        .init(kind: "ws", lexeme: " ", start: 7, end: 8, flags: 1),
        .init(kind: "int", lexeme: "42", start: 8, end: 10, flags: 0),
        .init(kind: "ws", lexeme: "\n", start: 10, end: 11, flags: 1),
      ])
    #expect(snapshot.errorSpans.isEmpty)
    #expect(snapshot.overflows.isEmpty)
  }

  @Test(.enabled(if: requiresMLXEval))
  func functionSignatureAndBodyGolden() throws {
    let snapshot = try lexSnapshot(input: "func foo() -> Int { return 1 }\n", emitSkipTokens: true)

    #expect(
      snapshot.tokens == [
        .init(kind: "kwFunc", lexeme: "func", start: 0, end: 4, flags: 0),
        .init(kind: "ws", lexeme: " ", start: 4, end: 5, flags: 1),
        .init(kind: "ident", lexeme: "foo", start: 5, end: 8, flags: 0),
        .init(kind: "lParen", lexeme: "(", start: 8, end: 9, flags: 0),
        .init(kind: "rParen", lexeme: ")", start: 9, end: 10, flags: 0),
        .init(kind: "ws", lexeme: " ", start: 10, end: 11, flags: 1),
        .init(kind: "arrow", lexeme: "->", start: 11, end: 13, flags: 0),
        .init(kind: "ws", lexeme: " ", start: 13, end: 14, flags: 1),
        .init(kind: "ident", lexeme: "Int", start: 14, end: 17, flags: 0),
        .init(kind: "ws", lexeme: " ", start: 17, end: 18, flags: 1),
        .init(kind: "lBrace", lexeme: "{", start: 18, end: 19, flags: 0),
        .init(kind: "ws", lexeme: " ", start: 19, end: 20, flags: 1),
        .init(kind: "kwReturn", lexeme: "return", start: 20, end: 26, flags: 0),
        .init(kind: "ws", lexeme: " ", start: 26, end: 27, flags: 1),
        .init(kind: "int", lexeme: "1", start: 27, end: 28, flags: 0),
        .init(kind: "ws", lexeme: " ", start: 28, end: 29, flags: 1),
        .init(kind: "rBrace", lexeme: "}", start: 29, end: 30, flags: 0),
        .init(kind: "ws", lexeme: "\n", start: 30, end: 31, flags: 1),
      ])
    #expect(snapshot.errorSpans.isEmpty)
    #expect(snapshot.overflows.isEmpty)
  }

  @Test(.enabled(if: requiresMLXEval))
  func commentThenDeclarationGolden() throws {
    let snapshot = try lexSnapshot(input: "// comment\nlet y = 0\n", emitSkipTokens: true)

    #expect(
      snapshot.tokens == [
        .init(kind: "lineComment", lexeme: "// comment", start: 0, end: 10, flags: 1),
        .init(kind: "ws", lexeme: "\n", start: 10, end: 11, flags: 1),
        .init(kind: "kwLet", lexeme: "let", start: 11, end: 14, flags: 0),
        .init(kind: "ws", lexeme: " ", start: 14, end: 15, flags: 1),
        .init(kind: "ident", lexeme: "y", start: 15, end: 16, flags: 0),
        .init(kind: "ws", lexeme: " ", start: 16, end: 17, flags: 1),
        .init(kind: "eq", lexeme: "=", start: 17, end: 18, flags: 0),
        .init(kind: "ws", lexeme: " ", start: 18, end: 19, flags: 1),
        .init(kind: "int", lexeme: "0", start: 19, end: 20, flags: 0),
        .init(kind: "ws", lexeme: "\n", start: 20, end: 21, flags: 1),
      ])
    #expect(snapshot.errorSpans.isEmpty)
    #expect(snapshot.overflows.isEmpty)
  }

  @Test(.enabled(if: requiresMLXEval))
  func overlapResolutionGolden() throws {
    let snapshot = try lexSnapshot(input: "===>", emitSkipTokens: false)

    #expect(
      snapshot.tokens == [
        .init(kind: "eqEq", lexeme: "==", start: 0, end: 2, flags: 0),
        .init(kind: "eq", lexeme: "=", start: 2, end: 3, flags: 0),
      ])
    #expect(snapshot.errorSpans == [ErrorSpan(start: 3, end: 4)])
    #expect(snapshot.overflows.isEmpty)
  }

  @Test(.enabled(if: requiresMLXEval))
  func deterministicAcrossRepeatedRuns() throws {
    let input = "func foo() -> Int { return 1 }\n"
    let first = try lexSnapshot(input: input, emitSkipTokens: true)

    for _ in 0..<10 {
      let next = try lexSnapshot(input: input, emitSkipTokens: true)
      #expect(next == first)
    }
  }

  private func lexSnapshot(input: String, emitSkipTokens: Bool) throws -> StreamSnapshot {
    let bytes = [UInt8](input.utf8)
    let source = SourceBuffer(
      fileID: FileID(rawValue: 1),
      path: "golden.swift",
      bytes: Data(bytes)
    )

    let runtime = try makeMicroSwiftRuntime()
    let result = LexingShell().lexSource(
      source: source,
      artifact: runtime,
      options: LexOptions(emitSkipTokens: emitSkipTokens)
    )

    let kindByID = Dictionary(
      uniqueKeysWithValues: runtime.tokenKinds.map { ($0.tokenKindID, $0.name) })
    let tokens = result.tokenTape.tokens.map { token in
      TokenSnapshot(
        kind: kindByID[token.kind] ?? "<unknown>",
        lexeme: String(decoding: bytes[Int(token.startByte)..<Int(token.endByte)], as: UTF8.self),
        start: token.startByte,
        end: token.endByte,
        flags: token.flags
      )
    }

    return StreamSnapshot(
      tokens: tokens, errorSpans: result.tokenTape.errorSpans, overflows: result.tokenTape.overflows
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

private struct StreamSnapshot: Equatable {
  let tokens: [TokenSnapshot]
  let errorSpans: [ErrorSpan]
  let overflows: [OverflowDiagnostic]
}

private struct TokenSnapshot: Equatable {
  let kind: String
  let lexeme: String
  let start: Int64
  let end: Int64
  let flags: UInt8
}
