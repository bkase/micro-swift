import MicroSwiftLexerGen

public struct FallbackWinner: Sendable, Equatable {
  public let len: UInt16
  public let priorityRank: UInt16
  public let ruleID: UInt16
  public let tokenKindID: UInt16
  public let mode: UInt8

  public init(
    len: UInt16,
    priorityRank: UInt16,
    ruleID: UInt16,
    tokenKindID: UInt16,
    mode: UInt8
  ) {
    self.len = len
    self.priorityRank = priorityRank
    self.ruleID = ruleID
    self.tokenKindID = tokenKindID
    self.mode = mode
  }

  public static let noMatch = FallbackWinner(
    len: 0,
    priorityRank: 0,
    ruleID: 0,
    tokenKindID: 0,
    mode: 0
  )
}

public struct ScalarFallbackEvaluator: Sendable {
  public init() {}

  public func evaluate(
    bytes: [UInt8],
    startPosition: Int,
    validLen: Int,
    byteToClass: [UInt8],
    artifact: LexerArtifact
  ) -> FallbackWinner {
    let boundedValidLen = max(0, min(validLen, bytes.count))
    guard startPosition >= 0, startPosition < boundedValidLen else {
      return .noMatch
    }

    var winner = FallbackWinner.noMatch

    for rule in artifact.rules {
      guard case let .fallback(
        stateCount,
        classCount,
        transitionRowStride,
        startState,
        acceptingStates,
        transitions
      ) = rule.plan else {
        continue
      }

      let acceptedLen = evaluateRule(
        bytes: bytes,
        startPosition: startPosition,
        validLen: boundedValidLen,
        byteToClass: byteToClass,
        stateCount: stateCount,
        classCount: classCount,
        transitionRowStride: transitionRowStride,
        startState: startState,
        acceptingStates: acceptingStates,
        transitions: transitions,
        maxWidth: rule.maxWidth
      )

      guard acceptedLen > 0 else { continue }

      let candidate = FallbackWinner(
        len: acceptedLen,
        priorityRank: rule.priorityRank,
        ruleID: rule.ruleID,
        tokenKindID: rule.tokenKindID,
        mode: modeID(for: rule.mode)
      )

      if isBetter(candidate, than: winner) {
        winner = candidate
      }
    }

    return winner
  }

  private func evaluateRule(
    bytes: [UInt8],
    startPosition: Int,
    validLen: Int,
    byteToClass: [UInt8],
    stateCount: UInt32,
    classCount: UInt16,
    transitionRowStride: UInt16,
    startState: UInt32,
    acceptingStates: [UInt32],
    transitions: [UInt32],
    maxWidth: UInt16?
  ) -> UInt16 {
    guard startState < stateCount else { return 0 }

    let accepting = Set(acceptingStates)
    let stepCap = min(validLen - startPosition, Int(maxWidth ?? UInt16.max))

    var state = startState
    var bestLen = 0

    for step in 0..<stepCap {
      let byteIndex = Int(bytes[startPosition + step])
      guard byteIndex < byteToClass.count else { break }

      let classID = UInt32(byteToClass[byteIndex])
      guard classID < UInt32(classCount) else { break }

      let transitionIndex = Int(state) * Int(transitionRowStride) + Int(classID)
      guard transitionIndex >= 0, transitionIndex < transitions.count else { break }

      state = transitions[transitionIndex]
      guard state < stateCount else { break }

      if accepting.contains(state) {
        bestLen = step + 1
      }
    }

    return UInt16(clamping: bestLen)
  }
}

private func isBetter(_ lhs: FallbackWinner, than rhs: FallbackWinner) -> Bool {
  if lhs.len != rhs.len { return lhs.len > rhs.len }
  if lhs.len == 0 { return false }
  if lhs.priorityRank != rhs.priorityRank { return lhs.priorityRank < rhs.priorityRank }
  return lhs.ruleID < rhs.ruleID
}

private func modeID(for mode: RuleMode) -> UInt8 {
  switch mode {
  case .emit:
    return 0
  case .skip:
    return 1
  }
}
