import Foundation
@testable import MicroSwiftLexerGen

enum FallbackFixtures {
  static func singleRuleFallback() -> LexerArtifact {
    let rules = [
      makeRule(
        id: 0,
        name: "identifierFallback",
        tokenKindID: 1,
        family: .fallback,
        priority: 10,
        minWidth: 1,
        maxWidth: nil,
        firstClassSetID: 0,
        plan: makeThreeStateFallback(startClasses: [lowerClassID], loopClasses: [lowerClassID])
      ),
      makeRule(
        id: 1,
        name: "kwIfLiteral",
        tokenKindID: 0,
        family: .literal,
        priority: 0,
        minWidth: 2,
        maxWidth: 2,
        firstClassSetID: 0,
        plan: .literal(bytes: ascii("if"))
      ),
    ]
    return makeArtifact(specName: "single-rule-fallback", rules: rules)
  }

  static func multiRuleFallbackWithPriority() -> LexerArtifact {
    let rules = [
      makeRule(
        id: 0,
        name: "alphaFallback",
        tokenKindID: 1,
        family: .fallback,
        priority: 20,
        minWidth: 1,
        maxWidth: nil,
        firstClassSetID: 0,
        plan: makeThreeStateFallback(startClasses: [lowerClassID], loopClasses: [lowerClassID])
      ),
      makeRule(
        id: 1,
        name: "alphaNumFallback",
        tokenKindID: 2,
        family: .fallback,
        priority: 5,
        minWidth: 1,
        maxWidth: nil,
        firstClassSetID: 2,
        plan: makeThreeStateFallback(
          startClasses: [lowerClassID, digitClassID],
          loopClasses: [lowerClassID, digitClassID]
        )
      ),
    ]
    return makeArtifact(specName: "multi-rule-fallback-priority", rules: rules)
  }

  static func mixedFastAndFallback() -> LexerArtifact {
    let rules = [
      makeRule(
        id: 0,
        name: "kwLetLiteral",
        tokenKindID: 4,
        family: .literal,
        priority: 0,
        minWidth: 3,
        maxWidth: 3,
        firstClassSetID: 0,
        plan: .literal(bytes: ascii("let"))
      ),
      makeRule(
        id: 1,
        name: "digitRun",
        tokenKindID: 3,
        family: .run,
        priority: 10,
        minWidth: 1,
        maxWidth: nil,
        firstClassSetID: 1,
        plan: .runClassRun(bodyClassSetID: 1, minLength: 1)
      ),
      makeRule(
        id: 2,
        name: "identFallback",
        tokenKindID: 1,
        family: .fallback,
        priority: 20,
        minWidth: 1,
        maxWidth: nil,
        firstClassSetID: 7,
        plan: makeThreeStateFallback(
          startClasses: [lowerClassID, underscoreClassID],
          loopClasses: [lowerClassID, digitClassID, underscoreClassID]
        )
      ),
    ]
    return makeArtifact(specName: "mixed-fast-and-fallback", rules: rules)
  }

  static func overlappingFastFallback() -> LexerArtifact {
    let rules = [
      makeRule(
        id: 0,
        name: "kwIfLiteral",
        tokenKindID: 0,
        family: .literal,
        priority: 0,
        minWidth: 2,
        maxWidth: 2,
        firstClassSetID: 0,
        plan: .literal(bytes: ascii("if"))
      ),
      makeRule(
        id: 1,
        name: "identFallback",
        tokenKindID: 1,
        family: .fallback,
        priority: 10,
        minWidth: 1,
        maxWidth: nil,
        firstClassSetID: 0,
        plan: makeThreeStateFallback(startClasses: [lowerClassID], loopClasses: [lowerClassID])
      ),
    ]
    return makeArtifact(specName: "overlapping-fast-fallback", rules: rules)
  }

  static func nearCapStateCount() -> LexerArtifact {
    let rules = [
      makeRule(
        id: 0,
        name: "nearCapFallback",
        tokenKindID: 5,
        family: .fallback,
        priority: 0,
        minWidth: 1,
        maxWidth: nil,
        firstClassSetID: 0,
        plan: makeLinearFallback(stateCount: 120, matchingClasses: [lowerClassID])
      )
    ]
    return makeArtifact(specName: "near-cap-state-count", rules: rules)
  }

  static func overCapStateCount() -> LexerArtifact {
    let rules = [
      makeRule(
        id: 0,
        name: "overCapFallback",
        tokenKindID: 6,
        family: .fallback,
        priority: 0,
        minWidth: 1,
        maxWidth: nil,
        firstClassSetID: 0,
        plan: makeLinearFallback(stateCount: 129, matchingClasses: [lowerClassID])
      )
    ]
    return makeArtifact(specName: "over-cap-state-count", rules: rules)
  }

  static func zeroFallbackRules() -> LexerArtifact {
    let rules = [
      makeRule(
        id: 0,
        name: "kwIfLiteral",
        tokenKindID: 0,
        family: .literal,
        priority: 0,
        minWidth: 2,
        maxWidth: 2,
        firstClassSetID: 0,
        plan: .literal(bytes: ascii("if"))
      ),
      makeRule(
        id: 1,
        name: "digitRun",
        tokenKindID: 3,
        family: .run,
        priority: 10,
        minWidth: 1,
        maxWidth: nil,
        firstClassSetID: 1,
        plan: .runClassRun(bodyClassSetID: 1, minLength: 1)
      ),
    ]
    return makeArtifact(specName: "zero-fallback-rules", rules: rules)
  }

  static var all: [LexerArtifact] {
    [
      singleRuleFallback(),
      multiRuleFallbackWithPriority(),
      mixedFastAndFallback(),
      overlappingFastFallback(),
      nearCapStateCount(),
      overCapStateCount(),
      zeroFallbackRules(),
    ]
  }

  private static let lowerClassID: UInt16 = 1
  private static let digitClassID: UInt16 = 2
  private static let underscoreClassID: UInt16 = 3

  private static let byteToClass: [UInt8] = {
    var map = Array(repeating: UInt8(0), count: 256)

    for byte in UInt8(97)...UInt8(122) {
      map[Int(byte)] = 1
    }
    for byte in UInt8(48)...UInt8(57) {
      map[Int(byte)] = 2
    }
    map[95] = 3
    for byte in UInt8(65)...UInt8(90) {
      map[Int(byte)] = 4
    }

    return map
  }()

  private static let classes: [ByteClassDecl] = {
    var buckets: [[UInt8]] = Array(repeating: [], count: 5)
    for (index, classID) in byteToClass.enumerated() {
      buckets[Int(classID)].append(UInt8(index))
    }
    return buckets.enumerated().map { classID, bytes in
      ByteClassDecl(classID: UInt8(classID), bytes: bytes)
    }
  }()

  private static let classSets: [ClassSetDecl] = [
    ClassSetDecl(classSetID: ClassSetID(0), classes: [1]),
    ClassSetDecl(classSetID: ClassSetID(1), classes: [2]),
    ClassSetDecl(classSetID: ClassSetID(2), classes: [1, 2]),
    ClassSetDecl(classSetID: ClassSetID(3), classes: [1, 2, 3]),
    ClassSetDecl(classSetID: ClassSetID(4), classes: [0, 1, 2, 3, 4]),
    ClassSetDecl(classSetID: ClassSetID(5), classes: [4]),
    ClassSetDecl(classSetID: ClassSetID(6), classes: [3]),
    ClassSetDecl(classSetID: ClassSetID(7), classes: [1, 3]),
  ]

  private static func makeArtifact(specName: String, rules: [LoweredRule]) -> LexerArtifact {
    let maxLiteralLength = rules.compactMap { rule -> UInt16? in
      if case .literal(let bytes) = rule.plan {
        return UInt16(bytes.count)
      }
      return nil
    }.max() ?? 0

    let maxBoundedRuleWidth = rules.compactMap(\.maxWidth).max() ?? 0
    let runtimeHints = RuntimeHints(
      maxLiteralLength: maxLiteralLength,
      maxBoundedRuleWidth: maxBoundedRuleWidth,
      maxDeterministicLookaheadBytes: maxLiteralLength
    )

    return LexerArtifact(
      formatVersion: 1,
      specName: specName,
      specHashHex: String(repeating: "0", count: 64),
      generatorVersion: "fixture",
      runtimeHints: runtimeHints,
      tokenKinds: makeTokenKinds(for: rules),
      byteToClass: byteToClass,
      classes: classes,
      classSets: classSets,
      rules: rules,
      keywordRemaps: []
    )
  }

  private static func makeTokenKinds(for rules: [LoweredRule]) -> [TokenKindDecl] {
    let names: [UInt16: String] = [
      0: "kwIf",
      1: "identifier",
      2: "alphaNumIdentifier",
      3: "number",
      4: "kwLet",
      5: "nearCap",
      6: "overCap",
    ]

    let tokenIDs = Set(rules.map(\.tokenKindID)).sorted()
    return tokenIDs.map { tokenID in
      TokenKindDecl(
        tokenKindID: tokenID,
        name: names[tokenID] ?? "token\(tokenID)",
        defaultMode: .emit
      )
    }
  }

  private static func makeRule(
    id: UInt16,
    name: String,
    tokenKindID: UInt16,
    family: RuleFamily,
    priority: UInt16,
    minWidth: UInt16,
    maxWidth: UInt16?,
    firstClassSetID: UInt16,
    plan: RulePlan
  ) -> LoweredRule {
    LoweredRule(
      ruleID: id,
      name: name,
      tokenKindID: tokenKindID,
      mode: .emit,
      family: family,
      priorityRank: priority,
      minWidth: minWidth,
      maxWidth: maxWidth,
      firstClassSetID: firstClassSetID,
      plan: plan
    )
  }

  private static func makeThreeStateFallback(
    startClasses: Set<UInt16>,
    loopClasses: Set<UInt16>
  ) -> RulePlan {
    let stateCount = 3
    let classCount = Int(classes.count)
    let rowStride = classCount

    var transitions = Array(repeating: UInt32(0), count: stateCount * rowStride)

    for classID in startClasses {
      transitions[(1 * rowStride) + Int(classID)] = 2
    }

    for classID in loopClasses {
      transitions[(2 * rowStride) + Int(classID)] = 2
    }

    return .fallback(
      stateCount: UInt32(stateCount),
      classCount: UInt16(classCount),
      transitionRowStride: UInt16(rowStride),
      startState: 1,
      acceptingStates: [2],
      transitions: transitions
    )
  }

  private static func makeLinearFallback(stateCount: Int, matchingClasses: Set<UInt16>) -> RulePlan {
    precondition(stateCount >= 3)
    let classCount = Int(classes.count)
    let rowStride = classCount

    var transitions = Array(repeating: UInt32(0), count: stateCount * rowStride)
    var nextState = 2

    while nextState < stateCount {
      for classID in matchingClasses {
        if nextState == stateCount - 1 {
          transitions[(nextState * rowStride) + Int(classID)] = UInt32(nextState)
        } else {
          transitions[(nextState * rowStride) + Int(classID)] = UInt32(nextState + 1)
        }
      }
      nextState += 1
    }

    for classID in matchingClasses {
      transitions[(1 * rowStride) + Int(classID)] = 2
    }

    let acceptingStates = Array(2..<stateCount).map(UInt32.init)
    return .fallback(
      stateCount: UInt32(stateCount),
      classCount: UInt16(classCount),
      transitionRowStride: UInt16(rowStride),
      startState: 1,
      acceptingStates: acceptingStates,
      transitions: transitions
    )
  }

  private static func ascii(_ text: String) -> [UInt8] {
    Array(text.utf8)
  }
}
