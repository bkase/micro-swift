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
    deps.stdout.write("backend: \(result.backendIdentifier)\n")
    deps.stdout.write("device: \(result.deviceIdentifier)\n")
    deps.stdout.write("pipeline: \(result.kernelPipelineIdentifier)\n")
    deps.stdout.write("fallback-positions-entered: \(result.fallbackPositionsEntered)\n")
    deps.stdout.write("fallback-dispatches: \(result.fallbackKernelExecutionCount)\n")
    deps.stdout.write("artifact-hash: \(result.artifactHash)\n")
    deps.stdout.write("fixture: \(result.fixtureIdentifier)\n")
  }
}
