import Foundation
import MicroSwiftFrontend
import MicroSwiftLexerGen
import Testing

@testable import MicroSwiftTensorCore

@Suite
struct LexBenchmarkTests {
  @Test
  func coldBenchmarkProducesValidResult() throws {
    let runtime = try makeMicroSwiftRuntime()
    let source = makeSource(repeating: "let x = 42\n", count: 1_000)

    let result = LexBenchmark.benchmarkCold(source: source, artifact: runtime, iterations: 2)

    #expect(result.mode == "cold")
    #expect(result.totalBytes == Int64(source.bytes.count * 2))
    #expect(result.totalTokens > 0)
    #expect(result.durationNanos > 0)
    #expect(result.bytesPerSecond.isFinite)
    #expect(result.tokensPerSecond.isFinite)
    #expect(!result.pageBucketDistribution.isEmpty)
  }

  @Test
  func warmBenchmarkShowsConsistentTiming() throws {
    let runtime = try makeMicroSwiftRuntime()
    let source = makeSource(repeating: "func foo() -> Int { return 1 }\n", count: 4_000)

    let first = LexBenchmark.benchmarkWarm(
      source: source,
      artifact: runtime,
      warmupIterations: 2,
      measureIterations: 3
    )
    let second = LexBenchmark.benchmarkWarm(
      source: source,
      artifact: runtime,
      warmupIterations: 2,
      measureIterations: 3
    )

    #expect(first.mode == "warm")
    #expect(first.totalBytes == Int64(source.bytes.count))
    #expect(first.totalTokens == second.totalTokens)
    #expect(first.durationNanos > 0)
    #expect(second.durationNanos > 0)

    let ratio = Double(max(first.durationNanos, second.durationNanos))
      / Double(min(first.durationNanos, second.durationNanos))
    #expect(ratio < 10.0)
  }

  @Test
  func reportGeneratesValidJSON() throws {
    let result = LexBenchmarkResult(
      mode: "warm",
      totalBytes: 1024,
      totalTokens: 128,
      durationNanos: 2_000_000,
      bytesPerSecond: 512_000.0,
      tokensPerSecond: 64_000.0,
      errorSpansPerSecond: 0.0,
      graphCompilationCount: 0,
      pageBucketDistribution: [4096: 1]
    )

    let json = BenchmarkReport.toJSON(result)
    let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]

    #expect(parsed?["mode"] as? String == "warm")
    #expect(parsed?["totalBytes"] as? Int == 1024)
    #expect(parsed?["durationNanos"] as? Int == 2_000_000)
    #expect(parsed?["graphCompilationCount"] as? Int == 0)
  }

  private func makeSource(repeating line: String, count: Int) -> SourceBuffer {
    let text = String(repeating: line, count: count)
    return SourceBuffer(
      fileID: FileID(rawValue: 99),
      path: "bench.swift",
      bytes: Data(text.utf8)
    )
  }

  private func makeMicroSwiftRuntime() throws -> ArtifactRuntime {
    let declared = microSwiftV0.declare()
    let normalized = DeclaredSpec.normalize(declared)
    let validated = try NormalizedSpec.validate(normalized)
    let byteClasses = validated.buildByteClasses()
    let classSets = validated.buildClassSets(using: byteClasses)
    let classified = try validated.classifyRules(byteClasses: byteClasses, classSets: classSets)
    let artifact = try ArtifactSerializer.build(
      classified: classified,
      byteClasses: byteClasses,
      classSets: classSets,
      generatorVersion: "test"
    )
    return try ArtifactLoader.load(artifact)
  }
}
