import Foundation
import MicroSwiftLexerGen
import Testing

@testable import MicroSwiftTensorCore

@Suite
struct KeywordRemapTests {
  @Test(.enabled(if: requiresMLXEval))
  func funcIdentifierRemappedToFuncKeywordKind() {
    let tokens: [GreedySelector.SelectedToken] = [
      .init(startPos: 0, length: 4, ruleID: 7, tokenKindID: 100, mode: 0)
    ]
    let bytes = Array("func".utf8)
    let tables = [
      table(baseRuleID: 7, maxKeywordLength: 4, entries: [([102, 117, 110, 99], 200)])
    ]

    let remapped = KeywordRemap.apply(tokens: tokens, bytes: bytes, remapTables: tables)

    #expect(
      remapped == [
        .init(startPos: 0, length: 4, ruleID: 7, tokenKindID: 200, mode: 0)
      ])
  }

  @Test(.enabled(if: requiresMLXEval))
  func letIdentifierRemappedToLetKeywordKind() {
    let tokens: [GreedySelector.SelectedToken] = [
      .init(startPos: 0, length: 3, ruleID: 7, tokenKindID: 100, mode: 0)
    ]
    let bytes = Array("let".utf8)
    let tables = [
      table(baseRuleID: 7, maxKeywordLength: 4, entries: [([108, 101, 116], 201)])
    ]

    let remapped = KeywordRemap.apply(tokens: tokens, bytes: bytes, remapTables: tables)

    #expect(
      remapped == [
        .init(startPos: 0, length: 3, ruleID: 7, tokenKindID: 201, mode: 0)
      ])
  }

  @Test(.enabled(if: requiresMLXEval))
  func nonKeywordIdentifierUnchanged() {
    let tokens: [GreedySelector.SelectedToken] = [
      .init(startPos: 0, length: 3, ruleID: 7, tokenKindID: 100, mode: 0)
    ]
    let bytes = Array("foo".utf8)
    let tables = [
      table(baseRuleID: 7, maxKeywordLength: 4, entries: [([108, 101, 116], 201)])
    ]

    let remapped = KeywordRemap.apply(tokens: tokens, bytes: bytes, remapTables: tables)

    #expect(remapped == tokens)
  }

  @Test(.enabled(if: requiresMLXEval))
  func tokenFromWrongRuleNotCheckedAgainstRemapTable() {
    let tokens: [GreedySelector.SelectedToken] = [
      .init(startPos: 0, length: 4, ruleID: 8, tokenKindID: 100, mode: 0)
    ]
    let bytes = Array("func".utf8)
    let tables = [
      table(baseRuleID: 7, maxKeywordLength: 4, entries: [([102, 117, 110, 99], 200)])
    ]

    let remapped = KeywordRemap.apply(tokens: tokens, bytes: bytes, remapTables: tables)

    #expect(remapped == tokens)
  }

  @Test(.enabled(if: requiresMLXEval))
  func tokenLongerThanMaxKeywordLengthNotChecked() {
    let tokens: [GreedySelector.SelectedToken] = [
      .init(startPos: 0, length: 8, ruleID: 7, tokenKindID: 100, mode: 0)
    ]
    let bytes = Array("function".utf8)
    let tables = [
      table(
        baseRuleID: 7, maxKeywordLength: 4,
        entries: [([102, 117, 110, 99, 116, 105, 111, 110], 200)])
    ]

    let remapped = KeywordRemap.apply(tokens: tokens, bytes: bytes, remapTables: tables)

    #expect(remapped == tokens)
  }

  @Test(.enabled(if: requiresMLXEval))
  func multipleRemapTablesAppliedInArtifactOrder() {
    let tokens: [GreedySelector.SelectedToken] = [
      .init(startPos: 0, length: 4, ruleID: 7, tokenKindID: 100, mode: 0)
    ]
    let bytes = Array("func".utf8)
    let tables = [
      table(baseRuleID: 7, maxKeywordLength: 4, entries: [([102, 117, 110, 99], 200)]),
      table(baseRuleID: 7, maxKeywordLength: 4, entries: [([102, 117, 110, 99], 201)]),
    ]

    let remapped = KeywordRemap.apply(tokens: tokens, bytes: bytes, remapTables: tables)

    #expect(
      remapped == [
        .init(startPos: 0, length: 4, ruleID: 7, tokenKindID: 201, mode: 0)
      ])
  }

  private func table(
    baseRuleID: UInt16,
    maxKeywordLength: UInt8,
    entries: [([UInt8], UInt16)]
  ) -> KeywordRemapTable {
    let payload = TablePayload(
      baseRuleID: baseRuleID,
      baseTokenKindID: 100,
      maxKeywordLength: maxKeywordLength,
      entries: entries.map { lexeme, tokenKindID in
        EntryPayload(lexeme: lexeme, tokenKindID: tokenKindID)
      }
    )
    let data = try! JSONEncoder().encode(payload)
    return try! JSONDecoder().decode(KeywordRemapTable.self, from: data)
  }

  private struct TablePayload: Codable {
    let baseRuleID: UInt16
    let baseTokenKindID: UInt16
    let maxKeywordLength: UInt8
    let entries: [EntryPayload]
  }

  private struct EntryPayload: Codable {
    let lexeme: [UInt8]
    let tokenKindID: UInt16
  }
}
