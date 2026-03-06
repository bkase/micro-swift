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
    deps.stdout.write("kernel: \(result.kernel)\n")
    deps.stdout.write("runtime: \(result.version)\n")
  }
}
