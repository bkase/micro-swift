import Foundation
import MLX

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
  private let reduceAndSelectGraph: @Sendable ([MLXArray]) -> [MLXArray]

  public init(pageSize: Int) {
    precondition(pageSize >= 0, "pageSize must be non-negative")
    self.pageSize = pageSize
    let rawGraph: @Sendable ([MLXArray]) -> [MLXArray] = { tensors in
      Self.reduceAndSelectGraph(tensors: tensors, pageSize: pageSize)
    }
    self.reduceAndSelectGraph =
      Self.shouldUseMLXCompile()
      ? compile(rawGraph)
      : rawGraph
  }

  public func execute(
    candidateBatch: WinnerReduction.RuleTensorBatch,
    fallbackResult: FallbackPageResult,
    validMaskTensor: MLXArray
  ) -> GreedySelector.SelectedTokenTensors {
    let fallbackWinners = makeFallbackWinnerTensors(
      fallbackResult: fallbackResult, pageSize: pageSize)
    let outputs = reduceAndSelectGraph([
      candidateBatch.candLenByRule,
      candidateBatch.priorityRankByRule,
      candidateBatch.ruleIDByRule,
      candidateBatch.tokenKindIDByRule,
      candidateBatch.modeByRule,
      fallbackWinners.len,
      fallbackWinners.priorityRank,
      fallbackWinners.ruleID,
      fallbackWinners.tokenKindID,
      fallbackWinners.mode,
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

  private static func reduceAndSelectGraph(tensors: [MLXArray], pageSize: Int) -> [MLXArray] {
    precondition(tensors.count == 11, "compiled fast-path graph expects 11 inputs")

    let batch = WinnerReduction.RuleTensorBatch(
      candLenByRule: tensors[0],
      priorityRankByRule: tensors[1],
      ruleIDByRule: tensors[2],
      tokenKindIDByRule: tensors[3],
      modeByRule: tensors[4]
    )
    let fallbackWinners = WinnerReduction.WinnerTensors(
      len: tensors[5],
      priorityRank: tensors[6],
      ruleID: tensors[7],
      tokenKindID: tensors[8],
      mode: tensors[9]
    )
    let validMask = tensors[10].asType(.bool)

    let fastWinners = WinnerReduction.reduce(batch: batch, pageSize: pageSize)
    let merged = mergeFastAndFallback(
      fastWinners: fastWinners,
      fallbackWinners: fallbackWinners,
      validMask: validMask,
      pageSize: pageSize
    )
    let selected = GreedySelector.select(winnerTensors: merged, validLen: Int32(pageSize))

    return [
      selected.startPos,
      selected.length,
      selected.ruleID,
      selected.tokenKindID,
      selected.mode,
      selected.selectedMask,
    ]
  }

  private static func shouldUseMLXCompile() -> Bool {
    let env = ProcessInfo.processInfo.environment
    return env["MICROSWIFT_ENABLE_MLX_COMPILE"] == "1"
  }
}

private func mergeFastAndFallback(
  fastWinners: WinnerReduction.WinnerTensors,
  fallbackWinners: WinnerReduction.WinnerTensors,
  validMask: MLXArray,
  pageSize: Int
) -> WinnerReduction.WinnerTensors {
  withMLXCPU {
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
}

private func makeFallbackWinnerTensors(
  fallbackResult: FallbackPageResult,
  pageSize: Int
) -> WinnerReduction.WinnerTensors {
  withMLXCPU {
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
