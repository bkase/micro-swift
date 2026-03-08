import Foundation
import MLX
import MicroSwiftLexerGen

public struct FastPathGraphMetrics: Codable, Sendable, Equatable {
  public let compileCount: Int
  public let cacheHits: Int
  public let cacheMisses: Int
  public let cacheEvents: [KernelCacheLog]

  public init(
    compileCount: Int,
    cacheHits: Int,
    cacheMisses: Int,
    cacheEvents: [KernelCacheLog]
  ) {
    self.compileCount = compileCount
    self.cacheHits = cacheHits
    self.cacheMisses = cacheMisses
    self.cacheEvents = cacheEvents
  }
}

public struct FastPathCompiledGraph: Sendable {
  public enum ReductionBackend: String, Sendable, Equatable {
    case cpu = "cpu-reduction"
    case gpu = "gpu-reduction"
  }

  private let pageSize: Int
  private let reductionBackend: ReductionBackend
  private let candidateAndSelectGraph: @Sendable ([MLXArray]) -> [MLXArray]

  public init(
    pageSize: Int,
    artifact: ArtifactRuntime,
    reductionBackend: ReductionBackend = .cpu
  ) {
    precondition(pageSize >= 0, "pageSize must be non-negative")
    self.pageSize = pageSize
    self.reductionBackend = reductionBackend

    let buckets = RuleBuckets.build(from: artifact.rules)
    let classSetRuntime = artifact.classSetRuntime
    let remapTables = artifact.keywordRemaps

    let modeByte: (RuleMode) -> UInt8 = { $0 == .skip ? 1 : 0 }

    var literalRules: [LiteralRuleInfo] = []
    for literalLength in buckets.literalBuckets.keys.sorted() {
      guard let rules = buckets.literalBuckets[literalLength] else { continue }
      for rule in rules {
        guard case .literal(let literalBytes) = rule.plan else { continue }
        literalRules.append(
          LiteralRuleInfo(
            ruleID: rule.ruleID, tokenKindID: rule.tokenKindID,
            priorityRank: rule.priorityRank, mode: modeByte(rule.mode),
            literalBytes: literalBytes
          ))
      }
    }

    var classRunRules: [ClassRunRuleInfo] = []
    for rule in buckets.classRunRules {
      guard case .runClassRun(let bodyClassSetID, let minLength) = rule.plan else { continue }
      classRunRules.append(
        ClassRunRuleInfo(
          ruleID: rule.ruleID, tokenKindID: rule.tokenKindID,
          priorityRank: rule.priorityRank, mode: modeByte(rule.mode),
          bodyClassSetID: bodyClassSetID, minLength: minLength
        ))
    }

    var headTailRules: [HeadTailRuleInfo] = []
    for rule in buckets.headTailRules {
      guard case .runHeadTail(let headClassSetID, let tailClassSetID) = rule.plan else { continue }
      headTailRules.append(
        HeadTailRuleInfo(
          ruleID: rule.ruleID, tokenKindID: rule.tokenKindID,
          priorityRank: rule.priorityRank, mode: modeByte(rule.mode),
          headClassSetID: headClassSetID, tailClassSetID: tailClassSetID
        ))
    }

    var prefixedRules: [PrefixedRuleInfo] = []
    for rule in buckets.prefixedRules {
      guard case .runPrefixed(let prefix, let bodyClassSetID, let stopClassSetID) = rule.plan
      else { continue }
      prefixedRules.append(
        PrefixedRuleInfo(
          ruleID: rule.ruleID, tokenKindID: rule.tokenKindID,
          priorityRank: rule.priorityRank, mode: modeByte(rule.mode),
          prefix: prefix, bodyClassSetID: bodyClassSetID, stopClassSetID: stopClassSetID
        ))
    }

    let capturedFallbackRules: [FallbackRuleMLXInfo] = []

    let capturedLiteralRules = literalRules
    let capturedClassRunRules = classRunRules
    let capturedHeadTailRules = headTailRules
    let capturedPrefixedRules = prefixedRules
    let capturedRemapTables = remapTables
    let capturedReductionBackend = reductionBackend
    let rawGraph: @Sendable ([MLXArray]) -> [MLXArray] = { tensors in
      Self.candidateAndSelectGraph(
        tensors: tensors, pageSize: pageSize,
        literalRules: capturedLiteralRules, classRunRules: capturedClassRunRules,
        headTailRules: capturedHeadTailRules, prefixedRules: capturedPrefixedRules,
        fallbackRules: capturedFallbackRules,
        classSetRuntime: classSetRuntime,
        remapTables: capturedRemapTables,
        reductionBackend: capturedReductionBackend
      )
    }
    self.candidateAndSelectGraph = compile(rawGraph)
  }

  public func execute(
    byteTensor: MLXArray,
    classIDTensor: MLXArray,
    validMaskTensor: MLXArray
  ) -> GreedySelector.SelectedTokenTensors {
    let outputs = candidateAndSelectGraph([
      byteTensor.asType(.uint8),
      classIDTensor.asType(.uint16),
      validMaskTensor.asType(.bool),
    ])

    precondition(outputs.count == 6, "compiled fast-path graph must return 6 outputs")
    return GreedySelector.SelectedTokenTensors(
      startPos: outputs[0],
      length: outputs[1],
      ruleID: outputs[2],
      tokenKindID: outputs[3],
      mode: outputs[4],
      selectedMask: outputs[5]
    )
  }

  public var reductionBackendIdentifier: String {
    reductionBackend.rawValue
  }

  private struct LiteralRuleInfo: Sendable {
    let ruleID: UInt16
    let tokenKindID: UInt16
    let priorityRank: UInt16
    let mode: UInt8
    let literalBytes: [UInt8]
  }
  private struct ClassRunRuleInfo: Sendable {
    let ruleID: UInt16
    let tokenKindID: UInt16
    let priorityRank: UInt16
    let mode: UInt8
    let bodyClassSetID: UInt16
    let minLength: UInt16
  }
  private struct HeadTailRuleInfo: Sendable {
    let ruleID: UInt16
    let tokenKindID: UInt16
    let priorityRank: UInt16
    let mode: UInt8
    let headClassSetID: UInt16
    let tailClassSetID: UInt16
  }
  private struct PrefixedRuleInfo: Sendable {
    let ruleID: UInt16
    let tokenKindID: UInt16
    let priorityRank: UInt16
    let mode: UInt8
    let prefix: [UInt8]
    let bodyClassSetID: UInt16
    let stopClassSetID: UInt16?
  }

  struct FallbackRuleMLXInfo: @unchecked Sendable {
    let ruleID: UInt16
    let priorityRank: UInt16
    let tokenKindID: UInt16
    let mode: UInt8
    let maxWidth: Int
    let classCount: Int
    let startState: Int32
    let stateCount: Int
    let transitionTensor: MLXArray
    let acceptingMask: MLXArray
  }

  private static func candidateAndSelectGraph(
    tensors: [MLXArray],
    pageSize: Int,
    literalRules: [LiteralRuleInfo],
    classRunRules: [ClassRunRuleInfo],
    headTailRules: [HeadTailRuleInfo],
    prefixedRules: [PrefixedRuleInfo],
    fallbackRules: [FallbackRuleMLXInfo],
    classSetRuntime: ClassSetRuntime,
    remapTables: [KeywordRemapTable],
    reductionBackend: ReductionBackend
  ) -> [MLXArray] {
    precondition(tensors.count == 3, "compiled fast-path graph expects 3 inputs")

    let byteTensor = tensors[0].asType(.uint8)
    let classIDTensor = tensors[1].asType(.uint16)
    let validMask = tensors[2].asType(.bool)

    // Precompute shared tensor resources
    let indices = MLXArray(Int32(0)..<Int32(pageSize), [pageSize])
    let sentinelFill = broadcast(MLXArray(Int32(pageSize)), to: [pageSize])
    let invalidIndices = which(.!validMask, indices, sentinelFill)
    let nextInvalidTensor = cummin(invalidIndices, axis: 0, reverse: true)

    var lengthRows: [MLXArray] = []
    var priorityRows: [MLXArray] = []
    var ruleRows: [MLXArray] = []
    var tokenRows: [MLXArray] = []
    var modeRows: [MLXArray] = []

    let totalRules =
      literalRules.count + classRunRules.count + headTailRules.count + prefixedRules.count
    lengthRows.reserveCapacity(totalRules)
    priorityRows.reserveCapacity(totalRules)
    ruleRows.reserveCapacity(totalRules)
    tokenRows.reserveCapacity(totalRules)
    modeRows.reserveCapacity(totalRules)

    func appendRow(
      ruleID: UInt16, tokenKindID: UInt16, priorityRank: UInt16, mode: UInt8, candLen: MLXArray
    ) {
      lengthRows.append(candLen.asType(.uint16))
      priorityRows.append(broadcast(MLXArray(priorityRank).asType(.uint16), to: [pageSize]))
      ruleRows.append(broadcast(MLXArray(ruleID).asType(.uint16), to: [pageSize]))
      tokenRows.append(broadcast(MLXArray(tokenKindID).asType(.uint16), to: [pageSize]))
      modeRows.append(broadcast(MLXArray(mode).asType(.uint8), to: [pageSize]))
    }

    // Literal rules
    for rule in literalRules {
      appendRow(
        ruleID: rule.ruleID, tokenKindID: rule.tokenKindID,
        priorityRank: rule.priorityRank, mode: rule.mode,
        candLen: LiteralExecution.evaluateLiteralMLX(
          byteTensor: byteTensor, validMaskTensor: validMask,
          literalBytes: rule.literalBytes
        )
      )
    }

    // ClassRun rules
    for rule in classRunRules {
      appendRow(
        ruleID: rule.ruleID, tokenKindID: rule.tokenKindID,
        priorityRank: rule.priorityRank, mode: rule.mode,
        candLen: ClassRunExecution.evaluateClassRunMLX(
          classIDTensor: classIDTensor, validMaskTensor: validMask,
          bodyClassSetID: rule.bodyClassSetID, minLength: rule.minLength,
          classSetRuntime: classSetRuntime
        )
      )
    }

    // HeadTail rules
    for rule in headTailRules {
      appendRow(
        ruleID: rule.ruleID, tokenKindID: rule.tokenKindID,
        priorityRank: rule.priorityRank, mode: rule.mode,
        candLen: HeadTailExecution.evaluateHeadTailMLX(
          classIDTensor: classIDTensor, validMaskTensor: validMask,
          headClassSetID: rule.headClassSetID, tailClassSetID: rule.tailClassSetID,
          classSetRuntime: classSetRuntime
        )
      )
    }

    // Prefixed rules (with shared nextStop caching)
    var nextStopTensorBySetID: [UInt16: MLXArray] = [:]
    for rule in prefixedRules {
      let nextStopTensor: MLXArray?
      if let stopClassSetID = rule.stopClassSetID {
        if let cached = nextStopTensorBySetID[stopClassSetID] {
          nextStopTensor = cached
        } else {
          let stopMember = MembershipKernels.membershipMaskTensor(
            classIDTensor: classIDTensor, setID: stopClassSetID,
            classSetRuntime: classSetRuntime
          )
          let isStop = stopMember .&& validMask
          let stopIndices = which(isStop, indices, sentinelFill)
          let computed = cummin(stopIndices, axis: 0, reverse: true)
          nextStopTensorBySetID[stopClassSetID] = computed
          nextStopTensor = computed
        }
      } else {
        nextStopTensor = nil
      }

      appendRow(
        ruleID: rule.ruleID, tokenKindID: rule.tokenKindID,
        priorityRank: rule.priorityRank, mode: rule.mode,
        candLen: PrefixedExecution.evaluatePrefixedMLX(
          byteTensor: byteTensor, classIDTensor: classIDTensor,
          validMaskTensor: validMask, prefix: rule.prefix,
          bodyClassSetID: rule.bodyClassSetID,
          classSetRuntime: classSetRuntime,
          nextInvalidTensor: nextInvalidTensor,
          nextStopTensor: nextStopTensor
        )
      )
    }

    // Stack into batch
    let batch = WinnerReduction.RuleTensorBatch(
      candLenByRule: stackRowsInline(lengthRows, pageSize: pageSize, dtype: .uint16),
      priorityRankByRule: stackRowsInline(priorityRows, pageSize: pageSize, dtype: .uint16),
      ruleIDByRule: stackRowsInline(ruleRows, pageSize: pageSize, dtype: .uint16),
      tokenKindIDByRule: stackRowsInline(tokenRows, pageSize: pageSize, dtype: .uint16),
      modeByRule: stackRowsInline(modeRows, pageSize: pageSize, dtype: .uint8)
    )

    // Reduce fast-path winners
    let fastWinners =
      reductionBackend == .gpu
      ? WinnerReduction.reduceGPU(batch: batch, pageSize: pageSize)
      : WinnerReduction.reduce(batch: batch, pageSize: pageSize)

    // Evaluate fallback DFA rules using MLX gather ops
    let fallbackWinners = evaluateFallbackMLX(
      classIDTensor: classIDTensor,
      validMaskTensor: validMask,
      fallbackRules: fallbackRules,
      pageSize: pageSize
    )

    // Merge fast-path and fallback winners
    let merged = mergeFastAndFallback(
      fastWinners: fastWinners,
      fallbackWinners: fallbackWinners,
      validMask: validMask,
      pageSize: pageSize
    )
    let selected = GreedySelector.select(winnerTensors: merged, validLen: Int32(pageSize))

    // Apply keyword remap inside the compiled graph so MLX traces/fuses the loops
    let remappedTokenKindID = TransportEmitter.applyKeywordRemap(
      tokenTensors: selected,
      byteTensor: byteTensor,
      validLen: pageSize,
      remapTables: remapTables
    )

    return [
      selected.startPos,
      selected.length,
      selected.ruleID,
      remappedTokenKindID,
      selected.mode,
      selected.selectedMask,
    ]
  }

}

private func evaluateFallbackMLX(
  classIDTensor: MLXArray,
  validMaskTensor: MLXArray,
  fallbackRules: [FastPathCompiledGraph.FallbackRuleMLXInfo],
  pageSize: Int
) -> WinnerReduction.WinnerTensors {
  guard !fallbackRules.isEmpty else {
    return WinnerReduction.WinnerTensors(
      len: zeros([pageSize], dtype: .uint16),
      priorityRank: zeros([pageSize], dtype: .uint16),
      ruleID: zeros([pageSize], dtype: .uint16),
      tokenKindID: zeros([pageSize], dtype: .uint16),
      mode: zeros([pageSize], dtype: .uint8)
    )
  }

  // Evaluate each fallback rule independently and reduce
  var bestLen = zeros([pageSize], dtype: .uint16)
  var bestPriority = broadcast(
    MLXArray(WinnerTuple.empty.priorityRank).asType(.uint16), to: [pageSize])
  var bestRuleID = broadcast(MLXArray(WinnerTuple.empty.ruleID).asType(.uint16), to: [pageSize])
  var bestTokenKindID = zeros([pageSize], dtype: .uint16)
  var bestMode = zeros([pageSize], dtype: .uint8)

  for rule in fallbackRules {
    let ruleWinnerLen = evaluateSingleFallbackRuleMLX(
      classIDTensor: classIDTensor,
      validMaskTensor: validMaskTensor,
      rule: rule,
      pageSize: pageSize
    )

    // Merge this rule's results into best using standard tie-break
    let candPriority = broadcast(MLXArray(rule.priorityRank).asType(.uint16), to: [pageSize])
    let candRuleID = broadcast(MLXArray(rule.ruleID).asType(.uint16), to: [pageSize])
    let candTokenKindID = broadcast(MLXArray(rule.tokenKindID).asType(.uint16), to: [pageSize])
    let candMode = broadcast(MLXArray(rule.mode).asType(.uint8), to: [pageSize])

    let longer = ruleWinnerLen .> bestLen
    let sameLen = ruleWinnerLen .== bestLen
    let positiveLen = ruleWinnerLen .> MLXArray(UInt16(0))
    let betterPriority = candPriority .< bestPriority
    let samePriority = candPriority .== bestPriority
    let betterRuleIDCmp = candRuleID .< bestRuleID
    let tieBreak =
      sameLen .&& positiveLen .&& (betterPriority .|| (samePriority .&& betterRuleIDCmp))
    let contenderWins = longer .|| tieBreak

    bestLen = which(contenderWins, ruleWinnerLen, bestLen).asType(.uint16)
    bestPriority = which(contenderWins, candPriority, bestPriority).asType(.uint16)
    bestRuleID = which(contenderWins, candRuleID, bestRuleID).asType(.uint16)
    bestTokenKindID = which(contenderWins, candTokenKindID, bestTokenKindID).asType(.uint16)
    bestMode = which(contenderWins, candMode, bestMode).asType(.uint8)
  }

  return WinnerReduction.WinnerTensors(
    len: bestLen,
    priorityRank: bestPriority,
    ruleID: bestRuleID,
    tokenKindID: bestTokenKindID,
    mode: bestMode
  )
}

private func evaluateSingleFallbackRuleMLX(
  classIDTensor: MLXArray,
  validMaskTensor: MLXArray,
  rule: FastPathCompiledGraph.FallbackRuleMLXInfo,
  pageSize: Int
) -> MLXArray {
  // Every position starts at the DFA start state
  var currentState = broadcast(MLXArray(rule.startState), to: [pageSize])
  var bestLen = zeros([pageSize], dtype: .uint16)
  // Track which positions are still alive (haven't hit invalid class or end of valid range)
  var alive = validMaskTensor.asType(.bool)

  let classCountI32 = MLXArray(Int32(rule.classCount))

  for step in 0..<rule.maxWidth {
    // Get classIDs shifted forward by `step` positions
    let shiftedClassIDs = ShiftedTensorView.forward(classIDTensor, by: step).asType(.int32)
    let shiftedValid = ShiftedTensorView.forwardValidMask(validMaskTensor, by: step)

    // Kill positions where classID is out of bounds or position is beyond valid range
    let classInBounds = shiftedClassIDs .< classCountI32
    let aliveNext = alive .&& shiftedValid .&& classInBounds
    alive = aliveNext

    // Clamp classIDs to prevent out-of-bounds gather (dead positions get garbage but alive masks them)
    let safeClassIDs = minimum(shiftedClassIDs, classCountI32 - MLXArray(Int32(1)))

    // Compute flat transition table index: state * classCount + classID
    let flatIndex = currentState * classCountI32 + safeClassIDs

    // Gather next states from transition table
    let nextState = rule.transitionTensor.take(flatIndex, axis: 0)
    currentState = nextState

    // Check if current state is accepting (only for alive positions)
    let isAccepting = rule.acceptingMask.take(currentState, axis: 0) .&& alive

    // Update best length where we found an accepting state
    let candidateLen = broadcast(MLXArray(UInt16(step + 1)), to: [pageSize])
    let updatedBestLen = which(isAccepting, candidateLen, bestLen).asType(.uint16)
    bestLen = updatedBestLen
  }

  return bestLen
}

private func stackRowsInline(_ rows: [MLXArray], pageSize: Int, dtype: DType) -> MLXArray {
  guard !rows.isEmpty else { return zeros([0, pageSize], dtype: dtype) }
  return stacked(rows.map { $0.asType(dtype) }, axis: 0)
}

private func mergeFastAndFallback(
  fastWinners: WinnerReduction.WinnerTensors,
  fallbackWinners: WinnerReduction.WinnerTensors,
  validMask: MLXArray,
  pageSize: Int
) -> WinnerReduction.WinnerTensors {
  let valid = validMask.asType(.bool)
  let zeroU16 = zeros([pageSize], dtype: .uint16)
  let zeroU8 = zeros([pageSize], dtype: .uint8)

  let fastLen = which(valid, fastWinners.len.asType(.uint16), zeroU16).asType(.uint16)
  let fastPriority = which(valid, fastWinners.priorityRank.asType(.uint16), zeroU16).asType(
    .uint16)
  let fastRuleID = which(valid, fastWinners.ruleID.asType(.uint16), zeroU16).asType(.uint16)
  let fastTokenKindID = which(valid, fastWinners.tokenKindID.asType(.uint16), zeroU16).asType(
    .uint16)
  let fastMode = which(valid, fastWinners.mode.asType(.uint8), zeroU8).asType(.uint8)

  let fallbackLen = which(valid, fallbackWinners.len.asType(.uint16), zeroU16).asType(.uint16)
  let fallbackPriority = which(valid, fallbackWinners.priorityRank.asType(.uint16), zeroU16)
    .asType(.uint16)
  let fallbackRuleID = which(valid, fallbackWinners.ruleID.asType(.uint16), zeroU16).asType(
    .uint16)
  let fallbackTokenKindID = which(
    valid,
    fallbackWinners.tokenKindID.asType(.uint16),
    zeroU16
  ).asType(.uint16)
  let fallbackMode = which(valid, fallbackWinners.mode.asType(.uint8), zeroU8).asType(.uint8)

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

final class KernelCacheLogSink: @unchecked Sendable {
  private let lock = NSLock()
  private var records: [String] = []

  func record(_ message: String) {
    lock.lock()
    records.append(message)
    lock.unlock()
  }

  func clear() {
    lock.lock()
    records.removeAll(keepingCapacity: true)
    lock.unlock()
  }

  func decodedRecords() -> [KernelCacheLog] {
    lock.lock()
    let snapshot = records
    lock.unlock()

    let decoder = JSONDecoder()
    return snapshot.compactMap { try? decoder.decode(KernelCacheLog.self, from: Data($0.utf8)) }
  }
}
