/// The typed declared specification after DSL construction.
/// This is the first stage of the one-way pipeline.
public struct DeclaredSpec: Sendable, Equatable {
  public let name: String
  public let rules: [DeclaredRule]
  public let keywordBlocks: [DeclaredKeywordBlock]
}

public struct DeclaredRule: Sendable, Equatable {
  public let declaredKindName: String
  public let mode: RuleMode
  public let role: RuleRole
  public let regex: RawRegex
  public let sourceSpan: SpecSpan
}

public struct DeclaredKeywordBlock: Sendable, Equatable {
  public let baseKindName: String
  public let entries: [DeclaredKeywordEntry]
  public let sourceSpan: SpecSpan
}

public struct DeclaredKeywordEntry: Sendable, Equatable {
  public let lexeme: String
  public let lexemeBytes: [UInt8]
  public let kindName: String
  public let sourceSpan: SpecSpan
}

// MARK: - Declaration lowering

extension LexerSpec {
  /// Lower the DSL spec into a typed declared IR.
  public func declare() -> DeclaredSpec {
    let declaredRules = rules.map { rule in
      DeclaredRule(
        declaredKindName: rule.kindName,
        mode: rule.mode,
        role: rule.role,
        regex: rule.regex,
        sourceSpan: rule.span
      )
    }

    let declaredKeywordBlocks = keywordBlocks.map { block in
      DeclaredKeywordBlock(
        baseKindName: block.baseKindName,
        entries: block.entries.map { entry in
          DeclaredKeywordEntry(
            lexeme: entry.lexeme,
            lexemeBytes: Array(entry.lexeme.utf8),
            kindName: entry.kindName,
            sourceSpan: entry.span
          )
        },
        sourceSpan: block.span
      )
    }

    return DeclaredSpec(
      name: name,
      rules: declaredRules,
      keywordBlocks: declaredKeywordBlocks
    )
  }
}
