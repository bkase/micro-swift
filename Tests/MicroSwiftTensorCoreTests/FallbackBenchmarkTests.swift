import Foundation
import Testing

@testable import MicroSwiftLexerGen
@testable import MicroSwiftTensorCore

@Suite
struct FallbackBenchmarkTests {
  @Test(.enabled(if: requiresMLXEval))
  func benchmarkModesProduceValidResults() throws {
    let artifact = try makeRuntimeArtifact()
    let bytes = Array("if abc _a1 z9 if abc".utf8)

    let cold = runBenchmark(
      bytes: bytes,
      artifact: artifact,
      config: BenchmarkConfig(mode: .cold, iterations: 5, seed: 1)
    )
    let warm = runBenchmark(
      bytes: bytes,
      artifact: artifact,
      config: BenchmarkConfig(mode: .warm, iterations: 3, seed: 1)
    )
    let error = runBenchmark(
      bytes: bytes,
      artifact: artifact,
      config: BenchmarkConfig(mode: .error, iterations: 3, seed: 1)
    )

    for result in [cold, warm, error] {
      #expect(result.bytesPerSecond.isFinite)
      #expect(result.tokensPerSecond.isFinite)
      #expect(result.errorSpansPerSecond.isFinite)
      #expect(result.bytesPerSecond >= 0)
      #expect(result.tokensPerSecond >= 0)
      #expect(result.errorSpansPerSecond >= 0)
      #expect(result.wallTimeSeconds >= 0)
      #expect(result.graphCompilations >= 0)
      #expect(result.fallbackRuleCount >= 0)
      #expect(!result.cacheEvents.isEmpty)
    }

    #expect(cold.graphCompilations == 1)
    #expect(warm.graphCompilations == 1)
    #expect(error.errorSpansPerSecond >= 0)
  }

  @Test(.enabled(if: requiresMLXEval))
  func benchmarkResultJSONIsValid() throws {
    let artifact = try makeRuntimeArtifact()
    let bytes = Array("abc123 _a1".utf8)

    let result = runBenchmark(
      bytes: bytes,
      artifact: artifact,
      config: BenchmarkConfig(mode: .warm, iterations: 2, seed: 99)
    )

    let json = benchmarkResultJSON(result)
    let data = try #require(json.data(using: .utf8))

    let decoded = try JSONDecoder().decode(BenchmarkResult.self, from: data)
    #expect(decoded == result)
  }

  @Test(.enabled(if: requiresMLXEval))
  func benchmarkMetricsAreConsistent() throws {
    let artifact = try makeRuntimeArtifact()
    let bytes = Array("a_a_a_a_a_a".utf8)
    let iterations = 4

    let result = runBenchmark(
      bytes: bytes,
      artifact: artifact,
      config: BenchmarkConfig(mode: .warm, iterations: iterations, seed: 7)
    )

    let measuredRuns = result.pageBucketDistribution.values.reduce(0, +)
    #expect(measuredRuns == iterations)

    #expect(result.fallbackRuleCount > 0)

    let storeEvents = result.cacheEvents.filter { $0.event == "fast-path-graph-cache-store" }
    #expect(storeEvents.count == 1)
    #expect(storeEvents[0].runtimeMetadata?.backend == "mlx")
    #expect(storeEvents[0].runtimeMetadata?.pipelineFunction == "fastPathPageGraph")
  }

  private func makeRuntimeArtifact() throws -> ArtifactRuntime {
    let fixture = makeBoundedFallbackArtifactForTests(FallbackFixtures.singleRuleFallback())
    return try ArtifactRuntime.fromArtifact(fixture)
  }
}
