import Foundation
import MicroSwiftFrontend

public struct LexBenchmarkResult: Sendable, Codable {
  public let mode: String
  public let totalBytes: Int64
  public let totalTokens: Int
  public let durationNanos: UInt64
  public let bytesPerSecond: Double
  public let tokensPerSecond: Double
  public let errorSpansPerSecond: Double
  public let graphCompilationCount: Int
  public let pageBucketDistribution: [Int32: Int]

  public init(
    mode: String,
    totalBytes: Int64,
    totalTokens: Int,
    durationNanos: UInt64,
    bytesPerSecond: Double,
    tokensPerSecond: Double,
    errorSpansPerSecond: Double,
    graphCompilationCount: Int,
    pageBucketDistribution: [Int32: Int]
  ) {
    self.mode = mode
    self.totalBytes = totalBytes
    self.totalTokens = totalTokens
    self.durationNanos = durationNanos
    self.bytesPerSecond = bytesPerSecond
    self.tokensPerSecond = tokensPerSecond
    self.errorSpansPerSecond = errorSpansPerSecond
    self.graphCompilationCount = graphCompilationCount
    self.pageBucketDistribution = pageBucketDistribution
  }
}

public enum LexBenchmark {
  public static func benchmarkCold(
    source: SourceBuffer,
    artifact: ArtifactRuntime,
    iterations: Int
  ) -> LexBenchmarkResult {
    precondition(iterations > 0, "iterations must be > 0")

    let baselineMetrics = TensorLexer.fastPathGraphMetrics()
    let pagingShell = PagingShell()
    let pages = pagingShell.planAndPreparePages(source: source)
    let distribution = bucketDistribution(from: pages)

    var totalTokens = 0
    var totalErrorSpans = 0
    let start = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<iterations {
      let result = LexingShell(pagingShell: pagingShell).lexSource(
        source: source,
        artifact: artifact,
        options: LexOptions()
      )
      totalTokens += result.tokenTape.tokens.count
      totalErrorSpans += result.tokenTape.errorSpans.count
    }
    let durationNanos = DispatchTime.now().uptimeNanoseconds - start
    let totalBytes = Int64(source.bytes.count) * Int64(iterations)
    let finalMetrics = TensorLexer.fastPathGraphMetrics()

    return LexBenchmarkResult(
      mode: "cold",
      totalBytes: totalBytes,
      totalTokens: totalTokens,
      durationNanos: durationNanos,
      bytesPerSecond: rate(count: Double(totalBytes), durationNanos: durationNanos),
      tokensPerSecond: rate(count: Double(totalTokens), durationNanos: durationNanos),
      errorSpansPerSecond: rate(count: Double(totalErrorSpans), durationNanos: durationNanos),
      graphCompilationCount: max(0, finalMetrics.compileCount - baselineMetrics.compileCount),
      pageBucketDistribution: distribution
    )
  }

  public static func benchmarkWarm(
    source: SourceBuffer,
    artifact: ArtifactRuntime,
    warmupIterations: Int,
    measureIterations: Int
  ) -> LexBenchmarkResult {
    precondition(warmupIterations >= 0, "warmupIterations must be >= 0")
    precondition(measureIterations > 0, "measureIterations must be > 0")

    let baselineMetrics = TensorLexer.fastPathGraphMetrics()
    let pagingShell = PagingShell()
    let shell = LexingShell(pagingShell: pagingShell)
    let distribution = bucketDistribution(from: pagingShell.planAndPreparePages(source: source))

    for _ in 0..<warmupIterations {
      _ = shell.lexSource(source: source, artifact: artifact, options: LexOptions())
    }
    for _ in 1..<measureIterations {
      _ = shell.lexSource(source: source, artifact: artifact, options: LexOptions())
    }

    let start = DispatchTime.now().uptimeNanoseconds
    let measured = shell.lexSource(source: source, artifact: artifact, options: LexOptions())
    let durationNanos = DispatchTime.now().uptimeNanoseconds - start

    let totalBytes = Int64(source.bytes.count)
    let totalTokens = measured.tokenTape.tokens.count
    let errorSpanCount = measured.tokenTape.errorSpans.count
    let finalMetrics = TensorLexer.fastPathGraphMetrics()

    return LexBenchmarkResult(
      mode: "warm",
      totalBytes: totalBytes,
      totalTokens: totalTokens,
      durationNanos: durationNanos,
      bytesPerSecond: rate(count: Double(totalBytes), durationNanos: durationNanos),
      tokensPerSecond: rate(count: Double(totalTokens), durationNanos: durationNanos),
      errorSpansPerSecond: rate(count: Double(errorSpanCount), durationNanos: durationNanos),
      graphCompilationCount: max(0, finalMetrics.compileCount - baselineMetrics.compileCount),
      pageBucketDistribution: distribution
    )
  }

  public static func benchmarkError(
    source: SourceBuffer,
    artifact: ArtifactRuntime,
    iterations: Int
  ) -> LexBenchmarkResult {
    precondition(iterations > 0, "iterations must be > 0")

    let baselineMetrics = TensorLexer.fastPathGraphMetrics()
    let pagingShell = PagingShell()
    let shell = LexingShell(pagingShell: pagingShell)
    let distribution = bucketDistribution(from: pagingShell.planAndPreparePages(source: source))

    var totalTokens = 0
    var totalErrorSpans = 0
    let start = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<iterations {
      let result = shell.lexSource(source: source, artifact: artifact, options: LexOptions())
      totalTokens += result.tokenTape.tokens.count
      totalErrorSpans += result.tokenTape.errorSpans.count
    }
    let durationNanos = DispatchTime.now().uptimeNanoseconds - start
    let totalBytes = Int64(source.bytes.count) * Int64(iterations)
    let finalMetrics = TensorLexer.fastPathGraphMetrics()

    return LexBenchmarkResult(
      mode: "error",
      totalBytes: totalBytes,
      totalTokens: totalTokens,
      durationNanos: durationNanos,
      bytesPerSecond: rate(count: Double(totalBytes), durationNanos: durationNanos),
      tokensPerSecond: rate(count: Double(totalTokens), durationNanos: durationNanos),
      errorSpansPerSecond: rate(count: Double(totalErrorSpans), durationNanos: durationNanos),
      graphCompilationCount: max(0, finalMetrics.compileCount - baselineMetrics.compileCount),
      pageBucketDistribution: distribution
    )
  }

  private static func rate(count: Double, durationNanos: UInt64) -> Double {
    guard durationNanos > 0 else { return 0 }
    return count * 1_000_000_000 / Double(durationNanos)
  }

  private static func bucketDistribution(from pages: [PreparedPage]) -> [Int32: Int] {
    var distribution: [Int32: Int] = [:]
    distribution.reserveCapacity(pages.count)
    for page in pages {
      guard let bucket = page.bucket else { continue }
      distribution[bucket.byteCapacity, default: 0] += 1
    }
    return distribution
  }
}
