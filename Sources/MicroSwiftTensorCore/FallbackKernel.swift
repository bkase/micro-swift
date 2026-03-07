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
