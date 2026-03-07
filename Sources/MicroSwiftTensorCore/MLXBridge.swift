import Cmlx
import Foundation
import MLX

private let mlxTestBootstrap: Void = {
  let env = ProcessInfo.processInfo.environment
  let processName = ProcessInfo.processInfo.processName.lowercased()
  let isTestProcess =
    env["XCTestConfigurationFilePath"] != nil
    || env["SWIFT_TESTING"] != nil
    || env["MS_TEST"] != nil
    || processName.contains("test")
  guard isTestProcess else { return }

  var cpu = mlx_device_new_type(MLX_CPU, 0)
  defer { mlx_device_free(cpu) }
  _ = mlx_set_default_device(cpu)
}()

@inline(__always)
func withMLXCPU<R>(_ body: () -> R) -> R {
  _ = mlxTestBootstrap
  return Device.withDefaultDevice(.cpu, body)
}
