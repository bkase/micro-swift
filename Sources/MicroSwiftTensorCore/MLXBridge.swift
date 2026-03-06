import MLX

private let mlxDefaultDeviceConfigured: Void = {
  Device.setDefault(device: .cpu)
}()

@inline(__always)
func withMLXCPU<R>(_ body: () -> R) -> R {
  _ = mlxDefaultDeviceConfigured
  return Device.withDefaultDevice(.cpu, body)
}
