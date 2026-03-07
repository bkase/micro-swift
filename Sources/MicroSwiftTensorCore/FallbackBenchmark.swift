import Foundation

public enum BenchmarkMode: String, Codable, Sendable {
  case cold
  case warm
  case error
}

public struct BenchmarkConfig: Sendable {
  public let mode: BenchmarkMode
  public let iterations: Int
  public let seed: UInt64?

  public init(mode: BenchmarkMode, iterations: Int = 1, seed: UInt64? = nil) {
    self.mode = mode
    self.iterations = iterations
    self.seed = seed
  }
}

public struct BenchmarkResult: Codable, Sendable, Equatable {
  public let bytesPerSecond: Double
  public let tokensPerSecond: Double
  public let errorSpansPerSecond: Double
  public let graphCompilations: Int
  public let pageBucketDistribution: [Int: Int]
  public let fallbackPositionsEntered: Int
  public let fallbackPositionsSkippedByStartMask: Int
  public let fallbackCacheMisses: Int
  public let fallbackCacheHits: Int
  public let fallbackKernelBackendDispatches: Int
  public let cacheEvents: [KernelCacheLog]
  public let wallTimeSeconds: Double

  public init(
    bytesPerSecond: Double,
    tokensPerSecond: Double,
    errorSpansPerSecond: Double,
    graphCompilations: Int,
    pageBucketDistribution: [Int: Int],
    fallbackPositionsEntered: Int,
    fallbackPositionsSkippedByStartMask: Int,
    fallbackCacheMisses: Int,
    fallbackCacheHits: Int,
    fallbackKernelBackendDispatches: Int,
    cacheEvents: [KernelCacheLog],
    wallTimeSeconds: Double
  ) {
    self.bytesPerSecond = bytesPerSecond
    self.tokensPerSecond = tokensPerSecond
    self.errorSpansPerSecond = errorSpansPerSecond
    self.graphCompilations = graphCompilations
    self.pageBucketDistribution = pageBucketDistribution
    self.fallbackPositionsEntered = fallbackPositionsEntered
    self.fallbackPositionsSkippedByStartMask = fallbackPositionsSkippedByStartMask
    self.fallbackCacheMisses = fallbackCacheMisses
    self.fallbackCacheHits = fallbackCacheHits
    self.fallbackKernelBackendDispatches = fallbackKernelBackendDispatches
    self.cacheEvents = cacheEvents
    self.wallTimeSeconds = wallTimeSeconds
  }
}

public func runBenchmark(
  bytes: [UInt8],
  artifact: ArtifactRuntime,
  config: BenchmarkConfig
) -> BenchmarkResult {
  let measuredIterations: Int
  switch config.mode {
  case .cold:
    measuredIterations = 1
  case .warm, .error:
    measuredIterations = max(1, config.iterations)
  }

  let benchmarkBytes =
    config.mode == .error
    ? makeErrorPathBytes(from: bytes, artifact: artifact, seed: config.seed)
    : bytes

  guard !benchmarkBytes.isEmpty else {
    return BenchmarkResult(
      bytesPerSecond: 0,
      tokensPerSecond: 0,
      errorSpansPerSecond: 0,
      graphCompilations: 0,
      pageBucketDistribution: [:],
      fallbackPositionsEntered: 0,
      fallbackPositionsSkippedByStartMask: 0,
      fallbackCacheMisses: 0,
      fallbackCacheHits: 0,
      fallbackKernelBackendDispatches: 0,
      cacheEvents: [],
      wallTimeSeconds: 0
    )
  }

  let validLen = benchmarkBytes.count
  let pageBucket = pageBucketSize(for: validLen)
  let byteToClassLUT = artifact.hostByteToClassLUT()

  let logSink = BenchmarkLogSink()
  let cache = KernelCache(logSink: logSink.record)

  let artifactHash = artifact.artifactHash

  var observability = FallbackObservability()

  func executeSingleRun(recordMetrics: Bool) -> (tokenCount: Int, errorSpanCount: Int) {
    let classIDs = benchmarkBytes.map { byteToClassLUT[Int($0)] }

    let fallbackResult: FallbackPageResult
    if let fallback = artifact.fallback {
      let cacheKey = KernelCacheKey(
        deviceID: FallbackMetalExecutorProvider.shared.cacheDeviceID,
        artifactHash: artifactHash,
        pageBucket: pageBucket,
        inputDType: "uint16"
      )
      let traceID = "bench-\(config.mode.rawValue)-\(UUID().uuidString)"

      let entry: KernelCacheEntry
      do {
        entry = try cache.getOrCreate(key: cacheKey, traceID: traceID) {
          let compiled = try FallbackMetalExecutorProvider.shared.compileKernel(fallback: fallback)
          return KernelCacheEntry(
            fallbackRunner: FallbackKernelRunner(fallback: fallback, compiledKernel: compiled),
            runtimeMetadata: compiled.metadata,
            createdAt: Date()
          )
        }
      } catch {
        preconditionFailure("Kernel cache resource creation failed: \(error)")
      }

      guard let fallbackRunner = entry.fallbackRunner else {
        preconditionFailure("Kernel cache entry missing fallback runner")
      }

      if recordMetrics {
        var runObservability = FallbackObservability()
        fallbackResult = fallbackRunner.evaluatePage(
          classIDs: classIDs,
          validLen: Int32(validLen),
          observability: &runObservability
        )
        observability.merge(runObservability)
      } else {
        fallbackResult = fallbackRunner.evaluatePage(
          classIDs: classIDs, validLen: Int32(validLen))
      }
    } else {
      fallbackResult = FallbackPageResult(
        fallbackLen: Array(repeating: 0, count: validLen),
        fallbackPriorityRank: Array(repeating: 0, count: validLen),
        fallbackRuleID: Array(repeating: 0, count: validLen),
        fallbackTokenKindID: Array(repeating: 0, count: validLen),
        fallbackMode: Array(repeating: 0, count: validLen)
      )
    }

    let fastWinners = executeFastFamilies(
      bytes: benchmarkBytes, classIDs: classIDs, validLen: validLen, artifact: artifact)

    let integrated = integrateWithFallback(
      fastWinners: fastWinners,
      fallbackResult: fallbackResult,
      pageWidth: validLen
    )
    let selected = greedyNonOverlapSelect(winners: integrated, validLen: validLen)

    return (
      tokenCount: selected.count,
      errorSpanCount: countErrorSpans(validLen: validLen, selected: selected)
    )
  }

  if config.mode == .warm {
    _ = executeSingleRun(recordMetrics: false)
  }

  let startNanos = DispatchTime.now().uptimeNanoseconds

  var totalTokenCount = 0
  var totalErrorSpanCount = 0
  var pageBucketDistribution: [Int: Int] = [:]

  for _ in 0..<measuredIterations {
    let iteration = executeSingleRun(recordMetrics: true)
    totalTokenCount += iteration.tokenCount
    totalErrorSpanCount += iteration.errorSpanCount
    pageBucketDistribution[pageBucket, default: 0] += 1
  }

  let elapsedNanos = DispatchTime.now().uptimeNanoseconds - startNanos
  let wallTimeSeconds = max(Double(elapsedNanos) / 1_000_000_000, 0.000_001)

  let totalBytes = Double(validLen * measuredIterations)
  let cacheEvents = logSink.decodedRecords()
  let cacheMisses = cacheEvents.filter { $0.event == "fallback-kernel-cache-miss" }.count
  let cacheHits = cacheEvents.filter { $0.event == "fallback-kernel-cache-hit" }.count
  let graphCompilations = cacheEvents.filter { $0.event == "fallback-kernel-cache-store" }.count

  return BenchmarkResult(
    bytesPerSecond: totalBytes / wallTimeSeconds,
    tokensPerSecond: Double(totalTokenCount) / wallTimeSeconds,
    errorSpansPerSecond: Double(totalErrorSpanCount) / wallTimeSeconds,
    graphCompilations: graphCompilations,
    pageBucketDistribution: pageBucketDistribution,
    fallbackPositionsEntered: observability.fallbackPositionsEntered,
    fallbackPositionsSkippedByStartMask: observability.fallbackPositionsSkippedByStartMask,
    fallbackCacheMisses: cacheMisses,
    fallbackCacheHits: cacheHits,
    fallbackKernelBackendDispatches: observability.fallbackKernelBackendDispatches,
    cacheEvents: cacheEvents,
    wallTimeSeconds: wallTimeSeconds
  )
}

public func benchmarkResultJSON(_ result: BenchmarkResult) -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

  guard
    let data = try? encoder.encode(result),
    let json = String(data: data, encoding: .utf8)
  else {
    return "{}"
  }

  return json
}

private final class BenchmarkLogSink: @unchecked Sendable {
  private let lock = NSLock()
  private var records: [String] = []

  func record(_ message: String) {
    lock.lock()
    records.append(message)
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

private func pageBucketSize(for length: Int) -> Int {
  guard length > 0 else { return 0 }

  var bucket = 1
  while bucket < length {
    bucket <<= 1
  }

  return bucket
}

private func countErrorSpans(validLen: Int, selected: [CandidateWinner]) -> Int {
  guard validLen > 0 else { return 0 }

  var covered = Array(repeating: false, count: validLen)
  for winner in selected where winner.len > 0 {
    let start = max(0, winner.position)
    let end = min(validLen, start + Int(winner.len))
    if start < end {
      for idx in start..<end {
        covered[idx] = true
      }
    }
  }

  var errorSpanCount = 0
  var index = 0

  while index < validLen {
    if covered[index] {
      index += 1
      continue
    }

    errorSpanCount += 1
    while index < validLen, !covered[index] {
      index += 1
    }
  }

  return errorSpanCount
}

private func makeErrorPathBytes(
  from bytes: [UInt8],
  artifact: ArtifactRuntime,
  seed: UInt64?
) -> [UInt8] {
  guard !bytes.isEmpty else { return [] }

  var startEligibleByte: UInt8?
  var startIneligibleByte: UInt8?
  let byteToClassLUT = artifact.hostByteToClassLUT()

  for byte in UInt8.min...UInt8.max {
    let classID = byteToClassLUT[Int(byte)]
    if isStartEligible(classID: classID, fallback: artifact.fallback) {
      if startEligibleByte == nil {
        startEligibleByte = byte
      }
    } else if startIneligibleByte == nil {
      startIneligibleByte = byte
    }

    if startEligibleByte != nil, startIneligibleByte != nil {
      break
    }
  }

  guard let ineligible = startIneligibleByte else {
    return bytes
  }

  guard let eligible = startEligibleByte else {
    return Array(repeating: ineligible, count: bytes.count)
  }

  var rng = LCRNG(seed: seed ?? 0xC0FFEE)
  var output = Array(repeating: UInt8(0), count: bytes.count)

  for idx in output.indices {
    let value = rng.next() & 0x1
    output[idx] = value == 0 ? ineligible : eligible
  }

  return output
}

private func isStartEligible(classID: UInt16, fallback: FallbackRuntime?) -> Bool {
  guard let fallback else { return false }

  if classID < 64 {
    let mask = UInt64(1) << UInt64(classID)
    return (fallback.startClassMaskLo & mask) != 0
  }
  if classID < 128 {
    let mask = UInt64(1) << UInt64(classID - 64)
    return (fallback.startClassMaskHi & mask) != 0
  }
  return false
}

private struct LCRNG {
  private var state: UInt64

  init(seed: UInt64) {
    self.state = seed
  }

  mutating func next() -> UInt64 {
    state = state &* 6_364_136_223_846_793_005 &+ 1
    return state
  }
}
