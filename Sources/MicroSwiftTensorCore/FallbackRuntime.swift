public struct FallbackRuntime: Sendable {
  public let numStatesUsed: UInt16
  public let maxWidth: UInt16
  public let startMaskLo: UInt64
  public let startMaskHi: UInt64

  public let stepLo: [UInt64]
  public let stepHi: [UInt64]

  public let acceptLoByRule: [UInt64]
  public let acceptHiByRule: [UInt64]

  public let globalRuleIDByFallbackRule: [UInt16]
  public let priorityRankByFallbackRule: [UInt16]
  public let tokenKindIDByFallbackRule: [UInt16]
  public let modeByFallbackRule: [UInt8]

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
    self.stepLo = stepLo
    self.stepHi = stepHi
    self.acceptLoByRule = acceptLoByRule
    self.acceptHiByRule = acceptHiByRule
    self.globalRuleIDByFallbackRule = globalRuleIDByFallbackRule
    self.priorityRankByFallbackRule = priorityRankByFallbackRule
    self.tokenKindIDByFallbackRule = tokenKindIDByFallbackRule
    self.modeByFallbackRule = modeByFallbackRule
    self.startClassMaskLo = startClassMaskLo
    self.startClassMaskHi = startClassMaskHi
  }
}
