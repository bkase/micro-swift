public enum GreedySelector {
  /// Selected token from the greedy scan.
  public struct SelectedToken: Sendable, Equatable {
    public let startPos: Int32
    public let length: UInt16
    public let ruleID: UInt16
    public let tokenKindID: UInt16
    public let mode: UInt8

    public init(startPos: Int32, length: UInt16, ruleID: UInt16, tokenKindID: UInt16, mode: UInt8) {
      self.startPos = startPos
      self.length = length
      self.ruleID = ruleID
      self.tokenKindID = tokenKindID
      self.mode = mode
    }
  }

  /// Deterministic page-local greedy selector.
  /// Semantics:
  ///   coveredUntil = 0
  ///   for i in 0..<validLen:
  ///     if winners[i].len > 0 && i >= coveredUntil:
  ///       accept token at i
  ///       coveredUntil = i + winners[i].len
  ///
  /// Returns selected tokens in source order.
  public static func select(
    winners: [WinnerTuple],
    validLen: Int32
  ) -> [SelectedToken] {
    precondition(validLen >= 0, "validLen must be non-negative")
    precondition(Int(validLen) <= winners.count, "validLen must not exceed winners.count")

    var selected: [SelectedToken] = []
    selected.reserveCapacity(Int(validLen))

    var coveredUntil: Int32 = 0
    for index in 0..<Int(validLen) {
      let startPos = Int32(index)
      let winner = winners[index]

      if winner.len > 0, startPos >= coveredUntil {
        selected.append(
          SelectedToken(
            startPos: startPos,
            length: winner.len,
            ruleID: winner.ruleID,
            tokenKindID: winner.tokenKindID,
            mode: winner.mode
          )
        )
        coveredUntil = startPos + Int32(winner.len)
      }
    }

    return selected
  }
}
