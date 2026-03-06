import CryptoKit
import Foundation

public struct LexerArtifact: Sendable, Codable, Equatable {
  public let formatVersion: UInt32
  public let specName: String
  public let specHashHex: String
  public let generatorVersion: String

  public let runtimeHints: RuntimeHints
  public let tokenKinds: [TokenKindDecl]
  public let byteToClass: [UInt8]
  public let classes: [ByteClassDecl]
  public let classSets: [ClassSetDecl]
  public let rules: [LoweredRule]
  public let keywordRemaps: [KeywordRemapTable]
}

public struct RuntimeHints: Sendable, Codable, Equatable {
  public let maxLiteralLength: UInt16
  public let maxBoundedRuleWidth: UInt16
  public let maxDeterministicLookaheadBytes: UInt16
}

public struct TokenKindDecl: Sendable, Codable, Equatable {
  public let tokenKindID: UInt16
  public let name: String
  public let defaultMode: RuleMode
}

public struct LoweredRule: Sendable, Codable, Equatable {
  public let ruleID: UInt16
  public let name: String
  public let tokenKindID: UInt16
  public let mode: RuleMode
  public let family: RuleFamily
  public let priorityRank: UInt16
  public let minWidth: UInt16
  public let maxWidth: UInt16?
  public let firstClassSetID: UInt16
  public let plan: RulePlan
}

public struct KeywordRemapTable: Sendable, Codable, Equatable {
  public let baseRuleID: UInt16
  public let baseTokenKindID: UInt16
  public let maxKeywordLength: UInt8
  public let entries: [KeywordRemapEntry]
}

public struct KeywordRemapEntry: Sendable, Codable, Equatable {
  public let lexeme: [UInt8]
  public let tokenKindID: UInt16
}

public enum RulePlan: Sendable, Codable, Equatable {
  case literal(bytes: [UInt8])
  case runClassRun(bodyClassSetID: UInt16, minLength: UInt16)
  case runHeadTail(headClassSetID: UInt16, tailClassSetID: UInt16)
  case runPrefixed(prefix: [UInt8], bodyClassSetID: UInt16, stopClassSetID: UInt16?)
  case localWindow(maxWidth: UInt16)
  case fallback(
    stateCount: UInt32,
    classCount: UInt16,
    transitionRowStride: UInt16,
    startState: UInt32,
    acceptingStates: [UInt32],
    transitions: [UInt32]
  )
}

extension RulePlan {
  private enum CodingKeys: String, CodingKey {
    case kind
    case bytes
    case bodyClassSetID
    case minLength
    case headClassSetID
    case tailClassSetID
    case prefix
    case stopClassSetID
    case maxWidth
    case stateCount
    case classCount
    case transitionRowStride
    case startState
    case acceptingStates
    case transitions
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .literal(let bytes):
      try c.encode("literal", forKey: .kind)
      try c.encode(bytes, forKey: .bytes)
    case .runClassRun(let bodyClassSetID, let minLength):
      try c.encode("runClassRun", forKey: .kind)
      try c.encode(bodyClassSetID, forKey: .bodyClassSetID)
      try c.encode(minLength, forKey: .minLength)
    case .runHeadTail(let headClassSetID, let tailClassSetID):
      try c.encode("runHeadTail", forKey: .kind)
      try c.encode(headClassSetID, forKey: .headClassSetID)
      try c.encode(tailClassSetID, forKey: .tailClassSetID)
    case .runPrefixed(let prefix, let bodyClassSetID, let stopClassSetID):
      try c.encode("runPrefixed", forKey: .kind)
      try c.encode(prefix, forKey: .prefix)
      try c.encode(bodyClassSetID, forKey: .bodyClassSetID)
      try c.encode(stopClassSetID, forKey: .stopClassSetID)
    case .localWindow(let maxWidth):
      try c.encode("localWindow", forKey: .kind)
      try c.encode(maxWidth, forKey: .maxWidth)
    case .fallback(
      let stateCount,
      let classCount,
      let transitionRowStride,
      let startState,
      let acceptingStates,
      let transitions
    ):
      try c.encode("fallback", forKey: .kind)
      try c.encode(stateCount, forKey: .stateCount)
      try c.encode(classCount, forKey: .classCount)
      try c.encode(transitionRowStride, forKey: .transitionRowStride)
      try c.encode(startState, forKey: .startState)
      try c.encode(acceptingStates, forKey: .acceptingStates)
      try c.encode(transitions, forKey: .transitions)
    }
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try c.decode(String.self, forKey: .kind)
    switch kind {
    case "literal":
      self = .literal(bytes: try c.decode([UInt8].self, forKey: .bytes))
    case "runClassRun":
      self = .runClassRun(
        bodyClassSetID: try c.decode(UInt16.self, forKey: .bodyClassSetID),
        minLength: try c.decode(UInt16.self, forKey: .minLength)
      )
    case "runHeadTail":
      self = .runHeadTail(
        headClassSetID: try c.decode(UInt16.self, forKey: .headClassSetID),
        tailClassSetID: try c.decode(UInt16.self, forKey: .tailClassSetID)
      )
    case "runPrefixed":
      self = .runPrefixed(
        prefix: try c.decode([UInt8].self, forKey: .prefix),
        bodyClassSetID: try c.decode(UInt16.self, forKey: .bodyClassSetID),
        stopClassSetID: try c.decodeIfPresent(UInt16.self, forKey: .stopClassSetID)
      )
    case "localWindow":
      self = .localWindow(maxWidth: try c.decode(UInt16.self, forKey: .maxWidth))
    case "fallback":
      self = .fallback(
        stateCount: try c.decode(UInt32.self, forKey: .stateCount),
        classCount: try c.decode(UInt16.self, forKey: .classCount),
        transitionRowStride: try c.decode(UInt16.self, forKey: .transitionRowStride),
        startState: try c.decode(UInt32.self, forKey: .startState),
        acceptingStates: try c.decode([UInt32].self, forKey: .acceptingStates),
        transitions: try c.decode([UInt32].self, forKey: .transitions)
      )
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .kind,
        in: c,
        debugDescription: "Unknown rule plan kind: \(kind)"
      )
    }
  }
}

public enum ArtifactSerializer {
  public static func build(
    classified: ClassifiedSpec,
    byteClasses: ByteClasses,
    classSets: ClassSets,
    generatorVersion: String = "dev"
  ) -> LexerArtifact {
    let tokenKinds = buildTokenKinds(classified: classified)
    let rules = buildLoweredRules(
      classified: classified, classSets: classSets, byteClasses: byteClasses)
    let keywordRemaps = buildKeywordRemaps(classified: classified)

    let maxLiteralLength =
      rules.compactMap { rule -> UInt16? in
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

    let semanticHashInput = semanticHashPayload(
      specName: classified.name,
      runtimeHints: runtimeHints,
      tokenKinds: tokenKinds,
      byteToClass: byteClasses.byteToClass,
      classes: byteClasses.classes,
      classSets: classSets.classSets,
      rules: rules,
      keywordRemaps: keywordRemaps
    )
    let specHashHex = sha256Hex(semanticHashInput)

    return LexerArtifact(
      formatVersion: 1,
      specName: classified.name,
      specHashHex: specHashHex,
      generatorVersion: generatorVersion,
      runtimeHints: runtimeHints,
      tokenKinds: tokenKinds,
      byteToClass: byteClasses.byteToClass,
      classes: byteClasses.classes,
      classSets: classSets.classSets,
      rules: rules,
      keywordRemaps: keywordRemaps
    )
  }

  public static func encode(_ artifact: LexerArtifact) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(artifact)
  }

  public static func decode(_ data: Data) throws -> LexerArtifact {
    try JSONDecoder().decode(LexerArtifact.self, from: data)
  }
}

private func buildTokenKinds(classified: ClassifiedSpec) -> [TokenKindDecl] {
  var firstSeen: [UInt16: TokenKindDecl] = [:]
  for rule in classified.rules {
    let id = UInt16(rule.rule.tokenKindID.rawValue)
    if firstSeen[id] == nil {
      firstSeen[id] = TokenKindDecl(
        tokenKindID: id,
        name: rule.rule.name,
        defaultMode: rule.rule.mode
      )
    }
  }

  for block in classified.keywordBlocks {
    for entry in block.entries {
      let id = UInt16(entry.tokenKindID.rawValue)
      if firstSeen[id] == nil {
        firstSeen[id] = TokenKindDecl(tokenKindID: id, name: entry.kindName, defaultMode: .emit)
      }
    }
  }

  return firstSeen.values.sorted { $0.tokenKindID < $1.tokenKindID }
}

private func buildLoweredRules(
  classified: ClassifiedSpec,
  classSets: ClassSets,
  byteClasses: ByteClasses
) -> [LoweredRule] {
  classified.rules.enumerated().map { index, rule in
    let firstClassSetID =
      classSets.classSetID(for: rule.rule.props.firstByteSet, in: byteClasses)?.rawValue ?? 0

    let loweredPlan: RulePlan
    switch rule.plan {
    case .literal(let plan):
      loweredPlan = .literal(bytes: plan.bytes)
    case .run(let plan):
      switch plan {
      case .classRun(let bodyClassSetID, let minLength):
        loweredPlan = .runClassRun(bodyClassSetID: bodyClassSetID.rawValue, minLength: minLength)
      case .headTail(let headClassSetID, let tailClassSetID):
        loweredPlan = .runHeadTail(
          headClassSetID: headClassSetID.rawValue,
          tailClassSetID: tailClassSetID.rawValue
        )
      case .prefixed(let prefix, let bodyClassSetID, let stopClassSetID):
        loweredPlan = .runPrefixed(
          prefix: prefix,
          bodyClassSetID: bodyClassSetID.rawValue,
          stopClassSetID: stopClassSetID?.rawValue
        )
      }
    case .localWindow(let plan):
      loweredPlan = .localWindow(maxWidth: plan.maxWidth)
    case .fallback(let plan):
      loweredPlan = .fallback(
        stateCount: plan.stateCount,
        classCount: plan.classCount,
        transitionRowStride: plan.transitionRowStride,
        startState: plan.startState,
        acceptingStates: plan.acceptingStates,
        transitions: plan.transitions
      )
    }

    return LoweredRule(
      ruleID: UInt16(rule.rule.ruleID.rawValue),
      name: rule.rule.name,
      tokenKindID: UInt16(rule.rule.tokenKindID.rawValue),
      mode: rule.rule.mode,
      family: rule.plan.family,
      priorityRank: UInt16(index),
      minWidth: UInt16(rule.rule.props.minWidth),
      maxWidth: rule.rule.props.maxWidth.map(UInt16.init),
      firstClassSetID: firstClassSetID,
      plan: loweredPlan
    )
  }
}

private func buildKeywordRemaps(classified: ClassifiedSpec) -> [KeywordRemapTable] {
  let rulesByName = Dictionary(
    uniqueKeysWithValues: classified.rules.map { ($0.rule.name, $0.rule) })

  return classified.keywordBlocks.compactMap { block in
    guard let baseRule = rulesByName[block.baseKindName] else { return nil }

    let entries = block.entries
      .sorted { lhs, rhs in
        lhs.lexemeBytes.lexicographicallyPrecedes(rhs.lexemeBytes)
      }
      .map { entry in
        KeywordRemapEntry(
          lexeme: entry.lexemeBytes, tokenKindID: UInt16(entry.tokenKindID.rawValue))
      }

    let maxKeywordLength = UInt8(entries.map { $0.lexeme.count }.max() ?? 0)
    return KeywordRemapTable(
      baseRuleID: UInt16(baseRule.ruleID.rawValue),
      baseTokenKindID: UInt16(block.baseTokenKindID.rawValue),
      maxKeywordLength: maxKeywordLength,
      entries: entries
    )
  }
}

private struct SemanticHashPayload: Codable {
  let specName: String
  let runtimeHints: RuntimeHints
  let tokenKinds: [TokenKindDecl]
  let byteToClass: [UInt8]
  let classes: [ByteClassDecl]
  let classSets: [ClassSetDecl]
  let rules: [LoweredRule]
  let keywordRemaps: [KeywordRemapTable]
}

private func semanticHashPayload(
  specName: String,
  runtimeHints: RuntimeHints,
  tokenKinds: [TokenKindDecl],
  byteToClass: [UInt8],
  classes: [ByteClassDecl],
  classSets: [ClassSetDecl],
  rules: [LoweredRule],
  keywordRemaps: [KeywordRemapTable]
) -> Data {
  let payload = SemanticHashPayload(
    specName: specName,
    runtimeHints: runtimeHints,
    tokenKinds: tokenKinds,
    byteToClass: byteToClass,
    classes: classes,
    classSets: classSets,
    rules: rules,
    keywordRemaps: keywordRemaps
  )

  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  return (try? encoder.encode(payload)) ?? Data()
}

private func sha256Hex(_ input: Data) -> String {
  let digest = SHA256.hash(data: input)
  return digest.map { String(format: "%02x", $0) }.joined()
}
