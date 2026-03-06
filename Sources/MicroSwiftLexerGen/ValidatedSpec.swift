public struct CompileOptions: Sendable, Codable, Equatable {
  public let maxLocalWindowBytes: Int
  public let enableFallback: Bool
  public let maxFallbackStatesPerRule: Int

  public init(
    maxLocalWindowBytes: Int = 8,
    enableFallback: Bool = true,
    maxFallbackStatesPerRule: Int = 256
  ) {
    self.maxLocalWindowBytes = maxLocalWindowBytes
    self.enableFallback = enableFallback
    self.maxFallbackStatesPerRule = maxFallbackStatesPerRule
  }
}

public enum SpecDiagCode: String, Sendable, Codable, Equatable {
  case nullableRule = "LEX001"
  case duplicateTopLevelTokenKind = "LEX002"
  case duplicateKeywordKind = "LEX003"
  case duplicateKeywordLexeme = "LEX004"
  case keywordNotMatchedByBaseRule = "LEX005"
}

public enum Severity: String, Sendable, Codable, Equatable {
  case error
  case warning
}

public struct SpecDiagnostic: Sendable, Codable, Equatable {
  public let code: SpecDiagCode
  public let severity: Severity
  public let primarySpan: SpecSpan
  public let secondarySpan: SpecSpan?
  public let message: String
}

public struct ValidationError: Error, Sendable, Equatable {
  public let diagnostics: [SpecDiagnostic]
}

public struct ValidatedSpec: Sendable, Equatable {
  public let name: String
  public let rules: [NormalizedRule]
  public let keywordBlocks: [NormalizedKeywordBlock]
}

extension NormalizedSpec {
  public static func validate(_ spec: NormalizedSpec, options: CompileOptions = .init()) throws
    -> ValidatedSpec
  {
    var diagnostics: [SpecDiagnostic] = []

    diagnostics.append(contentsOf: validateNullableRules(spec.rules))
    diagnostics.append(contentsOf: validateDuplicateTopLevelKinds(spec.rules))
    diagnostics.append(contentsOf: validateKeywordBlocks(spec))

    if !diagnostics.isEmpty {
      throw ValidationError(diagnostics: sortDiagnostics(diagnostics))
    }

    _ = options  // consumed by later validator phases
    return ValidatedSpec(name: spec.name, rules: spec.rules, keywordBlocks: spec.keywordBlocks)
  }

  private static func validateNullableRules(_ rules: [NormalizedRule]) -> [SpecDiagnostic] {
    rules
      .filter { $0.props.nullable }
      .map { rule in
        SpecDiagnostic(
          code: .nullableRule,
          severity: .error,
          primarySpan: rule.sourceSpan,
          secondarySpan: nil,
          message: "Rule '\(rule.name)' can match the empty string."
        )
      }
  }

  private static func validateDuplicateTopLevelKinds(_ rules: [NormalizedRule]) -> [SpecDiagnostic]
  {
    var firstSeen: [String: NormalizedRule] = [:]
    var diagnostics: [SpecDiagnostic] = []

    for rule in rules {
      if let original = firstSeen[rule.name] {
        diagnostics.append(
          SpecDiagnostic(
            code: .duplicateTopLevelTokenKind,
            severity: .error,
            primarySpan: rule.sourceSpan,
            secondarySpan: original.sourceSpan,
            message: "Duplicate top-level token kind '\(rule.name)'."
          )
        )
      } else {
        firstSeen[rule.name] = rule
      }
    }

    return diagnostics
  }

  private static func validateKeywordBlocks(_ spec: NormalizedSpec) -> [SpecDiagnostic] {
    var baseRuleByName: [String: NormalizedRule] = [:]
    for rule in spec.rules where baseRuleByName[rule.name] == nil {
      baseRuleByName[rule.name] = rule
    }
    var diagnostics: [SpecDiagnostic] = []

    for block in spec.keywordBlocks {
      guard let baseRule = baseRuleByName[block.baseKindName] else {
        continue
      }

      var lexemeSeen: [String: NormalizedKeywordEntry] = [:]
      var kindSeen: [String: NormalizedKeywordEntry] = [:]

      for entry in block.entries {
        if let prior = lexemeSeen[entry.lexeme] {
          diagnostics.append(
            SpecDiagnostic(
              code: .duplicateKeywordLexeme,
              severity: .error,
              primarySpan: entry.sourceSpan,
              secondarySpan: prior.sourceSpan,
              message:
                "Duplicate keyword lexeme '\(entry.lexeme)' in block '\(block.baseKindName)'."
            )
          )
        } else {
          lexemeSeen[entry.lexeme] = entry
        }

        if let prior = kindSeen[entry.kindName] {
          diagnostics.append(
            SpecDiagnostic(
              code: .duplicateKeywordKind,
              severity: .error,
              primarySpan: entry.sourceSpan,
              secondarySpan: prior.sourceSpan,
              message:
                "Duplicate keyword kind '\(entry.kindName)' in block '\(block.baseKindName)'."
            )
          )
        } else {
          kindSeen[entry.kindName] = entry
        }

        if !baseRule.regex.acceptsEntirely(entry.lexemeBytes) {
          diagnostics.append(
            SpecDiagnostic(
              code: .keywordNotMatchedByBaseRule,
              severity: .error,
              primarySpan: entry.sourceSpan,
              secondarySpan: baseRule.sourceSpan,
              message:
                "Keyword '\(entry.lexeme)' is not matched by base rule '\(block.baseKindName)'."
            )
          )
        }
      }
    }

    return diagnostics
  }

  private static func sortDiagnostics(_ diagnostics: [SpecDiagnostic]) -> [SpecDiagnostic] {
    diagnostics.sorted { lhs, rhs in
      if lhs.primarySpan.fileID != rhs.primarySpan.fileID {
        return lhs.primarySpan.fileID < rhs.primarySpan.fileID
      }
      if lhs.primarySpan.line != rhs.primarySpan.line {
        return lhs.primarySpan.line < rhs.primarySpan.line
      }
      if lhs.primarySpan.column != rhs.primarySpan.column {
        return lhs.primarySpan.column < rhs.primarySpan.column
      }
      return lhs.code.rawValue < rhs.code.rawValue
    }
  }
}

extension NormalizedRegex {
  fileprivate func acceptsEntirely(_ input: [UInt8]) -> Bool {
    endPositions(input: input, start: 0).contains(input.count)
  }

  private func endPositions(input: [UInt8], start: Int) -> Set<Int> {
    switch self {
    case .never:
      return []

    case .epsilon:
      return [start]

    case .literal(let bytes):
      guard start + bytes.count <= input.count else { return [] }
      for (offset, byte) in bytes.enumerated() where input[start + offset] != byte {
        return []
      }
      return [start + bytes.count]

    case .byteClass(let set):
      guard start < input.count, set.contains(input[start]) else { return [] }
      return [start + 1]

    case .concat(let children):
      var positions: Set<Int> = [start]
      for child in children {
        var next: Set<Int> = []
        for pos in positions {
          next.formUnion(child.endPositions(input: input, start: pos))
        }
        positions = next
        if positions.isEmpty { break }
      }
      return positions

    case .alt(let children):
      var result: Set<Int> = []
      for child in children {
        result.formUnion(child.endPositions(input: input, start: start))
      }
      return result

    case .repetition(let child, let min, let max):
      var accepted: Set<Int> = min == 0 ? [start] : []
      var frontier: Set<Int> = [start]
      var seen: Set<Int> = [start]
      let upperBound = max ?? (input.count - start + 1)

      if upperBound == 0 { return accepted }

      for rep in 1...upperBound {
        var next: Set<Int> = []
        for pos in frontier {
          next.formUnion(child.endPositions(input: input, start: pos))
        }

        if next.isEmpty { break }

        if max == nil {
          let newNext = next.subtracting(seen)
          if rep >= min {
            accepted.formUnion(next)
          }
          if newNext.isEmpty {
            break
          }
          frontier = newNext
          seen.formUnion(newNext)
        } else {
          frontier = next
          if rep >= min {
            accepted.formUnion(next)
          }
        }
      }

      return accepted
    }
  }
}
