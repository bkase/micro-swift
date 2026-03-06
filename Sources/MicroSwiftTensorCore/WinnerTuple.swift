public struct WinnerTuple: Sendable {
  public let len: UInt16
  public let priorityRank: UInt16
  public let ruleID: UInt16
  public let tokenKindID: UInt16
  public let mode: UInt8

  public init(len: UInt16, priorityRank: UInt16, ruleID: UInt16, tokenKindID: UInt16, mode: UInt8) {
    self.len = len
    self.priorityRank = priorityRank
    self.ruleID = ruleID
    self.tokenKindID = tokenKindID
    self.mode = mode
  }

  public static let empty = WinnerTuple(
    len: 0,
    priorityRank: .max,
    ruleID: .max,
    tokenKindID: 0,
    mode: 0
  )

  /// Lexicographic comparator: longer wins, then smaller priorityRank, then smaller ruleID.
  public func isBetterThan(_ other: WinnerTuple) -> Bool {
    if len != other.len {
      return len > other.len
    }
    if priorityRank != other.priorityRank {
      return priorityRank < other.priorityRank
    }
    if ruleID != other.ruleID {
      return ruleID < other.ruleID
    }
    return false
  }
}
