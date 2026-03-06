import MLX

public struct FallbackRuntime: @unchecked Sendable {
  public let numStatesUsed: UInt16
  public let maxWidth: UInt16
  public let startMaskLo: UInt64
  public let startMaskHi: UInt64

  public let stepLo: MLXArray
  public let stepHi: MLXArray
  private let hostStepLoStorage: [UInt64]
  private let hostStepHiStorage: [UInt64]

  public let acceptLoByRule: MLXArray
  public let acceptHiByRule: MLXArray
  private let hostAcceptLoByRuleStorage: [UInt64]
  private let hostAcceptHiByRuleStorage: [UInt64]

  public let globalRuleIDByFallbackRule: MLXArray
  public let priorityRankByFallbackRule: MLXArray
  public let tokenKindIDByFallbackRule: MLXArray
  public let modeByFallbackRule: MLXArray
  private let hostGlobalRuleIDByFallbackRuleStorage: [UInt16]
  private let hostPriorityRankByFallbackRuleStorage: [UInt16]
  private let hostTokenKindIDByFallbackRuleStorage: [UInt16]
  private let hostModeByFallbackRuleStorage: [UInt8]

  public let startClassMaskLo: UInt64
  public let startClassMaskHi: UInt64

  public init(
    numStatesUsed: UInt16,
    maxWidth: UInt16,
    startMaskLo: UInt64,
    startMaskHi: UInt64,
    stepLo: [UInt64],
    stepHi: [UInt64],
    acceptLoByRule: [UInt64],
    acceptHiByRule: [UInt64],
    globalRuleIDByFallbackRule: [UInt16],
    priorityRankByFallbackRule: [UInt16],
    tokenKindIDByFallbackRule: [UInt16],
    modeByFallbackRule: [UInt8],
    startClassMaskLo: UInt64,
    startClassMaskHi: UInt64
  ) {
    self.numStatesUsed = numStatesUsed
    self.maxWidth = maxWidth
    self.startMaskLo = startMaskLo
    self.startMaskHi = startMaskHi
    self.stepLo = withMLXCPU { MLXArray(stepLo) }
    self.stepHi = withMLXCPU { MLXArray(stepHi) }
    self.hostStepLoStorage = stepLo
    self.hostStepHiStorage = stepHi
    self.acceptLoByRule = withMLXCPU { MLXArray(acceptLoByRule) }
    self.acceptHiByRule = withMLXCPU { MLXArray(acceptHiByRule) }
    self.hostAcceptLoByRuleStorage = acceptLoByRule
    self.hostAcceptHiByRuleStorage = acceptHiByRule
    self.globalRuleIDByFallbackRule = withMLXCPU { MLXArray(globalRuleIDByFallbackRule) }
    self.priorityRankByFallbackRule = withMLXCPU { MLXArray(priorityRankByFallbackRule) }
    self.tokenKindIDByFallbackRule = withMLXCPU { MLXArray(tokenKindIDByFallbackRule) }
    self.modeByFallbackRule = withMLXCPU { MLXArray(modeByFallbackRule) }
    self.hostGlobalRuleIDByFallbackRuleStorage = globalRuleIDByFallbackRule
    self.hostPriorityRankByFallbackRuleStorage = priorityRankByFallbackRule
    self.hostTokenKindIDByFallbackRuleStorage = tokenKindIDByFallbackRule
    self.hostModeByFallbackRuleStorage = modeByFallbackRule
    self.startClassMaskLo = startClassMaskLo
    self.startClassMaskHi = startClassMaskHi
  }

  public func hostStepLo() -> [UInt64] { hostStepLoStorage }
  public func hostStepHi() -> [UInt64] { hostStepHiStorage }
  public func hostAcceptLoByRule() -> [UInt64] { hostAcceptLoByRuleStorage }
  public func hostAcceptHiByRule() -> [UInt64] { hostAcceptHiByRuleStorage }
  public func hostGlobalRuleIDByFallbackRule() -> [UInt16] {
    hostGlobalRuleIDByFallbackRuleStorage
  }
  public func hostPriorityRankByFallbackRule() -> [UInt16] {
    hostPriorityRankByFallbackRuleStorage
  }
  public func hostTokenKindIDByFallbackRule() -> [UInt16] {
    hostTokenKindIDByFallbackRuleStorage
  }
  public func hostModeByFallbackRule() -> [UInt8] {
    hostModeByFallbackRuleStorage
  }
}
