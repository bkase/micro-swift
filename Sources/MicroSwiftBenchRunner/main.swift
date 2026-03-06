import Foundation
import MicroSwiftFrontend
import MicroSwiftLexerGen
import MicroSwiftTensorCore

func makeMicroSwiftRuntime() throws -> ArtifactRuntime {
  let declared = microSwiftV0.declare()
  let normalized = DeclaredSpec.normalize(declared)
  let validated = try NormalizedSpec.validate(normalized)
  let byteClasses = validated.buildByteClasses()
  let classSets = validated.buildClassSets(using: byteClasses)
  let classified = try validated.classifyRules(byteClasses: byteClasses, classSets: classSets)
  let artifact = try ArtifactSerializer.build(
    classified: classified, byteClasses: byteClasses, classSets: classSets,
    generatorVersion: "bench"
  )
  return try ArtifactLoader.load(artifact)
}

func makeSource(_ text: String) -> SourceBuffer {
  SourceBuffer(fileID: FileID(rawValue: 1), path: "bench.swift", bytes: Data(text.utf8))
}

func printResult(_ label: String, _ r: LexBenchmarkResult) {
  let mbps = r.bytesPerSecond / 1_000_000
  let ktps = r.tokensPerSecond / 1_000
  let ms = Double(r.durationNanos) / 1_000_000
  let buckets =
    r.pageBucketDistribution.sorted(by: { $0.key < $1.key }).map {
      "\($0.key / 1024)KB:\($0.value)"
    }.joined(separator: " ")
  let pad = label.padding(toLength: 20, withPad: " ", startingAt: 0)
  print(
    "  \(pad) \(String(format: "%8.1f", mbps)) MB/s  \(String(format: "%8.1f", ktps)) Ktok/s  \(String(format: "%8.1f", ms)) ms  \(r.totalTokens) tok  buckets: \(buckets)"
  )
}

let runtime = try makeMicroSwiftRuntime()

let small = makeSource(String(repeating: "let x = 42\n", count: 100))
let medium = makeSource(String(repeating: "func foo() -> Int { return 1 }\n", count: 10_000))
let large = makeSource(
  String(repeating: "let longVarName = 12345 // some comment\n", count: 100_000))
let errors = makeSource(String(repeating: "@ # $ % ^ & ~ ` \n", count: 10_000))

print("=== MicroSwift M3 Lexer Benchmark ===\n")

for (name, source) in [
  ("small (1.1KB)", small), ("medium (310KB)", medium), ("large (3.9MB)", large),
] {
  print("\(name):")
  printResult(
    "cold (1 iter)",
    LexBenchmark.benchmarkCold(source: source, artifact: runtime, iterations: 1))
  printResult(
    "cold (5 iter)",
    LexBenchmark.benchmarkCold(source: source, artifact: runtime, iterations: 5))
  printResult(
    "warm (3+5)",
    LexBenchmark.benchmarkWarm(
      source: source, artifact: runtime, warmupIterations: 3, measureIterations: 5))
  printResult(
    "warm (10+10)",
    LexBenchmark.benchmarkWarm(
      source: source, artifact: runtime, warmupIterations: 10, measureIterations: 10))
  print()
}

print("error-heavy (180KB):")
printResult(
  "error (1 iter)",
  LexBenchmark.benchmarkError(source: errors, artifact: runtime, iterations: 1))
printResult(
  "error (5 iter)",
  LexBenchmark.benchmarkError(source: errors, artifact: runtime, iterations: 5))
print()
print("=== Done ===")
