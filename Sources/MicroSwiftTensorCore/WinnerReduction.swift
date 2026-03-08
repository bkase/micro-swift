import MLX
import MicroSwiftLexerGen

public enum WinnerReduction {
  /// Shared tensor layout for rule competition.
  /// All tensors are shaped [ruleCount, pageSize].
  public struct RuleTensorBatch {
    public let candLenByRule: MLXArray
    public let priorityRankByRule: MLXArray
    public let ruleIDByRule: MLXArray
    public let tokenKindIDByRule: MLXArray
    public let modeByRule: MLXArray

    public init(
      candLenByRule: MLXArray,
      priorityRankByRule: MLXArray,
      ruleIDByRule: MLXArray,
      tokenKindIDByRule: MLXArray,
      modeByRule: MLXArray
    ) {
      self.candLenByRule = candLenByRule.asType(.uint16)
      self.priorityRankByRule = priorityRankByRule.asType(.uint16)
      self.ruleIDByRule = ruleIDByRule.asType(.uint16)
      self.tokenKindIDByRule = tokenKindIDByRule.asType(.uint16)
      self.modeByRule = modeByRule.asType(.uint8)
    }

    public var ruleCount: Int {
      guard candLenByRule.ndim >= 1 else { return 0 }
      return Int(candLenByRule.shape[0])
    }

    public var pageSize: Int {
      guard candLenByRule.ndim >= 2 else { return 0 }
      return Int(candLenByRule.shape[1])
    }
  }

  /// Device-resident winner fields for one page.
  public struct WinnerTensors {
    public let len: MLXArray
    public let priorityRank: MLXArray
    public let ruleID: MLXArray
    public let tokenKindID: MLXArray
    public let mode: MLXArray

    public init(
      len: MLXArray,
      priorityRank: MLXArray,
      ruleID: MLXArray,
      tokenKindID: MLXArray,
      mode: MLXArray
    ) {
      self.len = len.asType(.uint16)
      self.priorityRank = priorityRank.asType(.uint16)
      self.ruleID = ruleID.asType(.uint16)
      self.tokenKindID = tokenKindID.asType(.uint16)
      self.mode = mode.asType(.uint8)
    }
  }

  /// Candidate from a single rule at all positions.
  public struct RuleCandidate {
    public let ruleID: UInt16
    public let tokenKindID: UInt16
    public let priorityRank: UInt16
    public let mode: UInt8
    public let candLen: [UInt16]
    public let candLenTensor: MLXArray?

    public init(
      ruleID: UInt16,
      tokenKindID: UInt16,
      priorityRank: UInt16,
      mode: UInt8,
      candLen: [UInt16]
    ) {
      self.ruleID = ruleID
      self.tokenKindID = tokenKindID
      self.priorityRank = priorityRank
      self.mode = mode
      self.candLen = candLen
      self.candLenTensor = nil
    }

    public init(
      ruleID: UInt16,
      tokenKindID: UInt16,
      priorityRank: UInt16,
      mode: UInt8,
      candLenTensor: MLXArray
    ) {
      self.ruleID = ruleID
      self.tokenKindID = tokenKindID
      self.priorityRank = priorityRank
      self.mode = mode
      self.candLen = []
      self.candLenTensor = candLenTensor
    }

    public func hostCandLen(pageSize: Int) -> [UInt16] {
      if !candLen.isEmpty {
        precondition(candLen.count == pageSize, "RuleCandidate candLen count must equal pageSize")
        return candLen
      }
      guard let candLenTensor else {
        return Array(repeating: 0, count: pageSize)
      }
      let values = candLenTensor.asType(.uint16).asArray(UInt16.self)
      precondition(
        values.count == pageSize, "RuleCandidate candLen tensor count must equal pageSize")
      return values
    }
  }

  /// Compatibility helper for tests/legacy paths.
  /// Converts host-or-device candidates into a shared [rule, page] tensor batch.
  public static func makeRuleTensorBatch(candidates: [RuleCandidate], pageSize: Int)
    -> RuleTensorBatch
  {
    precondition(pageSize >= 0, "pageSize must be non-negative")

    let lengthRows = candidates.map { candidate in
      candidate.candLenTensor?.asType(.uint16)
        ?? uint16Tensor(candidate.hostCandLen(pageSize: pageSize))
    }
    let priorityRows = candidates.map { candidate in
      uint16Filled(value: candidate.priorityRank, count: pageSize)
    }
    let ruleRows = candidates.map { candidate in
      uint16Filled(value: candidate.ruleID, count: pageSize)
    }
    let tokenRows = candidates.map { candidate in
      uint16Filled(value: candidate.tokenKindID, count: pageSize)
    }
    let modeRows = candidates.map { candidate in
      uint8Filled(value: candidate.mode, count: pageSize)
    }

    return RuleTensorBatch(
      candLenByRule: stackRows(lengthRows, pageSize: pageSize, dtype: .uint16),
      priorityRankByRule: stackRows(priorityRows, pageSize: pageSize, dtype: .uint16),
      ruleIDByRule: stackRows(ruleRows, pageSize: pageSize, dtype: .uint16),
      tokenKindIDByRule: stackRows(tokenRows, pageSize: pageSize, dtype: .uint16),
      modeByRule: stackRows(modeRows, pageSize: pageSize, dtype: .uint8)
    )
  }

  /// Production tensor reduction (sequential loop on CPU).
  /// Tie-break order:
  ///   1. longer length
  ///   2. smaller priorityRank
  ///   3. smaller ruleID
  public static func reduce(batch: RuleTensorBatch, pageSize: Int) -> WinnerTensors {
    precondition(pageSize >= 0, "pageSize must be non-negative")
    precondition(batch.pageSize == pageSize, "batch.pageSize must match pageSize")

    guard pageSize > 0 else {
      return WinnerTensors(
        len: zeros([0], dtype: .uint16),
        priorityRank: zeros([0], dtype: .uint16),
        ruleID: zeros([0], dtype: .uint16),
        tokenKindID: zeros([0], dtype: .uint16),
        mode: zeros([0], dtype: .uint8)
      )
    }

    guard batch.ruleCount > 0 else {
      return WinnerTensors(
        len: zeros([pageSize], dtype: .uint16),
        priorityRank: uint16Filled(value: WinnerTuple.empty.priorityRank, count: pageSize),
        ruleID: uint16Filled(value: WinnerTuple.empty.ruleID, count: pageSize),
        tokenKindID: zeros([pageSize], dtype: .uint16),
        mode: zeros([pageSize], dtype: .uint8)
      )
    }

    var bestLen = zeros([pageSize], dtype: .uint16)
    var bestPriority = uint16Filled(value: WinnerTuple.empty.priorityRank, count: pageSize)
    var bestRuleID = uint16Filled(value: WinnerTuple.empty.ruleID, count: pageSize)
    var bestTokenKindID = zeros([pageSize], dtype: .uint16)
    var bestMode = zeros([pageSize], dtype: .uint8)

    for ruleIndex in 0..<batch.ruleCount {
      let candLen = batch.candLenByRule[ruleIndex].asType(.uint16)
      let candPriority = batch.priorityRankByRule[ruleIndex].asType(.uint16)
      let candRuleID = batch.ruleIDByRule[ruleIndex].asType(.uint16)
      let candTokenKindID = batch.tokenKindIDByRule[ruleIndex].asType(.uint16)
      let candMode = batch.modeByRule[ruleIndex].asType(.uint8)

      let longer = candLen .> bestLen
      let sameLen = candLen .== bestLen
      let positiveLen = candLen .> 0
      let betterPriority = candPriority .< bestPriority
      let samePriority = candPriority .== bestPriority
      let betterRuleID = candRuleID .< bestRuleID
      let tieBreak =
        sameLen .&& positiveLen .&& (betterPriority .|| (samePriority .&& betterRuleID))
      let contenderWins = longer .|| tieBreak

      bestLen = which(contenderWins, candLen, bestLen).asType(.uint16)
      bestPriority = which(contenderWins, candPriority, bestPriority).asType(.uint16)
      bestRuleID = which(contenderWins, candRuleID, bestRuleID).asType(.uint16)
      bestTokenKindID = which(contenderWins, candTokenKindID, bestTokenKindID).asType(.uint16)
      bestMode = which(contenderWins, candMode, bestMode).asType(.uint8)
    }

    return WinnerTensors(
      len: bestLen,
      priorityRank: bestPriority,
      ruleID: bestRuleID,
      tokenKindID: bestTokenKindID,
      mode: bestMode
    )
  }

  /// GPU-friendly reduction using argMax on a composite score.
  /// Fuses the entire rule competition into a single GPU kernel via MLX.compile.
  /// Tie-break order matches `reduce`: longer length > smaller priority > smaller ruleID.
  public static func reduceGPU(batch: RuleTensorBatch, pageSize: Int) -> WinnerTensors {
    precondition(pageSize >= 0, "pageSize must be non-negative")
    precondition(batch.pageSize == pageSize, "batch.pageSize must match pageSize")

    guard pageSize > 0 else {
      return WinnerTensors(
        len: zeros([0], dtype: .uint16),
        priorityRank: zeros([0], dtype: .uint16),
        ruleID: zeros([0], dtype: .uint16),
        tokenKindID: zeros([0], dtype: .uint16),
        mode: zeros([0], dtype: .uint8)
      )
    }

    guard batch.ruleCount > 0 else {
      return WinnerTensors(
        len: zeros([pageSize], dtype: .uint16),
        priorityRank: uint16Filled(value: WinnerTuple.empty.priorityRank, count: pageSize),
        ruleID: uint16Filled(value: WinnerTuple.empty.ruleID, count: pageSize),
        tokenKindID: zeros([pageSize], dtype: .uint16),
        mode: zeros([pageSize], dtype: .uint8)
      )
    }

    // Build composite score: encode (len, invPriority, invRuleID) as int64
    // so that argMax picks the correct winner with all tie-breaks.
    // len in bits [32..47], invPriority in bits [16..31], invRuleID in bits [0..15]
    let lenI64 = batch.candLenByRule.asType(.int64)
    let invPriority = (MLXArray(Int64(0xFFFF)) - batch.priorityRankByRule.asType(.int64))
    let invRuleID = (MLXArray(Int64(0xFFFF)) - batch.ruleIDByRule.asType(.int64))
    let score =
      lenI64 * MLXArray(Int64(1) << 32) + invPriority * MLXArray(Int64(1) << 16) + invRuleID

    // Mask out zero-length candidates so they never win
    let hasMatch = batch.candLenByRule.asType(.int64) .> MLXArray(Int64(0))
    let maskedScore = which(hasMatch, score, MLXArray(Int64(-1)))

    // argMax along rule axis → [pageSize] indices of winning rule
    let bestIdx = argMax(maskedScore, axis: 0).asType(.int32)  // [pageSize]
    let idxExpanded = bestIdx.expandedDimensions(axis: 0)  // [1, pageSize]

    // Gather winner fields
    let bestLen = takeAlong(batch.candLenByRule, idxExpanded, axis: 0).squeezed(axis: 0)
    let bestPriority = takeAlong(batch.priorityRankByRule, idxExpanded, axis: 0).squeezed(axis: 0)
    let bestRuleID = takeAlong(batch.ruleIDByRule, idxExpanded, axis: 0).squeezed(axis: 0)
    let bestTokenKindID = takeAlong(batch.tokenKindIDByRule, idxExpanded, axis: 0).squeezed(axis: 0)
    let bestMode = takeAlong(batch.modeByRule, idxExpanded, axis: 0).squeezed(axis: 0)

    // Zero out fields where no rule matched (len == 0 means empty)
    let anyMatch = bestLen .> MLXArray(UInt16(0))
    let emptyPriority = uint16Filled(value: WinnerTuple.empty.priorityRank, count: pageSize)
    let emptyRuleID = uint16Filled(value: WinnerTuple.empty.ruleID, count: pageSize)

    return WinnerTensors(
      len: bestLen.asType(.uint16),
      priorityRank: which(anyMatch, bestPriority, emptyPriority).asType(.uint16),
      ruleID: which(anyMatch, bestRuleID, emptyRuleID).asType(.uint16),
      tokenKindID: which(anyMatch, bestTokenKindID, zeros([pageSize], dtype: .uint16)).asType(
        .uint16),
      mode: which(anyMatch, bestMode, zeros([pageSize], dtype: .uint8)).asType(.uint8)
    )
  }

  /// Host conversion helper for tests and host-only selector paths.
  public static func hostWinners(from tensors: WinnerTensors, pageSize: Int) -> [WinnerTuple] {
    precondition(pageSize >= 0, "pageSize must be non-negative")

    let len = tensors.len.asType(.uint16).asArray(UInt16.self)
    let priority = tensors.priorityRank.asType(.uint16).asArray(UInt16.self)
    let ruleID = tensors.ruleID.asType(.uint16).asArray(UInt16.self)
    let tokenKindID = tensors.tokenKindID.asType(.uint16).asArray(UInt16.self)
    let mode = tensors.mode.asType(.uint8).asArray(UInt8.self)
    precondition(
      len.count == pageSize
        && priority.count == pageSize
        && ruleID.count == pageSize
        && tokenKindID.count == pageSize
        && mode.count == pageSize,
      "winner tensor fields must all match pageSize"
    )

    return (0..<pageSize).map { index in
      if len[index] == 0 {
        return .empty
      }
      return WinnerTuple(
        len: len[index],
        priorityRank: priority[index],
        ruleID: ruleID[index],
        tokenKindID: tokenKindID[index],
        mode: mode[index]
      )
    }
  }

  /// Compatibility reducer; routes through the tensor reducer.
  public static func reduce(candidates: [RuleCandidate], pageSize: Int) -> [WinnerTuple] {
    let batch = makeRuleTensorBatch(candidates: candidates, pageSize: pageSize)
    let winnerTensors = reduce(batch: batch, pageSize: pageSize)
    return hostWinners(from: winnerTensors, pageSize: pageSize)
  }

  /// Pairwise merge two winner arrays element-wise.
  public static func pairwiseMerge(_ a: [WinnerTuple], _ b: [WinnerTuple]) -> [WinnerTuple] {
    precondition(a.count == b.count, "Winner arrays must have equal length")

    var merged: [WinnerTuple] = []
    merged.reserveCapacity(a.count)

    for index in a.indices {
      let lhs = a[index]
      let rhs = b[index]
      merged.append(rhs.isBetterThan(lhs) ? rhs : lhs)
    }

    return merged
  }
}

private func stackRows(_ rows: [MLXArray], pageSize: Int, dtype: DType) -> MLXArray {
  guard !rows.isEmpty else { return zeros([0, pageSize], dtype: dtype) }
  let normalized = rows.map { $0.asType(dtype) }
  return stacked(normalized, axis: 0)
}

private func uint16Tensor(_ values: [UInt16]) -> MLXArray {
  MLXArray(values, [values.count]).asType(.uint16)
}

private func uint16Filled(value: UInt16, count: Int) -> MLXArray {
  broadcast(MLXArray(value).asType(.uint16), to: [count])
}

private func uint8Filled(value: UInt8, count: Int) -> MLXArray {
  broadcast(MLXArray(value).asType(.uint8), to: [count])
}

public struct CandidateWinner: Sendable, Equatable {
  public let position: Int
  public let len: UInt16
  public let priorityRank: UInt16
  public let ruleID: UInt16
  public let tokenKindID: UInt16
  public let mode: UInt8

  public init(
    position: Int,
    len: UInt16,
    priorityRank: UInt16,
    ruleID: UInt16,
    tokenKindID: UInt16,
    mode: UInt8
  ) {
    self.position = position
    self.len = len
    self.priorityRank = priorityRank
    self.ruleID = ruleID
    self.tokenKindID = tokenKindID
    self.mode = mode
  }

  public static func noMatch(at position: Int) -> CandidateWinner {
    CandidateWinner(
      position: position,
      len: 0,
      priorityRank: 0,
      ruleID: 0,
      tokenKindID: 0,
      mode: 0
    )
  }
}

public func reduceBucketWinners(buckets: [[CandidateWinner]]) -> [CandidateWinner] {
  let maxPosition =
    buckets
    .flatMap(\.self)
    .map(\.position)
    .max() ?? -1

  guard maxPosition >= 0 else { return [] }

  var reduced = (0...maxPosition).map(CandidateWinner.noMatch(at:))

  for bucket in buckets {
    for candidate in bucket where candidate.position >= 0 && candidate.position <= maxPosition {
      if isBetterCandidate(candidate, than: reduced[candidate.position]) {
        reduced[candidate.position] = candidate
      }
    }
  }

  return reduced
}

public func integrateWithFallback(
  fastWinners: WinnerReduction.WinnerTensors,
  fallbackResult: FallbackPageResult,
  pageWidth: Int
) -> WinnerReduction.WinnerTensors {
  guard pageWidth > 0 else {
    return WinnerReduction.WinnerTensors(
      len: zeros([0], dtype: .uint16),
      priorityRank: zeros([0], dtype: .uint16),
      ruleID: zeros([0], dtype: .uint16),
      tokenKindID: zeros([0], dtype: .uint16),
      mode: zeros([0], dtype: .uint8)
    )
  }

  let fallbackLen = MLXArray(
    normalized(
      fallbackResult.fallbackLen, count: pageWidth, fill: 0
    ),
    [pageWidth]
  ).asType(.uint16)
  let fallbackPriority = MLXArray(
    normalized(
      fallbackResult.fallbackPriorityRank, count: pageWidth, fill: 0
    ),
    [pageWidth]
  ).asType(.uint16)
  let fallbackRuleID = MLXArray(
    normalized(
      fallbackResult.fallbackRuleID, count: pageWidth, fill: 0
    ),
    [pageWidth]
  ).asType(.uint16)
  let fallbackTokenKindID = MLXArray(
    normalized(
      fallbackResult.fallbackTokenKindID, count: pageWidth, fill: 0
    ),
    [pageWidth]
  ).asType(.uint16)
  let fallbackMode = MLXArray(
    normalized(
      fallbackResult.fallbackMode, count: pageWidth, fill: 0
    ),
    [pageWidth]
  ).asType(.uint8)

  let fastLen = fastWinners.len.asType(.uint16)
  let fastPriority = fastWinners.priorityRank.asType(.uint16)
  let fastRuleID = fastWinners.ruleID.asType(.uint16)
  let fastTokenKindID = fastWinners.tokenKindID.asType(.uint16)
  let fastMode = fastWinners.mode.asType(.uint8)

  let longer = fallbackLen .> fastLen
  let sameLen = fallbackLen .== fastLen
  let positiveLen = fallbackLen .> 0
  let betterPriority = fallbackPriority .< fastPriority
  let samePriority = fallbackPriority .== fastPriority
  let betterRuleID = fallbackRuleID .< fastRuleID
  let tieBreak = sameLen .&& positiveLen .&& (betterPriority .|| (samePriority .&& betterRuleID))
  let fallbackWins = longer .|| tieBreak

  return WinnerReduction.WinnerTensors(
    len: which(fallbackWins, fallbackLen, fastLen).asType(.uint16),
    priorityRank: which(fallbackWins, fallbackPriority, fastPriority).asType(.uint16),
    ruleID: which(fallbackWins, fallbackRuleID, fastRuleID).asType(.uint16),
    tokenKindID: which(fallbackWins, fallbackTokenKindID, fastTokenKindID).asType(.uint16),
    mode: which(fallbackWins, fallbackMode, fastMode).asType(.uint8)
  )
}

public func integrateWithFallback(
  fastWinners: [WinnerTuple],
  fallbackResult: FallbackPageResult,
  pageWidth: Int
) -> [WinnerTuple] {
  guard pageWidth > 0 else { return [] }

  var integrated = normalizedWinners(fastWinners, pageWidth: pageWidth)
  for position in 0..<pageWidth {
    let fallback = WinnerTuple(
      len: value(at: position, in: fallbackResult.fallbackLen),
      priorityRank: value(at: position, in: fallbackResult.fallbackPriorityRank),
      ruleID: value(at: position, in: fallbackResult.fallbackRuleID),
      tokenKindID: value(at: position, in: fallbackResult.fallbackTokenKindID),
      mode: value(at: position, in: fallbackResult.fallbackMode)
    )

    if fallback.isBetterThan(integrated[position]) {
      integrated[position] = fallback
    }
  }

  return integrated
}

private func normalized<T>(_ values: [T], count: Int, fill: T) -> [T] {
  guard count > 0 else { return [] }
  if values.count == count { return values }
  if values.count > count { return Array(values.prefix(count)) }
  return values + Array(repeating: fill, count: count - values.count)
}

public func integrateWithFallback(
  fastWinners: [CandidateWinner],
  fallbackResult: FallbackPageResult,
  pageWidth: Int
) -> [CandidateWinner] {
  let integrated = integrateWithFallback(
    fastWinners: normalizedWinners(fastWinners, pageWidth: pageWidth).map(asWinnerTuple),
    fallbackResult: fallbackResult,
    pageWidth: pageWidth
  )

  return integrated.enumerated().map { position, winner in
    candidateWinner(from: winner, position: position)
  }
}

private func normalizedWinners(_ winners: [WinnerTuple], pageWidth: Int) -> [WinnerTuple] {
  guard pageWidth > 0 else { return [] }
  guard winners.count != pageWidth else { return winners }

  var normalized = Array(repeating: WinnerTuple.empty, count: pageWidth)
  for (position, winner) in winners.enumerated() where position < pageWidth {
    normalized[position] = winner
  }
  return normalized
}

private func normalizedWinners(_ winners: [CandidateWinner], pageWidth: Int) -> [CandidateWinner] {
  guard pageWidth > 0 else { return [] }

  var normalized = (0..<pageWidth).map(CandidateWinner.noMatch(at:))
  for winner in winners where winner.position >= 0 && winner.position < pageWidth {
    if isBetterCandidate(winner, than: normalized[winner.position]) {
      normalized[winner.position] = winner
    }
  }
  return normalized
}

private func value<T>(at index: Int, in values: [T], default defaultValue: T) -> T {
  guard index >= 0, index < values.count else { return defaultValue }
  return values[index]
}

private func value(at index: Int, in values: [UInt16]) -> UInt16 {
  value(at: index, in: values, default: 0)
}

private func value(at index: Int, in values: [UInt8]) -> UInt8 {
  value(at: index, in: values, default: 0)
}

private func isBetterCandidate(_ lhs: CandidateWinner, than rhs: CandidateWinner) -> Bool {
  if lhs.len != rhs.len { return lhs.len > rhs.len }
  if lhs.len == 0 { return false }
  if lhs.priorityRank != rhs.priorityRank { return lhs.priorityRank < rhs.priorityRank }
  return lhs.ruleID < rhs.ruleID
}

private func asWinnerTuple(_ candidate: CandidateWinner) -> WinnerTuple {
  if candidate.len == 0 {
    return .empty
  }

  return WinnerTuple(
    len: candidate.len,
    priorityRank: candidate.priorityRank,
    ruleID: candidate.ruleID,
    tokenKindID: candidate.tokenKindID,
    mode: candidate.mode
  )
}

func candidateWinner(from winner: WinnerTuple, position: Int) -> CandidateWinner {
  CandidateWinner(
    position: position,
    len: winner.len,
    priorityRank: winner.len == 0 ? 0 : winner.priorityRank,
    ruleID: winner.len == 0 ? 0 : winner.ruleID,
    tokenKindID: winner.len == 0 ? 0 : winner.tokenKindID,
    mode: winner.len == 0 ? 0 : winner.mode
  )
}
