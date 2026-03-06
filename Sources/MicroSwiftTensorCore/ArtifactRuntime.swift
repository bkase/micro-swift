import MicroSwiftLexerGen

public enum ArtifactRuntimeError: Error, Sendable, Equatable {
  case invalidByteToClassLength(actual: Int)
  case invalidFallbackPayload(ruleID: UInt16)
  case fallbackClassCountExceeds128(ruleID: UInt16, classCount: UInt16)
  case fallbackClassCountMismatch(ruleID: UInt16, expected: UInt16, actual: UInt16)
  case fallbackStateCapExceeded(totalStates: UInt32)
  case fallbackWidthMissing(ruleID: UInt16)
  case fallbackWidthInvalid(ruleID: UInt16, minWidth: UInt16, maxWidth: UInt16)
}

public struct ArtifactRuntime: Sendable {
  public let specName: String
  public let ruleCount: Int
  public let runtimeHints: RuntimeHints
  public let byteToClassLUT: [UInt8]
  public let tokenKinds: [TokenKindDecl]
  public let rules: [LoweredRule]
  public let classSets: [ClassSetDecl]
  public let classes: [ByteClassDecl]
  public let keywordRemaps: [KeywordRemapTable]
  public let classSetRuntime: ClassSetRuntime
  public let fallback: FallbackRuntime?

  public var maxLiteralLength: UInt16 {
    runtimeHints.maxLiteralLength
  }

  public var maxBoundedRuleWidth: UInt16 {
    runtimeHints.maxBoundedRuleWidth
  }

  public var maxDeterministicLookaheadBytes: UInt16 {
    runtimeHints.maxDeterministicLookaheadBytes
  }

  public init(
    specName: String,
    ruleCount: Int,
    runtimeHints: RuntimeHints,
    byteToClassLUT: [UInt8],
    tokenKinds: [TokenKindDecl],
    rules: [LoweredRule],
    classSets: [ClassSetDecl],
    classes: [ByteClassDecl],
    keywordRemaps: [KeywordRemapTable],
    fallback: FallbackRuntime?
  ) {
    self.specName = specName
    self.ruleCount = ruleCount
    self.runtimeHints = runtimeHints
    self.byteToClassLUT = byteToClassLUT
    self.tokenKinds = tokenKinds
    self.rules = rules
    self.classSets = classSets
    self.classes = classes
    self.keywordRemaps = keywordRemaps
    self.classSetRuntime = ClassSetRuntime.build(classSets: classSets, classes: classes)
    self.fallback = fallback
  }

  public static func fromArtifact(_ artifact: LexerArtifact) throws -> ArtifactRuntime {
    guard artifact.byteToClass.count == 256 else {
      throw ArtifactRuntimeError.invalidByteToClassLength(actual: artifact.byteToClass.count)
    }

    let fallback = try buildFallbackRuntime(from: artifact)

    return ArtifactRuntime(
      specName: artifact.specName,
      ruleCount: artifact.rules.count,
      runtimeHints: artifact.runtimeHints,
      byteToClassLUT: artifact.byteToClass,
      tokenKinds: artifact.tokenKinds,
      rules: artifact.rules,
      classSets: artifact.classSets,
      classes: artifact.classes,
      keywordRemaps: artifact.keywordRemaps,
      fallback: fallback
    )
  }
}

private struct FallbackRuleBridge {
  let ruleID: UInt16
  let priorityRank: UInt16
  let tokenKindID: UInt16
  let mode: UInt8
  let maxWidth: UInt16

  let stateCount: UInt32
  let classCount: UInt16
  let transitionRowStride: UInt16
  let startState: UInt32
  let acceptingStates: [UInt32]
  let transitions: [UInt32]
}

private func buildFallbackRuntime(from artifact: LexerArtifact) throws -> FallbackRuntime? {
  var bridges: [FallbackRuleBridge] = []

  for rule in artifact.rules {
    guard
      case .fallback(
        let
          stateCount,
        let
          classCount,
        let
          transitionRowStride,
        let
          startState,
        let
          acceptingStates,
        let
          transitions
      ) = rule.plan
    else {
      continue
    }

    guard let maxWidth = rule.maxWidth else {
      throw ArtifactRuntimeError.fallbackWidthMissing(ruleID: rule.ruleID)
    }
    if maxWidth == 0 || maxWidth < rule.minWidth {
      throw ArtifactRuntimeError.fallbackWidthInvalid(
        ruleID: rule.ruleID,
        minWidth: rule.minWidth,
        maxWidth: maxWidth
      )
    }

    guard stateCount > 0, classCount > 0, transitionRowStride == classCount else {
      throw ArtifactRuntimeError.invalidFallbackPayload(ruleID: rule.ruleID)
    }
    guard startState < stateCount else {
      throw ArtifactRuntimeError.invalidFallbackPayload(ruleID: rule.ruleID)
    }
    guard acceptingStates.allSatisfy({ $0 < stateCount }) else {
      throw ArtifactRuntimeError.invalidFallbackPayload(ruleID: rule.ruleID)
    }

    let expectedTransitions = Int(stateCount) * Int(transitionRowStride)
    guard transitions.count == expectedTransitions else {
      throw ArtifactRuntimeError.invalidFallbackPayload(ruleID: rule.ruleID)
    }
    guard transitions.allSatisfy({ $0 < stateCount }) else {
      throw ArtifactRuntimeError.invalidFallbackPayload(ruleID: rule.ruleID)
    }

    if classCount > 128 {
      throw ArtifactRuntimeError.fallbackClassCountExceeds128(
        ruleID: rule.ruleID, classCount: classCount)
    }

    bridges.append(
      FallbackRuleBridge(
        ruleID: rule.ruleID,
        priorityRank: rule.priorityRank,
        tokenKindID: rule.tokenKindID,
        mode: modeID(rule.mode),
        maxWidth: maxWidth,
        stateCount: stateCount,
        classCount: classCount,
        transitionRowStride: transitionRowStride,
        startState: startState,
        acceptingStates: acceptingStates,
        transitions: transitions
      ))
  }

  guard !bridges.isEmpty else {
    return nil
  }

  let sharedClassCount = bridges[0].classCount
  for bridge in bridges.dropFirst() where bridge.classCount != sharedClassCount {
    throw ArtifactRuntimeError.fallbackClassCountMismatch(
      ruleID: bridge.ruleID,
      expected: sharedClassCount,
      actual: bridge.classCount
    )
  }

  var totalStates: UInt32 = 0
  var offsets: [UInt32] = []
  offsets.reserveCapacity(bridges.count)

  for bridge in bridges {
    offsets.append(totalStates)
    let (next, overflow) = totalStates.addingReportingOverflow(bridge.stateCount)
    totalStates = next
    if overflow || totalStates > 128 {
      throw ArtifactRuntimeError.fallbackStateCapExceeded(totalStates: totalStates)
    }
  }

  let numStatesUsed = UInt16(totalStates)
  let classCount = Int(sharedClassCount)
  let stepCount = classCount * Int(numStatesUsed)

  var stepLo = Array(repeating: UInt64(0), count: stepCount)
  var stepHi = Array(repeating: UInt64(0), count: stepCount)

  var startMaskLo: UInt64 = 0
  var startMaskHi: UInt64 = 0
  var startClassMaskLo: UInt64 = 0
  var startClassMaskHi: UInt64 = 0

  var acceptLoByRule: [UInt64] = []
  var acceptHiByRule: [UInt64] = []
  var globalRuleIDByFallbackRule: [UInt16] = []
  var priorityRankByFallbackRule: [UInt16] = []
  var tokenKindIDByFallbackRule: [UInt16] = []
  var modeByFallbackRule: [UInt8] = []

  acceptLoByRule.reserveCapacity(bridges.count)
  acceptHiByRule.reserveCapacity(bridges.count)
  globalRuleIDByFallbackRule.reserveCapacity(bridges.count)
  priorityRankByFallbackRule.reserveCapacity(bridges.count)
  tokenKindIDByFallbackRule.reserveCapacity(bridges.count)
  modeByFallbackRule.reserveCapacity(bridges.count)

  for (fallbackIndex, bridge) in bridges.enumerated() {
    let offset = offsets[fallbackIndex]

    let globalStart = offset + bridge.startState
    setStateBit(globalStart, lo: &startMaskLo, hi: &startMaskHi)

    var acceptLo: UInt64 = 0
    var acceptHi: UInt64 = 0
    for acceptingState in bridge.acceptingStates {
      let globalAccept = offset + acceptingState
      setStateBit(globalAccept, lo: &acceptLo, hi: &acceptHi)
    }

    for localState in 0..<Int(bridge.stateCount) {
      let globalState = Int(offset) + localState
      for classID in 0..<classCount {
        let tIndex = localState * Int(bridge.transitionRowStride) + classID
        let localDestination = bridge.transitions[tIndex]
        let globalDestination = offset + localDestination
        let flatIndex = classID * Int(numStatesUsed) + globalState
        setStateBit(globalDestination, lo: &stepLo[flatIndex], hi: &stepHi[flatIndex])

        if UInt32(localState) == bridge.startState {
          if classID < 64 {
            startClassMaskLo |= (UInt64(1) << UInt64(classID))
          } else {
            startClassMaskHi |= (UInt64(1) << UInt64(classID - 64))
          }
        }
      }
    }

    acceptLoByRule.append(acceptLo)
    acceptHiByRule.append(acceptHi)
    globalRuleIDByFallbackRule.append(bridge.ruleID)
    priorityRankByFallbackRule.append(bridge.priorityRank)
    tokenKindIDByFallbackRule.append(bridge.tokenKindID)
    modeByFallbackRule.append(bridge.mode)
  }

  let maxWidth = bridges.map(\.maxWidth).max() ?? 0

  return FallbackRuntime(
    numStatesUsed: numStatesUsed,
    maxWidth: maxWidth,
    startMaskLo: startMaskLo,
    startMaskHi: startMaskHi,
    stepLo: stepLo,
    stepHi: stepHi,
    acceptLoByRule: acceptLoByRule,
    acceptHiByRule: acceptHiByRule,
    globalRuleIDByFallbackRule: globalRuleIDByFallbackRule,
    priorityRankByFallbackRule: priorityRankByFallbackRule,
    tokenKindIDByFallbackRule: tokenKindIDByFallbackRule,
    modeByFallbackRule: modeByFallbackRule,
    startClassMaskLo: startClassMaskLo,
    startClassMaskHi: startClassMaskHi
  )
}

private func modeID(_ mode: RuleMode) -> UInt8 {
  switch mode {
  case .emit:
    return 0
  case .skip:
    return 1
  }
}

private func setStateBit(_ state: UInt32, lo: inout UInt64, hi: inout UInt64) {
  if state < 64 {
    lo |= (UInt64(1) << UInt64(state))
  } else {
    hi |= (UInt64(1) << UInt64(state - 64))
  }
}
