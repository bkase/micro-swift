import Foundation
import MLX
import MicroSwiftFrontend
import MicroSwiftLexerGen
import MicroSwiftTensorCore

// --- Build artifact from MicroSwift v0 spec ---

func buildArtifactAndRuntime() throws -> (LexerArtifact, ArtifactRuntime) {
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
    generatorVersion: "bench"
  )
  let runtime = try ArtifactLoader.load(artifact)
  return (artifact, runtime)
}

// --- Generate realistic source text ---

func generateSource(targetBytes: Int) -> String {
  let block = """
    func fibonacci(n: Int) -> Int {
      if n == 0 {
        return 0
      }
      if n == 1 {
        return 1
      }
      let a = fibonacci(n: n - 1)
      let b = fibonacci(n: n - 2)
      return a + b
    }
    // compute the result
    let result = fibonacci(n: 10)
    let x = 42 + result * 3

    """
  let blockBytes = block.utf8.count
  let repeats = max(1, targetBytes / blockBytes)
  return String(repeating: block, count: repeats)
}

// --- Benchmark helpers ---

struct BenchResult {
  let label: String
  let inputBytes: Int
  let iterations: Int
  let durationNanos: UInt64
  let bytesPerSecond: Double
  let tokensPerIteration: Int
}

func formatRate(_ bytesPerSec: Double) -> String {
  if bytesPerSec >= 1_000_000_000 {
    return String(format: "%.2f GB/s", bytesPerSec / 1_000_000_000)
  } else if bytesPerSec >= 1_000_000 {
    return String(format: "%.2f MB/s", bytesPerSec / 1_000_000)
  } else if bytesPerSec >= 1_000 {
    return String(format: "%.2f KB/s", bytesPerSec / 1_000)
  }
  return String(format: "%.0f B/s", bytesPerSec)
}

func printResult(_ r: BenchResult) {
  let durationMs = Double(r.durationNanos) / 1_000_000
  print("    \(r.label)")
  print("      input:            \(r.inputBytes) bytes")
  print("      iterations:       \(r.iterations)")
  print("      duration:         \(String(format: "%.2f", durationMs)) ms")
  print("      throughput:       \(formatRate(r.bytesPerSecond))")
  print("      tokens/iteration: \(r.tokensPerIteration)")
}

// --- M3 benchmark: CPU-only full lex pipeline (v0 profile) ---

func benchM3(source: SourceBuffer, runtime: ArtifactRuntime, warmup: Int, measure: Int)
  -> BenchResult
{
  let result = LexBenchmark.benchmarkWarm(
    source: source,
    artifact: runtime,
    warmupIterations: warmup,
    measureIterations: measure
  )

  return BenchResult(
    label: "M3 CPU (v0)",
    inputBytes: Int(result.totalBytes),
    iterations: measure,
    durationNanos: result.durationNanos,
    bytesPerSecond: result.bytesPerSecond,
    tokensPerIteration: result.totalTokens
  )
}

// --- M4 GPU benchmark: Full TensorLexer.lexPage with v1Fallback, MLX on GPU ---

func benchM4GPU(bytes: [UInt8], runtime: ArtifactRuntime, warmup: Int, measure: Int) -> BenchResult
{
  let validLen = Int32(bytes.count)
  let gpuOptions = LexOptions(runtimeProfile: .v1Fallback, useGPUReduction: true)

  return Device.withDefaultDevice(.gpu) {
    for _ in 0..<warmup {
      _ = TensorLexer.lexPage(
        bytes: bytes, validLen: validLen, baseOffset: 0,
        artifact: runtime, options: gpuOptions)
    }

    let start = DispatchTime.now().uptimeNanoseconds
    var tokenCount: Int32 = 0
    for _ in 0..<measure {
      let result = TensorLexer.lexPage(
        bytes: bytes, validLen: validLen, baseOffset: 0,
        artifact: runtime, options: gpuOptions)
      tokenCount += result.rowCount
    }
    let elapsed = DispatchTime.now().uptimeNanoseconds - start

    let totalBytes = bytes.count * measure
    let bytesPerSec = Double(totalBytes) * 1_000_000_000 / Double(elapsed)

    return BenchResult(
      label: "M4 GPU (v1-fallback)",
      inputBytes: bytes.count,
      iterations: measure,
      durationNanos: elapsed,
      bytesPerSecond: bytesPerSec,
      tokensPerIteration: Int(tokenCount) / max(1, measure)
    )
  }
}

// --- M4 benchmark: Full TensorLexer.lexPage with v1Fallback ---

func benchM4(bytes: [UInt8], runtime: ArtifactRuntime, warmup: Int, measure: Int) -> BenchResult {
  let validLen = Int32(bytes.count)

  for _ in 0..<warmup {
    _ = TensorLexer.lexPage(
      bytes: bytes, validLen: validLen, baseOffset: 0,
      artifact: runtime, options: LexOptions(runtimeProfile: .v1Fallback))
  }

  let start = DispatchTime.now().uptimeNanoseconds
  var tokenCount: Int32 = 0
  for _ in 0..<measure {
    let result = TensorLexer.lexPage(
      bytes: bytes, validLen: validLen, baseOffset: 0,
      artifact: runtime, options: LexOptions(runtimeProfile: .v1Fallback))
    tokenCount += result.rowCount
  }
  let elapsed = DispatchTime.now().uptimeNanoseconds - start

  let totalBytes = bytes.count * measure
  let bytesPerSec = Double(totalBytes) * 1_000_000_000 / Double(elapsed)

  return BenchResult(
    label: "M4 Metal (v1-fallback)",
    inputBytes: bytes.count,
    iterations: measure,
    durationNanos: elapsed,
    bytesPerSecond: bytesPerSec,
    tokensPerIteration: Int(tokenCount) / max(1, measure)
  )
}

// --- Main ---

setbuf(stdout, nil)  // Unbuffer stdout so output appears before any crash

do {
  let (_, runtime) = try buildArtifactAndRuntime()

  let sizes = [250, 500, 1_000, 2_500, 5_000, 10_000, 25_000, 50_000]
  let warmup = 5
  let measure = 50

  print("=== MicroSwift Release Benchmark ===")
  print("Warmup: \(warmup), Measure: \(measure) iterations per size")
  print()

  var m3Results: [BenchResult] = []
  var m4Results: [BenchResult?] = []
  var m4GPUResults: [BenchResult] = []

  for targetSize in sizes {
    let sourceText = generateSource(targetBytes: targetSize)
    let sourceBytes = Array(sourceText.utf8)
    let source = SourceBuffer(
      fileID: FileID(rawValue: 1),
      path: "bench.swift",
      bytes: Data(sourceText.utf8)
    )

    print("  --- \(sourceBytes.count) bytes ---")

    let m3 = benchM3(source: source, runtime: runtime, warmup: warmup, measure: measure)
    printResult(m3)

    // Skip M4 Metal (CPU) path for sizes > 10KB to avoid Metal executor hang
    let m4: BenchResult?
    if targetSize <= 10_000 {
      m4 = benchM4(bytes: sourceBytes, runtime: runtime, warmup: warmup, measure: measure)
      printResult(m4!)
    } else {
      m4 = nil
      print("    M4 Metal (v1-fallback) — skipped (>10KB)")
    }

    let m4gpu = benchM4GPU(bytes: sourceBytes, runtime: runtime, warmup: warmup, measure: measure)
    printResult(m4gpu)

    if let m4 {
      let cpuSpeedup = m4.bytesPerSecond / m3.bytesPerSecond
      print(String(format: "      M4-CPU speedup:   %.2fx", cpuSpeedup))
    }
    let gpuSpeedup = m4gpu.bytesPerSecond / m3.bytesPerSecond
    print(String(format: "      M4-GPU speedup:   %.2fx", gpuSpeedup))
    print()

    m3Results.append(m3)
    m4Results.append(m4)
    m4GPUResults.append(m4gpu)
  }

  print("=== Summary Table ===")
  print("  Input         M3 CPU         M4 CPU        M4 GPU        CPU-sp  GPU-sp")
  print("  " + String(repeating: "-", count: 74))
  for i in 0..<m3Results.count {
    let sizeLabel: String
    if m3Results[i].inputBytes >= 1000 {
      sizeLabel = "\(m3Results[i].inputBytes / 1000) KB"
    } else {
      sizeLabel = "\(m3Results[i].inputBytes) B"
    }
    let gpuSpeedup = m4GPUResults[i].bytesPerSecond / m3Results[i].bytesPerSecond
    let m3Rate = formatRate(m3Results[i].bytesPerSecond)
    let m4Rate = m4Results[i].map { formatRate($0.bytesPerSecond) } ?? "—"
    let m4GPURate = formatRate(m4GPUResults[i].bytesPerSecond)
    let cpuStr = m4Results[i].map { String(format: "%.2fx", $0.bytesPerSecond / m3Results[i].bytesPerSecond) } ?? "—"
    let gpuStr = String(format: "%.2fx", gpuSpeedup)
    print(
      "  \(sizeLabel.padding(toLength: 12, withPad: " ", startingAt: 0))  \(m3Rate.padding(toLength: 12, withPad: " ", startingAt: 0))  \(m4Rate.padding(toLength: 12, withPad: " ", startingAt: 0))  \(m4GPURate.padding(toLength: 12, withPad: " ", startingAt: 0))  \(cpuStr.padding(toLength: 6, withPad: " ", startingAt: 0))  \(gpuStr)"
    )
  }

} catch {
  print("ERROR: \(error)")
  exit(1)
}
