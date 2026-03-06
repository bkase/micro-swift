public enum RuleFamily: String, Sendable, Equatable {
  case literal
  case run
  case localWindow
  case fallback
}

public struct LiteralPlan: Sendable, Equatable {
  public let bytes: [UInt8]
}

public enum RunPlan: Sendable, Equatable {
  case classRun(bodyClassSetID: ClassSetID, minLength: UInt16)
  case headTail(headClassSetID: ClassSetID, tailClassSetID: ClassSetID)
  case prefixed(prefix: [UInt8], bodyClassSetID: ClassSetID, stopClassSetID: ClassSetID?)
}

public struct LocalWindowPlan: Sendable, Equatable {
  public let maxWidth: UInt16
}

public struct FallbackPlan: Sendable, Equatable {
  public let regex: NormalizedRegex
}

public enum ClassifiedPlan: Sendable, Equatable {
  case literal(LiteralPlan)
  case run(RunPlan)
  case localWindow(LocalWindowPlan)
  case fallback(FallbackPlan)

  public var family: RuleFamily {
    switch self {
    case .literal: return .literal
    case .run: return .run
    case .localWindow: return .localWindow
    case .fallback: return .fallback
    }
  }
}

public struct ClassifiedRule: Sendable, Equatable {
  public let rule: NormalizedRule
  public let plan: ClassifiedPlan
}

public struct ClassifiedSpec: Sendable, Equatable {
  public let name: String
  public let rules: [ClassifiedRule]
  public let keywordBlocks: [NormalizedKeywordBlock]
}

public struct ClassificationError: Error, Sendable, Equatable {
  public let message: String
}

extension ValidatedSpec {
  public func classifyRules(
    byteClasses: ByteClasses,
    classSets: ClassSets,
    options: CompileOptions = .init()
  ) throws -> ClassifiedSpec {
    let classified = try rules.map { rule in
      let plan = try classify(
        regex: rule.regex,
        props: rule.props,
        byteClasses: byteClasses,
        classSets: classSets,
        options: options
      )
      return ClassifiedRule(rule: rule, plan: plan)
    }

    return ClassifiedSpec(name: name, rules: classified, keywordBlocks: keywordBlocks)
  }

  private func classify(
    regex: NormalizedRegex,
    props: RegexProps,
    byteClasses: ByteClasses,
    classSets: ClassSets,
    options: CompileOptions
  ) throws -> ClassifiedPlan {
    if case .literal(let bytes) = regex {
      return .literal(LiteralPlan(bytes: bytes))
    }

    if let runPlan = classifyRun(regex: regex, byteClasses: byteClasses, classSets: classSets) {
      return .run(runPlan)
    }

    if let maxWidth = props.maxWidth, maxWidth <= options.maxLocalWindowBytes {
      return .localWindow(LocalWindowPlan(maxWidth: UInt16(maxWidth)))
    }

    if options.enableFallback {
      return .fallback(FallbackPlan(regex: regex))
    }

    throw ClassificationError(message: "Rule requires fallback but fallback is disabled.")
  }

  private func classifyRun(
    regex: NormalizedRegex,
    byteClasses: ByteClasses,
    classSets: ClassSets
  ) -> RunPlan? {
    if case .repetition(.byteClass(let body), let min, max: nil) = regex,
      let bodyID = classSets.classSetID(for: body, in: byteClasses)
    {
      return .classRun(bodyClassSetID: bodyID, minLength: UInt16(clamping: min))
    }

    if case .concat(let children) = regex {
      if children.count == 2,
        case .byteClass(let head) = children[0],
        case .repetition(.byteClass(let tail), let min, max: nil) = children[1],
        min == 0,
        head.isSubset(of: tail),
        let headID = classSets.classSetID(for: head, in: byteClasses),
        let tailID = classSets.classSetID(for: tail, in: byteClasses)
      {
        return .headTail(headClassSetID: headID, tailClassSetID: tailID)
      }

      if children.count == 2,
        case .literal(let prefix) = children[0],
        case .repetition(.byteClass(let body), let min, max: nil) = children[1],
        min == 0,
        !prefix.isEmpty,
        let bodyID = classSets.classSetID(for: body, in: byteClasses)
      {
        let stop = body.complement
        let stopID = classSets.classSetID(for: stop, in: byteClasses)
        return .prefixed(prefix: prefix, bodyClassSetID: bodyID, stopClassSetID: stopID)
      }
    }

    return nil
  }
}
