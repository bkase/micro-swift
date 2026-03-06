public struct FallbackPageResult: Sendable, Equatable {
  public let fallbackLen: [UInt16]
  public let fallbackPriorityRank: [UInt16]
  public let fallbackRuleID: [UInt16]
  public let fallbackTokenKindID: [UInt16]
  public let fallbackMode: [UInt8]

  public init(
    fallbackLen: [UInt16],
    fallbackPriorityRank: [UInt16],
    fallbackRuleID: [UInt16],
    fallbackTokenKindID: [UInt16],
    fallbackMode: [UInt8]
  ) {
    self.fallbackLen = fallbackLen
    self.fallbackPriorityRank = fallbackPriorityRank
    self.fallbackRuleID = fallbackRuleID
    self.fallbackTokenKindID = fallbackTokenKindID
    self.fallbackMode = fallbackMode
  }
}

public struct FallbackKernelRunner: Sendable {
  public let fallback: FallbackRuntime

  public init(fallback: FallbackRuntime) {
    self.fallback = fallback
  }

  public func evaluatePage(classIDs: [UInt16], validLen: Int32) -> FallbackPageResult {
    runFallbackPage(classIDs: classIDs, validLen: validLen, fallback: fallback)
  }

  public func evaluatePage(
    classIDs: [UInt16],
    validLen: Int32,
    observability: inout FallbackObservability
  ) -> FallbackPageResult {
    withUnsafeMutablePointer(to: &observability) { observabilityPointer in
      runFallbackPage(
        classIDs: classIDs,
        validLen: validLen,
        fallback: fallback,
        observability: observabilityPointer
      )
    }
  }
}

public func evaluatePage(
  classIDs: [UInt16],
  validLen: Int32,
  fallback: FallbackRuntime
) -> FallbackPageResult {
  runFallbackPage(classIDs: classIDs, validLen: validLen, fallback: fallback)
}

private func runFallbackPage(
  classIDs: [UInt16],
  validLen: Int32,
  fallback: FallbackRuntime,
  observability: UnsafeMutablePointer<FallbackObservability>? = nil
) -> FallbackPageResult {
  let pageWidth = classIDs.count
  let boundedValidLen = max(0, min(Int(validLen), pageWidth))
  let fallbackMaxWidth = Int(fallback.maxWidth)
  let numStatesUsed = Int(fallback.numStatesUsed)
  let stepLo = fallback.hostStepLo()
  let stepHi = fallback.hostStepHi()
  let acceptLoByRule = fallback.hostAcceptLoByRule()
  let acceptHiByRule = fallback.hostAcceptHiByRule()
  let globalRuleIDByFallbackRule = fallback.hostGlobalRuleIDByFallbackRule()
  let priorityRankByFallbackRule = fallback.hostPriorityRankByFallbackRule()
  let tokenKindIDByFallbackRule = fallback.hostTokenKindIDByFallbackRule()
  let modeByFallbackRule = fallback.hostModeByFallbackRule()
  let fallbackRuleCount = globalRuleIDByFallbackRule.count

  let stepStride = max(1, numStatesUsed)
  let maxClassCount = stepLo.count / stepStride

  var fallbackLen = Array(repeating: UInt16(0), count: pageWidth)
  var fallbackPriorityRank = Array(repeating: UInt16(0), count: pageWidth)
  var fallbackRuleID = Array(repeating: UInt16(0), count: pageWidth)
  var fallbackTokenKindID = Array(repeating: UInt16(0), count: pageWidth)
  var fallbackMode = Array(repeating: UInt8(0), count: pageWidth)

  for i in 0..<pageWidth {
    guard i < boundedValidLen else { continue }
    guard startEligible(classID: classIDs[i], fallback: fallback) else {
      observability?.pointee.recordSkippedByStartMask()
      continue
    }
    observability?.pointee.recordEntered()

    var bestLen: UInt16 = 0
    var bestPriorityRank: UInt16 = 0
    var bestRuleID: UInt16 = 0
    var bestTokenKindID: UInt16 = 0
    var bestMode: UInt8 = 0

    var activeLo = fallback.startMaskLo
    var activeHi = fallback.startMaskHi

    for k in 0..<fallbackMaxWidth {
      let cursor = i + k
      guard cursor < boundedValidLen else {
        activeLo = 0
        activeHi = 0
        continue
      }

      if activeLo == 0, activeHi == 0 {
        continue
      }

      let classID = Int(classIDs[cursor])
      guard classID < maxClassCount else {
        activeLo = 0
        activeHi = 0
        continue
      }

      var nextLo: UInt64 = 0
      var nextHi: UInt64 = 0

      var loBits = activeLo
      while loBits != 0 {
        let bit = loBits.trailingZeroBitCount
          let state = bit
          if state < numStatesUsed {
            let flatIndex = (classID * stepStride) + state
            nextLo |= stepLo[flatIndex]
            nextHi |= stepHi[flatIndex]
          }
        loBits &= (loBits - 1)
      }

      var hiBits = activeHi
      while hiBits != 0 {
        let bit = hiBits.trailingZeroBitCount
          let state = 64 + bit
          if state < numStatesUsed {
            let flatIndex = (classID * stepStride) + state
            nextLo |= stepLo[flatIndex]
            nextHi |= stepHi[flatIndex]
          }
        hiBits &= (hiBits - 1)
      }

      activeLo = nextLo
      activeHi = nextHi

      if activeLo == 0, activeHi == 0 {
        continue
      }

      let candidateLen = UInt16(k + 1)
      for ruleIndex in 0..<fallbackRuleCount {
        if (activeLo & acceptLoByRule[ruleIndex]) == 0,
          (activeHi & acceptHiByRule[ruleIndex]) == 0
        {
          continue
        }

        let candidatePriority = priorityRankByFallbackRule[ruleIndex]
        let candidateRuleID = globalRuleIDByFallbackRule[ruleIndex]

        if better(
          len: candidateLen,
          priorityRank: candidatePriority,
          ruleID: candidateRuleID,
          thanLen: bestLen,
          thanPriorityRank: bestPriorityRank,
          thanRuleID: bestRuleID
        ) {
          bestLen = candidateLen
          bestPriorityRank = candidatePriority
          bestRuleID = candidateRuleID
          bestTokenKindID = tokenKindIDByFallbackRule[ruleIndex]
          bestMode = modeByFallbackRule[ruleIndex]
        }
      }
    }

    fallbackLen[i] = bestLen
    fallbackPriorityRank[i] = bestPriorityRank
    fallbackRuleID[i] = bestRuleID
    fallbackTokenKindID[i] = bestTokenKindID
    fallbackMode[i] = bestMode
  }

  return FallbackPageResult(
    fallbackLen: fallbackLen,
    fallbackPriorityRank: fallbackPriorityRank,
    fallbackRuleID: fallbackRuleID,
    fallbackTokenKindID: fallbackTokenKindID,
    fallbackMode: fallbackMode
  )
}

private func startEligible(classID: UInt16, fallback: FallbackRuntime) -> Bool {
  if classID < 64 {
    let mask = UInt64(1) << UInt64(classID)
    return (fallback.startClassMaskLo & mask) != 0
  }
  if classID < 128 {
    let mask = UInt64(1) << UInt64(classID - 64)
    return (fallback.startClassMaskHi & mask) != 0
  }
  return false
}

private func better(
  len lhsLen: UInt16,
  priorityRank lhsPriorityRank: UInt16,
  ruleID lhsRuleID: UInt16,
  thanLen rhsLen: UInt16,
  thanPriorityRank rhsPriorityRank: UInt16,
  thanRuleID rhsRuleID: UInt16
) -> Bool {
  if lhsLen != rhsLen { return lhsLen > rhsLen }
  if lhsLen == 0 { return false }
  if lhsPriorityRank != rhsPriorityRank { return lhsPriorityRank < rhsPriorityRank }
  return lhsRuleID < rhsRuleID
}
