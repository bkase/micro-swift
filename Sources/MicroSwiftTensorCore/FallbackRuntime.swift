import MLX

public struct FallbackRuntime: Sendable {
  public let numStatesUsed: UInt16
  public let maxWidth: UInt16
  public let startMaskLo: UInt64
  public let startMaskHi: UInt64

  private let hostStepLoStorage: [UInt64]
  private let hostStepHiStorage: [UInt64]

  private let hostAcceptLoByRuleStorage: [UInt64]
  private let hostAcceptHiByRuleStorage: [UInt64]

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
    self.hostStepLoStorage = stepLo
    self.hostStepHiStorage = stepHi
    self.hostAcceptLoByRuleStorage = acceptLoByRule
    self.hostAcceptHiByRuleStorage = acceptHiByRule
    self.hostGlobalRuleIDByFallbackRuleStorage = globalRuleIDByFallbackRule
    self.hostPriorityRankByFallbackRuleStorage = priorityRankByFallbackRule
    self.hostTokenKindIDByFallbackRuleStorage = tokenKindIDByFallbackRule
    self.hostModeByFallbackRuleStorage = modeByFallbackRule
    self.startClassMaskLo = startClassMaskLo
    self.startClassMaskHi = startClassMaskHi
  }

  // Host extraction helpers
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

  // MLX-backed accessors for device execution. Created on demand.
  public func mlxStepLo() -> MLXArray { MLXArray(hostStepLoStorage) }
  public func mlxStepHi() -> MLXArray { MLXArray(hostStepHiStorage) }
  public func mlxAcceptLoByRule() -> MLXArray { MLXArray(hostAcceptLoByRuleStorage) }
  public func mlxAcceptHiByRule() -> MLXArray { MLXArray(hostAcceptHiByRuleStorage) }
  public func mlxGlobalRuleIDByFallbackRule() -> MLXArray {
    MLXArray(hostGlobalRuleIDByFallbackRuleStorage)
  }
  public func mlxPriorityRankByFallbackRule() -> MLXArray {
    MLXArray(hostPriorityRankByFallbackRuleStorage)
  }
  public func mlxTokenKindIDByFallbackRule() -> MLXArray {
    MLXArray(hostTokenKindIDByFallbackRuleStorage)
  }
  public func mlxModeByFallbackRule() -> MLXArray {
    MLXArray(hostModeByFallbackRuleStorage)
  }
}
