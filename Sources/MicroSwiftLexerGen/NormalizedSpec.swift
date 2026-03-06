public struct RuleID: Sendable, Equatable, Hashable, Codable {
  public let rawValue: Int

  public init(_ rawValue: Int) {
    self.rawValue = rawValue
  }
}

public struct TokenKindID: Sendable, Equatable, Hashable, Codable {
  public let rawValue: Int

  public init(_ rawValue: Int) {
    self.rawValue = rawValue
  }
}

public struct RegexProps: Sendable, Equatable {
  public let nullable: Bool
  public let minWidth: Int
  public let maxWidth: Int?
  public let firstByteSet: ByteSet
}

public struct NormalizedSpec: Sendable, Equatable {
  public let name: String
  public let rules: [NormalizedRule]
  public let keywordBlocks: [NormalizedKeywordBlock]
}

public struct NormalizedRule: Sendable, Equatable {
  public let ruleID: RuleID
  public let tokenKindID: TokenKindID
  public let name: String
  public let mode: RuleMode
  public let role: RuleRole
  public let regex: NormalizedRegex
  public let props: RegexProps
  public let sourceSpan: SpecSpan
}

public struct NormalizedKeywordBlock: Sendable, Equatable {
  public let baseKindName: String
  public let baseTokenKindID: TokenKindID
  public let entries: [NormalizedKeywordEntry]
  public let sourceSpan: SpecSpan
}

public struct NormalizedKeywordEntry: Sendable, Equatable {
  public let lexeme: String
  public let lexemeBytes: [UInt8]
  public let kindName: String
  public let tokenKindID: TokenKindID
  public let sourceSpan: SpecSpan
}

/// Canonical regex IR used by downstream lowering.
public indirect enum NormalizedRegex: Sendable, Equatable, Hashable {
  case never
  case epsilon
  case literal([UInt8])
  case byteClass(ByteSet)
  case concat([NormalizedRegex])
  case alt([NormalizedRegex])
  case repetition(NormalizedRegex, min: Int, max: Int?)
}

extension DeclaredSpec {
  public static func normalize(_ spec: DeclaredSpec) -> NormalizedSpec {
    var tokenIDsByName: [String: TokenKindID] = [:]
    var nextTokenKindID = 0

    func tokenKindID(for name: String) -> TokenKindID {
      if let existing = tokenIDsByName[name] {
        return existing
      }
      let newID = TokenKindID(nextTokenKindID)
      nextTokenKindID += 1
      tokenIDsByName[name] = newID
      return newID
    }

    let normalizedRules = spec.rules.enumerated().map { index, rule in
      let tokenID = tokenKindID(for: rule.declaredKindName)
      let normalizedRegex = NormalizedRegex.normalize(rule.regex)
      return NormalizedRule(
        ruleID: RuleID(index),
        tokenKindID: tokenID,
        name: rule.declaredKindName,
        mode: rule.mode,
        role: rule.role,
        regex: normalizedRegex,
        props: normalizedRegex.props,
        sourceSpan: rule.sourceSpan
      )
    }

    let normalizedKeywordBlocks = spec.keywordBlocks.map { block in
      let baseTokenKindID = tokenKindID(for: block.baseKindName)
      let entries = block.entries.map { entry in
        NormalizedKeywordEntry(
          lexeme: entry.lexeme,
          lexemeBytes: entry.lexemeBytes,
          kindName: entry.kindName,
          tokenKindID: tokenKindID(for: entry.kindName),
          sourceSpan: entry.sourceSpan
        )
      }
      return NormalizedKeywordBlock(
        baseKindName: block.baseKindName,
        baseTokenKindID: baseTokenKindID,
        entries: entries,
        sourceSpan: block.sourceSpan
      )
    }

    return NormalizedSpec(
      name: spec.name,
      rules: normalizedRules,
      keywordBlocks: normalizedKeywordBlocks
    )
  }
}

extension NormalizedRegex {
  public static func normalize(_ raw: RawRegex) -> NormalizedRegex {
    switch raw {
    case .literal(let bytes):
      if bytes.isEmpty { return .epsilon }
      return .literal(bytes)

    case .byteClass(let set):
      if set.isEmpty { return .never }
      return .byteClass(set)

    case .concat(let parts):
      var normalizedParts: [NormalizedRegex] = []
      normalizedParts.reserveCapacity(parts.count)
      for part in parts {
        normalizedParts.append(normalize(part))
      }
      return normalizeConcat(normalizedParts)

    case .alt(let options):
      var normalizedOptions: [NormalizedRegex] = []
      normalizedOptions.reserveCapacity(options.count)
      for option in options {
        normalizedOptions.append(normalize(option))
      }
      return normalizeAlt(normalizedOptions)

    case .repetition(let pattern, let min, let max):
      return normalizeRepetition(normalize(pattern), min: min, max: max)
    }
  }

  public var canonicalKey: String {
    switch self {
    case .never:
      return "n"
    case .epsilon:
      return "e"
    case .literal(let bytes):
      return "l[\(bytes.map(String.init).joined(separator: ","))]"
    case .byteClass(let set):
      return "b[\(set.members.map(String.init).joined(separator: ","))]"
    case .concat(let children):
      return "c(\(children.map(\.canonicalKey).joined(separator: "|")))"
    case .alt(let children):
      return "a(\(children.map(\.canonicalKey).joined(separator: "|")))"
    case .repetition(let child, let min, let max):
      let maxPart = max.map(String.init) ?? "*"
      return "r(\(child.canonicalKey),\(min),\(maxPart))"
    }
  }

  public var props: RegexProps {
    switch self {
    case .never:
      return RegexProps(nullable: false, minWidth: 0, maxWidth: 0, firstByteSet: .empty)

    case .epsilon:
      return RegexProps(nullable: true, minWidth: 0, maxWidth: 0, firstByteSet: .empty)

    case .literal(let bytes):
      let firstSet = bytes.first.map { ByteSet(bytes: [$0]) } ?? .empty
      return RegexProps(
        nullable: bytes.isEmpty,
        minWidth: bytes.count,
        maxWidth: bytes.count,
        firstByteSet: firstSet
      )

    case .byteClass(let set):
      return RegexProps(nullable: false, minWidth: 1, maxWidth: 1, firstByteSet: set)

    case .concat(let children):
      var minWidth = 0
      var maxWidth: Int? = 0

      for child in children {
        let childProps = child.props
        minWidth += childProps.minWidth
        if let currentMax = maxWidth, let childMax = childProps.maxWidth {
          maxWidth = currentMax + childMax
        } else {
          maxWidth = nil
        }
      }

      var nullable = true
      var first = ByteSet.empty
      for child in children {
        let childProps = child.props
        first = first.union(childProps.firstByteSet)
        if !childProps.nullable {
          nullable = false
          break
        }
      }

      return RegexProps(
        nullable: nullable, minWidth: minWidth, maxWidth: maxWidth, firstByteSet: first)

    case .alt(let children):
      var nullable = false
      var minWidth = Int.max
      var maxWidth: Int? = 0
      var first = ByteSet.empty

      for child in children {
        let childProps = child.props
        nullable = nullable || childProps.nullable
        minWidth = Swift.min(minWidth, childProps.minWidth)
        if let currentMax = maxWidth, let childMax = childProps.maxWidth {
          maxWidth = Swift.max(currentMax, childMax)
        } else {
          maxWidth = nil
        }
        first = first.union(childProps.firstByteSet)
      }

      return RegexProps(
        nullable: nullable,
        minWidth: minWidth == .max ? 0 : minWidth,
        maxWidth: maxWidth,
        firstByteSet: first
      )

    case .repetition(let child, let min, let max):
      let childProps = child.props
      let nullable = min == 0 || childProps.nullable
      let minWidth = childProps.minWidth * min

      let maxWidth: Int?
      if let max {
        if let childMax = childProps.maxWidth {
          maxWidth = childMax * max
        } else {
          maxWidth = nil
        }
      } else {
        maxWidth = childProps.maxWidth == 0 ? 0 : nil
      }

      let firstByteSet = max == 0 ? ByteSet.empty : childProps.firstByteSet
      return RegexProps(
        nullable: nullable, minWidth: minWidth, maxWidth: maxWidth, firstByteSet: firstByteSet)
    }
  }

  private static func normalizeConcat(_ items: [NormalizedRegex]) -> NormalizedRegex {
    var flattened: [NormalizedRegex] = []

    for item in items {
      switch item {
      case .concat(let nested):
        flattened.append(contentsOf: nested)
      case .epsilon:
        continue
      case .never:
        return .never
      default:
        flattened.append(item)
      }
    }

    if flattened.isEmpty { return .epsilon }

    var merged: [NormalizedRegex] = []
    for item in flattened {
      if case .literal(let rightBytes) = item,
        let lastIndex = merged.indices.last,
        case .literal(let leftBytes) = merged[lastIndex]
      {
        merged[lastIndex] = .literal(leftBytes + rightBytes)
      } else {
        merged.append(item)
      }
    }

    if merged.count == 1 { return merged[0] }
    return .concat(merged)
  }

  private static func normalizeAlt(_ items: [NormalizedRegex]) -> NormalizedRegex {
    var flattened: [NormalizedRegex] = []

    for item in items {
      switch item {
      case .alt(let nested):
        flattened.append(contentsOf: nested)
      case .never:
        continue
      default:
        flattened.append(item)
      }
    }

    if flattened.isEmpty { return .never }

    let deduped = Array(Set(flattened))
      .sorted { lhs, rhs in lhs.canonicalKey < rhs.canonicalKey }

    if deduped.count == 1 { return deduped[0] }
    return .alt(deduped)
  }

  private static func normalizeRepetition(_ child: NormalizedRegex, min: Int, max: Int?)
    -> NormalizedRegex
  {
    precondition(min >= 0, "repetition min must be non-negative")
    if let max {
      precondition(max >= min, "repetition max must be >= min")
    }

    if max == 0 { return .epsilon }
    if min == 1 && max == 1 { return child }

    if child == .never {
      return min == 0 ? .epsilon : .never
    }
    if child == .epsilon {
      return .epsilon
    }

    return .repetition(child, min: min, max: max)
  }
}
