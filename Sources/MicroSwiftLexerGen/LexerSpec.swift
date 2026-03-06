/// A typed handle returned by `identifier()` for use in `keywords(for:)`.
public struct IdentifierRuleHandle: Sendable {
  public let kindName: String
  public let regex: RawRegex
  public let span: SpecSpan
}

/// An entry in a keyword block.
public struct KeywordEntry: Sendable, Equatable {
  public let lexeme: String
  public let kindName: String
  public let span: SpecSpan
}

/// The top-level lexer specification value.
public struct LexerSpec: Sendable {
  public let name: String
  public let rules: [RuleDecl]
  public let keywordBlocks: [KeywordBlockDecl]

  public init(name: String, @LexerSpecBuilder build: () -> LexerSpecContent) {
    self.name = name
    let content = build()
    self.rules = content.rules
    self.keywordBlocks = content.keywordBlocks
  }
}

/// A rule declaration from the DSL.
public struct RuleDecl: Sendable, Equatable {
  public let kindName: String
  public let mode: RuleMode
  public let role: RuleRole
  public let regex: RawRegex
  public let span: SpecSpan
}

/// A keyword block declaration from the DSL.
public struct KeywordBlockDecl: Sendable, Equatable {
  public let baseKindName: String
  public let baseRegex: RawRegex
  public let baseSpan: SpecSpan
  public let entries: [KeywordEntry]
  public let span: SpecSpan
}

/// Content produced by the LexerSpec builder.
public struct LexerSpecContent: Sendable {
  public var rules: [RuleDecl]
  public var keywordBlocks: [KeywordBlockDecl]

  public init(rules: [RuleDecl] = [], keywordBlocks: [KeywordBlockDecl] = []) {
    self.rules = rules
    self.keywordBlocks = keywordBlocks
  }
}

// MARK: - Result builder

@resultBuilder
public struct LexerSpecBuilder {
  public static func buildBlock(_ components: LexerSpecContent...) -> LexerSpecContent {
    var result = LexerSpecContent()
    for c in components {
      result.rules.append(contentsOf: c.rules)
      result.keywordBlocks.append(contentsOf: c.keywordBlocks)
    }
    return result
  }

  public static func buildExpression(_ content: LexerSpecContent) -> LexerSpecContent {
    content
  }
}

// MARK: - DSL functions

/// Declare a token rule.
public func token(
  _ kindName: String,
  _ regex: RawRegex,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column
) -> LexerSpecContent {
  let rule = RuleDecl(
    kindName: kindName,
    mode: .emit,
    role: .token,
    regex: regex,
    span: SpecSpan(fileID: fileID, line: line, column: column)
  )
  return LexerSpecContent(rules: [rule])
}

/// Declare a skip rule.
public func skip(
  _ kindName: String,
  _ regex: RawRegex,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column
) -> LexerSpecContent {
  let rule = RuleDecl(
    kindName: kindName,
    mode: .skip,
    role: .skip,
    regex: regex,
    span: SpecSpan(fileID: fileID, line: line, column: column)
  )
  return LexerSpecContent(rules: [rule])
}

/// Declare an identifier-like rule handle for use in `keywords(for:)`.
public func identifier(
  _ kindName: String,
  _ regex: RawRegex,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column
) -> IdentifierRuleHandle {
  IdentifierRuleHandle(
    kindName: kindName,
    regex: regex,
    span: SpecSpan(fileID: fileID, line: line, column: column)
  )
}

/// Attach a keyword remap table to an identifier rule.
/// This emits both the base identifier rule and the keyword block.
public func keywords(
  for identifierRule: IdentifierRuleHandle,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  @KeywordBlockBuilder build: () -> [KeywordEntry]
) -> LexerSpecContent {
  let rule = RuleDecl(
    kindName: identifierRule.kindName,
    mode: .emit,
    role: .identifier,
    regex: identifierRule.regex,
    span: identifierRule.span
  )
  let block = KeywordBlockDecl(
    baseKindName: identifierRule.kindName,
    baseRegex: identifierRule.regex,
    baseSpan: identifierRule.span,
    entries: build(),
    span: SpecSpan(fileID: fileID, line: line, column: column)
  )
  return LexerSpecContent(rules: [rule], keywordBlocks: [block])
}

/// Declare a keyword entry inside a keywords block.
public func keyword(
  _ lexeme: String,
  as kindName: String,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column
) -> KeywordEntry {
  precondition(lexeme.allSatisfy(\.isASCII), "keyword lexemes must be ASCII")
  return KeywordEntry(
    lexeme: lexeme,
    kindName: kindName,
    span: SpecSpan(fileID: fileID, line: line, column: column)
  )
}

/// Keyword block builder.
@resultBuilder
public struct KeywordBlockBuilder {
  public static func buildBlock(_ entries: KeywordEntry...) -> [KeywordEntry] {
    entries
  }
}
