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
  private let pageSize: Int
  private let candidateAndSelectGraph: @Sendable ([MLXArray]) -> [MLXArray]

  public init(pageSize: Int, artifact: ArtifactRuntime) {
    precondition(pageSize >= 0, "pageSize must be non-negative")
    self.pageSize = pageSize

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

    let capturedLiteralRules = literalRules
    let capturedClassRunRules = classRunRules
    let capturedHeadTailRules = headTailRules
    let capturedPrefixedRules = prefixedRules
    let capturedRemapTables = remapTables
    let rawGraph: @Sendable ([MLXArray]) -> [MLXArray] = { tensors in
      Self.candidateAndSelectGraph(
        tensors: tensors, pageSize: pageSize,
        literalRules: capturedLiteralRules, classRunRules: capturedClassRunRules,
        headTailRules: capturedHeadTailRules, prefixedRules: capturedPrefixedRules,
        classSetRuntime: classSetRuntime,
        remapTables: capturedRemapTables
      )
    }
    self.candidateAndSelectGraph = compile(rawGraph)
  }

  public func execute(
    byteTensor: MLXArray,
    classIDTensor: MLXArray,
    validMaskTensor: MLXArray,
    fallbackResult: FallbackPageResult
  ) -> GreedySelector.SelectedTokenTensors {
    let fallbackWinners = makeFallbackWinnerTensors(
      fallbackResult: fallbackResult, pageSize: pageSize)
    let outputs = candidateAndSelectGraph([
      byteTensor.asType(.uint8),
      classIDTensor.asType(.uint16),
      validMaskTensor.asType(.bool),
      fallbackWinners.len,
      fallbackWinners.priorityRank,
      fallbackWinners.ruleID,
      fallbackWinners.tokenKindID,
      fallbackWinners.mode,
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

  private static func candidateAndSelectGraph(
    tensors: [MLXArray],
    pageSize: Int,
    literalRules: [LiteralRuleInfo],
    classRunRules: [ClassRunRuleInfo],
    headTailRules: [HeadTailRuleInfo],
    prefixedRules: [PrefixedRuleInfo],
    classSetRuntime: ClassSetRuntime,
    remapTables: [KeywordRemapTable]
  ) -> [MLXArray] {
    precondition(tensors.count == 8, "compiled fast-path graph expects 8 inputs")

    let byteTensor = tensors[0].asType(.uint8)
    let classIDTensor = tensors[1].asType(.uint16)
    let validMask = tensors[2].asType(.bool)
    let fallbackWinners = WinnerReduction.WinnerTensors(
      len: tensors[3],
      priorityRank: tensors[4],
      ruleID: tensors[5],
      tokenKindID: tensors[6],
      mode: tensors[7]
    )

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

    // Reduce → merge with fallback → greedy select
    let fastWinners = WinnerReduction.reduce(batch: batch, pageSize: pageSize)
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

private func makeFallbackWinnerTensors(
  fallbackResult: FallbackPageResult,
  pageSize: Int
) -> WinnerReduction.WinnerTensors {
  WinnerReduction.WinnerTensors(
      len: MLXArray(normalized(fallbackResult.fallbackLen, count: pageSize, fill: 0), [pageSize])
        .asType(.uint16),
      priorityRank: MLXArray(
        normalized(fallbackResult.fallbackPriorityRank, count: pageSize, fill: 0),
        [pageSize]
      ).asType(.uint16),
      ruleID: MLXArray(
        normalized(fallbackResult.fallbackRuleID, count: pageSize, fill: 0), [pageSize]
      )
      .asType(.uint16),
      tokenKindID: MLXArray(
        normalized(fallbackResult.fallbackTokenKindID, count: pageSize, fill: 0),
        [pageSize]
      ).asType(.uint16),
      mode: MLXArray(normalized(fallbackResult.fallbackMode, count: pageSize, fill: 0), [pageSize])
        .asType(.uint8)
    )
}

private func normalized<T>(_ values: [T], count: Int, fill: T) -> [T] {
  guard count > 0 else { return [] }
  if values.count == count { return values }
  if values.count > count { return Array(values.prefix(count)) }
  return values + Array(repeating: fill, count: count - values.count)
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

struct StableHash {
  private var value: UInt64 = 0xcbf2_9ce4_8422_2325

  mutating func combine<T: FixedWidthInteger>(_ number: T) {
    var littleEndian = number.littleEndian
    withUnsafeBytes(of: &littleEndian) { bytes in
      for byte in bytes {
        value ^= UInt64(byte)
        value &*= 0x100_0000_01b3
      }
    }
  }

  mutating func combineBytes<S: Sequence>(_ bytes: S) where S.Element == UInt8 {
    for byte in bytes {
      value ^= UInt64(byte)
      value &*= 0x100_0000_01b3
    }
  }

  mutating func combineString(_ value: String) {
    combineBytes(value.utf8)
    combine(UInt8(0xFF))
  }

  func hexDigest() -> String {
    String(format: "%016llx", value)
  }
}

func artifactRuntimeHash(_ artifact: ArtifactRuntime) -> String {
  var hasher = StableHash()
  hasher.combineString(artifact.specName)
  hasher.combine(UInt64(artifact.ruleCount))
  hasher.combine(UInt16(artifact.runtimeHints.maxLiteralLength))
  hasher.combine(UInt16(artifact.runtimeHints.maxBoundedRuleWidth))
  hasher.combine(UInt16(artifact.runtimeHints.maxDeterministicLookaheadBytes))

  let byteToClass = artifact.hostByteToClassLUT()
  hasher.combine(UInt64(byteToClass.count))
  for classID in byteToClass {
    hasher.combine(classID)
  }

  if let fallback = artifact.fallback {
    hasher.combine(UInt16(fallback.numStatesUsed))
    hasher.combine(UInt16(fallback.maxWidth))
    hasher.combine(UInt64(fallback.startMaskLo))
    hasher.combine(UInt64(fallback.startMaskHi))
    hasher.combine(UInt64(fallback.startClassMaskLo))
    hasher.combine(UInt64(fallback.startClassMaskHi))

    let stepLo = fallback.hostStepLo()
    hasher.combine(UInt64(stepLo.count))
    for value in stepLo {
      hasher.combine(value)
    }

    let stepHi = fallback.hostStepHi()
    hasher.combine(UInt64(stepHi.count))
    for value in stepHi {
      hasher.combine(value)
    }

    let acceptLoByRule = fallback.hostAcceptLoByRule()
    hasher.combine(UInt64(acceptLoByRule.count))
    for value in acceptLoByRule {
      hasher.combine(value)
    }

    let acceptHiByRule = fallback.hostAcceptHiByRule()
    hasher.combine(UInt64(acceptHiByRule.count))
    for value in acceptHiByRule {
      hasher.combine(value)
    }

    let globalRuleIDByFallbackRule = fallback.hostGlobalRuleIDByFallbackRule()
    hasher.combine(UInt64(globalRuleIDByFallbackRule.count))
    for value in globalRuleIDByFallbackRule {
      hasher.combine(value)
    }

    let priorityRankByFallbackRule = fallback.hostPriorityRankByFallbackRule()
    hasher.combine(UInt64(priorityRankByFallbackRule.count))
    for value in priorityRankByFallbackRule {
      hasher.combine(value)
    }

    let tokenKindIDByFallbackRule = fallback.hostTokenKindIDByFallbackRule()
    hasher.combine(UInt64(tokenKindIDByFallbackRule.count))
    for value in tokenKindIDByFallbackRule {
      hasher.combine(value)
    }

    let modeByFallbackRule = fallback.hostModeByFallbackRule()
    hasher.combine(UInt64(modeByFallbackRule.count))
    hasher.combineBytes(modeByFallbackRule)
  } else {
    hasher.combine(UInt8(0))
  }

  return hasher.hexDigest()
}
