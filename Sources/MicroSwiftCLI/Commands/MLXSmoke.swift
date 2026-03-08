import ArgumentParser
import Dependencies
import Foundation

struct MLXSmoke: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "mlx-smoke",
    abstract: "Run the MLX smoke check"
  )

  @Flag(name: .shortAndLong, help: "Emit JSON output")
  var json: Bool = false

  func run() async throws {
    let deps = DependencyValues._current
    let result = try await deps.mlxRuntime.smoke()
    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      deps.stdout.write(String(decoding: data, as: UTF8.self) + "\n")
      return
    }

    deps.stdout.write("mlx-smoke: \(result.status)\n")
    deps.stdout.write("runtime-profile: \(result.runtimeProfile)\n")
    deps.stdout.write("artifact-hash: \(result.artifactHash)\n")
    deps.stdout.write("fast-backend: \(result.fastPathBackendIdentifier)\n")
    deps.stdout.write("fast-device: \(result.fastPathDeviceIdentifier)\n")
    deps.stdout.write("fast-pipeline: \(result.fastPathPipelineIdentifier)\n")
    deps.stdout.write("fast-graph-compiles: \(result.fastPathGraphCompileCount)\n")
    deps.stdout.write("fast-cache-hits: \(result.fastPathGraphCacheHitCount)\n")
    deps.stdout.write("fast-cache-misses: \(result.fastPathGraphCacheMissCount)\n")
    deps.stdout.write(
      "forbidden-mid-pipeline-host-extractions: \(result.forbiddenMidPipelineHostExtractionCount)\n"
    )
    deps.stdout.write("run-family-backend: \(result.runFamilyBackendIdentifier)\n")
    deps.stdout.write("run-family-classRun-dispatches: \(result.runFamilyClassRunDispatchCount)\n")
    deps.stdout.write("run-family-headTail-dispatches: \(result.runFamilyHeadTailDispatchCount)\n")
    deps.stdout.write("literal-workload-rows: \(result.literalWorkloadRowCount)\n")
    deps.stdout.write("run-workload-rows: \(result.runWorkloadRowCount)\n")
    deps.stdout.write("prefixed-workload-rows: \(result.prefixedWorkloadRowCount)\n")
    deps.stdout.write("fixture: \(result.fixtureIdentifier)\n")
  }
}
