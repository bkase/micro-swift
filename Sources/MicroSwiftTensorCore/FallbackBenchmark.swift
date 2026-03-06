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
      wallTimeSeconds: 0
    )
  }

  let validLen = benchmarkBytes.count
  let pageBucket = pageBucketSize(for: validLen)

  var fallbackRunnerByBucket: [Int: FallbackKernelRunner] = [:]
  var graphCompilations = 0
  var observability = FallbackObservability()

  func executeSingleRun(recordMetrics: Bool) -> (tokenCount: Int, errorSpanCount: Int) {
    let classIDs = benchmarkBytes.map { UInt16(artifact.byteToClassLUT[Int($0)]) }

    let fallbackResult: FallbackPageResult
    if let fallback = artifact.fallback {
      let runner: FallbackKernelRunner
      if let cached = fallbackRunnerByBucket[pageBucket] {
        runner = cached
        observability.recordCacheHit()
      } else {
        runner = FallbackKernelRunner(fallback: fallback)
        fallbackRunnerByBucket[pageBucket] = runner
        graphCompilations += 1
        observability.recordCacheMiss()
      }

      if recordMetrics {
        var runObservability = FallbackObservability()
        fallbackResult = runner.evaluatePage(
          classIDs: classIDs,
          validLen: Int32(validLen),
          observability: &runObservability
        )
        observability.merge(runObservability)
      } else {
        fallbackResult = runner.evaluatePage(classIDs: classIDs, validLen: Int32(validLen))
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

    let integrated = integrateWithFallback(
      fastWinners: [],
      fallbackResult: fallbackResult,
      pageWidth: validLen
    )
    let selected = greedyNonOverlapSelect(winners: integrated, validLen: validLen)

    return (tokenCount: selected.count, errorSpanCount: countErrorSpans(validLen: validLen, selected: selected))
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

  return BenchmarkResult(
    bytesPerSecond: totalBytes / wallTimeSeconds,
    tokensPerSecond: Double(totalTokenCount) / wallTimeSeconds,
    errorSpansPerSecond: Double(totalErrorSpanCount) / wallTimeSeconds,
    graphCompilations: graphCompilations,
    pageBucketDistribution: pageBucketDistribution,
    fallbackPositionsEntered: observability.fallbackPositionsEntered,
    fallbackPositionsSkippedByStartMask: observability.fallbackPositionsSkippedByStartMask,
    fallbackCacheMisses: observability.fallbackCacheMisses,
    fallbackCacheHits: observability.fallbackCacheHits,
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

  for byte in UInt8.min...UInt8.max {
    let classID = UInt16(artifact.byteToClassLUT[Int(byte)])
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
  for index in output.indices {
    let pickEligible = rng.nextBit()
    output[index] = pickEligible ? eligible : ineligible
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

  mutating func nextBit() -> Bool {
    state = state &* 6364136223846793005 &+ 1442695040888963407
    return (state & 1) == 1
  }
}
