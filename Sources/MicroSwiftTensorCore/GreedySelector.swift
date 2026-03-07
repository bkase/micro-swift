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
      let n = pageSize
      let sentinelScalar = Int32(n)
      let sentinelArr = MLXArray([sentinelScalar])
      let sentinelFill = MLXArray(Array(repeating: sentinelScalar, count: n))
      let positions = arange(n, dtype: .int32)
      let validMask = positions .< Int32(boundedValidLen)
      let winnerLen = winnerTensors.len.asType(.int32)
      let positive = (winnerLen .> 0) .&& validMask
      let endExclusive = positions + winnerLen

      // --- Phase 1: Build successor links ---
      // candPosOrN: candidates get their position, non-candidates get sentinel N
      let candPosOrN = which(positive, positions, sentinelFill)
      // nextCandAt: nearest candidate position >= each position (reverse cummin)
      let nextCandAt = cummin(candPosOrN, axis: 0, reverse: true)
      // Extended with sentinel for safe OOB gather
      let nextCandAtExt = concatenated([nextCandAt, sentinelArr], axis: 0)
      // succ[i] = next candidate at or after endExclusive[i], for candidates only
      let succRaw = nextCandAtExt.take(minimum(endExclusive, sentinelScalar))
      let succ = which(positive, succRaw, sentinelFill)

      // --- Phase 2: Pointer jumping (O(log N) iterations) ---
      // Compute ceil(log2(N)) without Foundation
      var logN = 0
      var v = n
      while v > 1 {
        v = (v + 1) / 2
        logN += 1
      }
      logN = Swift.max(logN, 1)
      var succLevels: [MLXArray] = [succ]
      for k in 0..<logN {
        let ext = concatenated([succLevels[k], sentinelArr], axis: 0)
        let next = ext.take(minimum(succLevels[k], sentinelScalar))
        succLevels.append(next)
      }

      // --- Phase 3: Binary-search chain membership ---
      // Start from the first candidate
      let firstCand = nextCandAt[0..<1]  // 1-element tensor, broadcasts to [N]
      var cursor = broadcast(firstCand, to: [n]).asType(.int32)
      for k in stride(from: logN - 1, through: 0, by: -1) {
        let ext = concatenated([succLevels[k], sentinelArr], axis: 0)
        let jumped = ext.take(minimum(cursor, sentinelScalar))
        let shouldAdvance = jumped .<= positions
        cursor = which(shouldAdvance, jumped, cursor)
      }
      let selectedMask = positive .&& (cursor .== positions)

      let zeroU16 = zeros([n], dtype: .uint16)
      let zeroU8 = zeros([n], dtype: .uint8)
      let zeroI32 = zeros([n], dtype: .int32)
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
