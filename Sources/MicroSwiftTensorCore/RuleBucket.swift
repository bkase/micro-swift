import MicroSwiftLexerGen

public struct RuleBuckets: Sendable {
  /// Literals grouped by byte length.
  public let literalBuckets: [Int: [LoweredRule]]

  /// classRun rules.
  public let classRunRules: [LoweredRule]

  /// headTail rules.
  public let headTailRules: [LoweredRule]

  /// prefixed rules.
  public let prefixedRules: [LoweredRule]

  public init(
    literalBuckets: [Int: [LoweredRule]],
    classRunRules: [LoweredRule],
    headTailRules: [LoweredRule],
    prefixedRules: [LoweredRule]
  ) {
    self.literalBuckets = literalBuckets
    self.classRunRules = classRunRules
    self.headTailRules = headTailRules
    self.prefixedRules = prefixedRules
  }

  /// Build deterministic buckets from lowered rules.
  /// Unsupported families/plans are rejected at bucketing time with a fast-fail runtime error.
  public static func build(from rules: [LoweredRule]) -> RuleBuckets {
    let sortedRules = rules.sorted { lhs, rhs in
      if lhs.ruleID != rhs.ruleID {
        return lhs.ruleID < rhs.ruleID
      }
      return lhs.name < rhs.name
    }

    var literalBuckets: [Int: [LoweredRule]] = [:]
    var classRunRules: [LoweredRule] = []
    var headTailRules: [LoweredRule] = []
    var prefixedRules: [LoweredRule] = []

    for rule in sortedRules {
      switch rule.plan {
      case .literal(let bytes):
        literalBuckets[bytes.count, default: []].append(rule)
      case .runClassRun:
        classRunRules.append(rule)
      case .runHeadTail:
        headTailRules.append(rule)
      case .runPrefixed:
        prefixedRules.append(rule)
      case .localWindow, .fallback:
        preconditionFailure(
          "artifact-capability-error: unsupported rule family for runtime profile v0, " +
            "ruleID=\(rule.ruleID), name=\(rule.name), family=\(rule.family.rawValue)")
      }
    }

    return RuleBuckets(
      literalBuckets: literalBuckets,
      classRunRules: classRunRules,
      headTailRules: headTailRules,
      prefixedRules: prefixedRules
    )
  }
}
