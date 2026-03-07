import MLX

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

  /// Device-oriented selected token fields laid out over page positions.
  /// Entries where `selectedMask == false` are zeroed.
  public struct SelectedTokenTensors {
    public let startPos: MLXArray
    public let length: MLXArray
    public let ruleID: MLXArray
    public let tokenKindID: MLXArray
    public let mode: MLXArray
    public let selectedMask: MLXArray

    public init(
      startPos: MLXArray,
      length: MLXArray,
      ruleID: MLXArray,
      tokenKindID: MLXArray,
      mode: MLXArray,
      selectedMask: MLXArray
    ) {
      self.startPos = startPos.asType(.int32)
      self.length = length.asType(.uint16)
      self.ruleID = ruleID.asType(.uint16)
      self.tokenKindID = tokenKindID.asType(.uint16)
      self.mode = mode.asType(.uint8)
      self.selectedMask = selectedMask.asType(.bool)
    }
  }

  /// Deterministic page-local greedy selector.
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

  /// Deterministic greedy selection over winner tensors without host winner extraction.
  /// This returns page-aligned selected fields; packing/filtering is handled downstream.
  public static func select(
    winnerTensors: WinnerReduction.WinnerTensors,
    validLen: Int32
  ) -> SelectedTokenTensors {
    precondition(validLen >= 0, "validLen must be non-negative")
    let pageSize = Int(winnerTensors.len.shape.first ?? 0)
    let boundedValidLen = max(0, min(Int(validLen), pageSize))
    guard pageSize > 0, boundedValidLen > 0 else {
      let emptyMask = withMLXCPU { zeros([pageSize], dtype: .bool) }
      return SelectedTokenTensors(
        startPos: withMLXCPU { zeros([pageSize], dtype: .int32) },
        length: withMLXCPU { zeros([pageSize], dtype: .uint16) },
        ruleID: withMLXCPU { zeros([pageSize], dtype: .uint16) },
        tokenKindID: withMLXCPU { zeros([pageSize], dtype: .uint16) },
        mode: withMLXCPU { zeros([pageSize], dtype: .uint8) },
        selectedMask: emptyMask
      )
    }

    return withMLXCPU {
      let positions = arange(pageSize, dtype: .int32)
      let validMask = positions .< Int32(boundedValidLen)
      let winnerLen = winnerTensors.len.asType(.int32)
      let positive = (winnerLen .> 0) .&& validMask
      let endExclusive = positions + winnerLen

      // Fixed-point solve of greedy keep predicate using cumulative max of accepted ends.
      var selectedMask = positive
      for _ in 0..<boundedValidLen {
        let selectedEnds = which(selectedMask, endExclusive, zeros([pageSize], dtype: .int32))
        let coveredInclusive = selectedEnds.cummax(axis: 0)
        let coveredBefore = {
          let shiftedCore = coveredInclusive[0..<(pageSize - 1)]
          let headPadding = zeros([1], dtype: .int32)
          return concatenated([headPadding, shiftedCore], axis: 0)
        }()
        let nextMask = positive .&& (positions .>= coveredBefore)
        selectedMask = nextMask
      }

      let zeroU16 = zeros([pageSize], dtype: .uint16)
      let zeroU8 = zeros([pageSize], dtype: .uint8)
      let zeroI32 = zeros([pageSize], dtype: .int32)
      return SelectedTokenTensors(
        startPos: which(selectedMask, positions, zeroI32).asType(.int32),
        length: which(selectedMask, winnerTensors.len.asType(.uint16), zeroU16).asType(.uint16),
        ruleID: which(selectedMask, winnerTensors.ruleID.asType(.uint16), zeroU16).asType(.uint16),
        tokenKindID: which(selectedMask, winnerTensors.tokenKindID.asType(.uint16), zeroU16)
          .asType(.uint16),
        mode: which(selectedMask, winnerTensors.mode.asType(.uint8), zeroU8).asType(.uint8),
        selectedMask: selectedMask
      )
    }
  }
}

public func greedyNonOverlapSelect(
  winners: [CandidateWinner],
  validLen: Int
) -> [CandidateWinner] {
  guard validLen > 0 else { return [] }

  let bestByPosition = reduceBucketWinners(buckets: [winners])
  var selected: [CandidateWinner] = []
  var coveredUntil = 0

  for position in 0..<validLen {
    let winner =
      position < bestByPosition.count
      ? bestByPosition[position] : CandidateWinner.noMatch(at: position)
    if winner.len > 0, position >= coveredUntil {
      selected.append(winner)
      coveredUntil = position + Int(winner.len)
    }
  }

  return selected
}
